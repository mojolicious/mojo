# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::IOLoop;

use strict;
use warnings;

use base 'Mojo::Base';
use bytes;

use Carp 'croak';
use IO::Poll qw/POLLERR POLLHUP POLLIN POLLOUT/;
use IO::Socket;
use Mojo::Buffer;

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 8192;

# Epoll support requires IO::Epoll
use constant EPOLL => ($ENV{MOJO_POLL} || $ENV{MOJO_KQUEUE})
  ? 0
  : eval { require IO::Epoll; 1 };

# IPv6 support requires IO::Socket::INET6
use constant IPV6 => $ENV{MOJO_NO_IPV6}
  ? 0
  : eval { require IO::Socket::INET6; 1 };

# KQueue support requires IO::KQueue
use constant KQUEUE => ($ENV{MOJO_POLL} || $ENV{MOJO_EPOLL})
  ? 0
  : eval { require IO::KQueue; 1 };

# TLS support requires IO::Socket::SSL
use constant TLS => $ENV{MOJO_NO_TLS}
  ? 0
  : eval { require IO::Socket::SSL; 1 };

__PACKAGE__->attr(
    [qw/lock_cb unlock_cb/] => sub {
        sub {1}
    }
);
__PACKAGE__->attr([qw/accept_timeout connect_timeout/] => 5);
__PACKAGE__->attr(max_connections                      => 1000);
__PACKAGE__->attr(timeout                              => '0.25');

__PACKAGE__->attr([qw/_connections _fds _listen _timers/] => sub { {} });
__PACKAGE__->attr([qw/_listening _running/]);
__PACKAGE__->attr(
    _loop => sub {

        # Initialize as late as possible because kqueues don't survive a fork
        return IO::KQueue->new if KQUEUE;
        return IO::Epoll->new  if EPOLL;
        return IO::Poll->new;
    }
);

# Singleton
our $LOOP;

sub new {
    my $self = shift->SUPER::new(@_);

    # Ignore PIPE signal
    $SIG{PIPE} = 'IGNORE';

    return $self;
}

sub connect {
    my $self = shift;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # Options (TLS handshake only works blocking)
    my %options = (
        Blocking => $args->{tls} ? 1 : 0,
        PeerAddr => $args->{host},
        PeerPort => $args->{port} || ($args->{tls} ? 443 : 80),
        Proto    => 'tcp',
        Type     => SOCK_STREAM
    );

    # TLS certificate verification
    if ($args->{tls} && $args->{tls_ca_file}) {
        $options{SSL_ca_file}         = $args->{tls_ca_file};
        $options{SSL_verify_mode}     = 0x01;
        $options{SSL_verify_callback} = $args->{tls_verify_cb};
    }

    # New connection
    my $class =
        TLS && $args->{tls} ? 'IO::Socket::SSL'
      : IPV6 ? 'IO::Socket::INET6'
      :        'IO::Socket::INET';
    my $socket = $class->new(%options) or return;

    # Non blocking
    $socket->blocking(0);

    # Timeout
    my $id = $self->timer(
        after => $self->connect_timeout,
        cb    => sub {
            shift->_error("$socket", 'Connect timeout.');
        }
    );

    # Add connection
    $self->_connections->{$socket} = {
        buffer        => Mojo::Buffer->new,
        connect_cb    => $args->{cb},
        connect_timer => $id,
        connecting    => 1,
        socket        => $socket
    };

    # File descriptor
    my $fd = fileno($socket);
    $self->_fds->{$fd} = "$socket";

    # Add socket to poll
    $self->writing("$socket");

    return "$socket";
}

sub connection_timeout {
    my ($self, $id, $timeout) = @_;
    $self->_connections->{$id}->{timeout} = $timeout and return $self
      if $timeout;
    return $self->_connections->{$id}->{timeout};
}

sub drop {
    my ($self, $id) = @_;

    # Drop timer?
    if ($self->_timers->{$id}) {
        delete $self->_timers->{$id};
        return $self;
    }

    # Delete connection
    my $c = delete $self->_connections->{$id};

    # Socket
    if (my $socket = $c->{socket}) {

        # Remove file descriptor
        my $fd = fileno($socket);
        delete $self->_fds->{$fd};

        # Remove socket from kqueue
        if (KQUEUE) {
            my $writing = $c->{writing};
            $self->_loop->EV_SET($fd, IO::KQueue::EVFILT_READ(),
                IO::KQueue::EV_DELETE())
              if defined $writing;
            $self->_loop->EV_SET($fd, IO::KQueue::EVFILT_WRITE(),
                IO::KQueue::EV_DELETE())
              if $writing;
        }

        # Remove socket from poll or epoll
        else { $self->_loop->remove($socket) }

        # Close socket
        close $socket;
    }

    return $self;
}

sub error_cb { shift->_add_event('error', @_) }

sub finish {
    my ($self, $id) = @_;

    # Finish connection once buffer is empty
    $self->_connections->{$id}->{finish} = 1;

    return $self;
}

sub hup_cb { shift->_add_event('hup', @_) }

# Fat Tony is a cancer on this fair city!
# He is the cancer and I am the… uh… what cures cancer?
sub listen {
    my $self = shift;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # Options (TLS handshake only works blocking)
    my %options = (
        Blocking => $args->{tls} ? 1 : 0,
        Listen => $args->{queue_size} || SOMAXCONN,
        Type => SOCK_STREAM
    );

    # Listen on UNIX domain socket
    my $listen;
    if (my $file = $args->{file}) {

        # Path
        $options{Local} = $file;

        # Create socket
        $listen = IO::Socket::UNIX->new(%options)
          or croak "Can't create listen socket: $!";
    }

    # Listen on port
    else {

        # Socket options
        my $address = $args->{address};
        $options{LocalAddr} = $address if $address;
        $options{LocalPort} = $args->{port} || 3000;
        $options{Proto}     = 'tcp';
        $options{ReuseAddr} = 1;
        my $cert = $args->{tls_cert};
        $options{SSL_cert_file} = $cert if $cert;
        my $key = $args->{tls_key};
        $options{SSL_key_file} = $key if $key;

        # Create socket
        my $class =
            TLS && $args->{tls} ? 'IO::Socket::SSL'
          : IPV6 ? 'IO::Socket::INET6'
          :        'IO::Socket::INET';
        $listen = $class->new(%options)
          or croak "Can't create listen socket: $!";
    }

    # Add listen socket
    $self->_listen->{$listen} = {socket => $listen, cb => $args->{cb}};

    # File descriptor
    my $fd = fileno($listen);
    $self->_fds->{$fd} = "$listen";

    return $self;
}

sub local_info {
    my ($self, $id) = @_;
    my $socket = $self->_connections->{$id}->{socket};
    return {address => $socket->sockhost, port => $socket->sockport};
}

sub not_writing {
    my ($self, $id) = @_;

    # Active
    $self->_active($id);

    # Connection
    my $c = $self->_connections->{$id};

    # Chunk still in buffer
    my $buffer = $c->{buffer};
    return $c->{read_only} = 1 if $buffer && $buffer->size;

    # Socket
    return unless my $socket = $c->{socket};

    # KQueue
    if (KQUEUE) {
        my $fd      = fileno($socket);
        my $writing = $c->{writing};
        $self->_loop->EV_SET($fd, IO::KQueue::EVFILT_READ(),
            IO::KQueue::EV_ADD())
          unless defined $writing;
        $self->_loop->EV_SET($fd, IO::KQueue::EVFILT_WRITE(),
            IO::KQueue::EV_DELETE())
          if $writing;
        $c->{writing} = 0;
    }

    # Epoll
    elsif (EPOLL) { $self->_loop->mask($socket, IO::Epoll::POLLIN()) }

    # Poll
    else { $self->_loop->mask($socket, POLLIN) }
}

sub read_cb { shift->_add_event('read', @_) }

sub remote_info {
    my ($self, $id) = @_;
    my $socket = $self->_connections->{$id}->{socket};
    return {address => $socket->peerhost, port => $socket->peerport};
}

sub singleton { $LOOP ||= shift->new(@_) }

sub start {
    my $self = shift;

    # Already running?
    return if $self->_running;

    # Running
    $self->_running(1);

    # Mainloop
    $self->_spin while $self->_running;

    return $self;
}

sub stop { shift->_running(0) }

sub timer {
    my $self = shift;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # Started
    $args->{started} = time;

    # Add timer
    $self->_timers->{"$args"} = $args;

    return "$args";
}

sub write_cb { shift->_add_event('write', @_) }

sub writing {
    my ($self, $id) = @_;

    # Active
    $self->_active($id);

    # Connection
    my $c = $self->_connections->{$id};

    # Socket
    return unless my $socket = $c->{socket};

    # KQueue
    if (KQUEUE) {
        my $fd      = fileno($socket);
        my $writing = $c->{writing};
        $self->_loop->EV_SET($fd, IO::KQueue::EVFILT_READ(),
            IO::KQueue::EV_ADD())
          unless defined $writing;
        $self->_loop->EV_SET($fd, IO::KQueue::EVFILT_WRITE(),
            IO::KQueue::EV_ADD())
          unless $writing;
        $c->{writing} = 1;
    }

    # Epoll
    elsif (EPOLL) {
        $self->_loop->mask($socket,
            IO::Epoll::POLLIN() | IO::Epoll::POLLOUT());
    }

    # Poll
    else { $self->_loop->mask($socket, POLLIN | POLLOUT) }
}

sub _accept {
    my ($self, $listen) = @_;

    # Accept
    my $socket = $listen->accept or return;

    # Timeout
    my $id = $self->timer(
        after => $self->accept_timeout,
        cb    => sub {
            shift->_error("$socket", 'Accept timeout.');
        }
    );

    # Add connection
    $self->_connections->{$socket} = {
        accept_timer => $id,
        accepting    => 1,
        buffer       => Mojo::Buffer->new,
        socket       => $socket
    };

    # File descriptor
    my $fd = fileno($socket);
    $self->_fds->{$fd} = "$socket";

    # Accept callback
    $self->_listen->{$listen}->{cb}->($self, "$socket");

    # Unlock
    $self->unlock_cb->($self);

    # Remove listen sockets
    for my $l (keys %{$self->_listen}) {
        my $socket = $self->_listen->{$l}->{socket};

        # Remove listen socket from kqueue
        if (KQUEUE) {
            $self->_loop->EV_SET(fileno($socket), IO::KQueue::EVFILT_READ(),
                IO::KQueue::EV_DELETE());
        }

        # Remove listen socket from poll or epoll
        else { $self->_loop->remove($socket) }
    }

    # Not listening anymore
    $self->_listening(0);
}

sub _accepting {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->_connections->{$id};

    # Connected?
    return unless $c->{socket}->connected;

    # Accepted
    delete $c->{accepting};

    # Remove timeout
    $self->drop(delete $c->{accept_timer});

    # Non blocking
    $c->{socket}->blocking(0);

    # Add socket to poll
    $self->not_writing($id);
}

sub _active {
    my ($self, $id) = @_;
    return $self->_connections->{$id}->{active} = time;
}

sub _add_event {
    my ($self, $event, $id, $cb) = @_;

    # Add event callback to connection
    $self->_connections->{$id}->{$event} = $cb;

    return $self;
}

sub _connecting {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->_connections->{$id};

    # Not yet connected
    return unless $c->{socket}->connected;

    # Connected
    delete $c->{connecting};

    # Remove timeout
    $self->drop(delete $c->{connect_timer});

    # Connect callback
    my $cb = $c->{connect_cb};
    $self->$cb($id) if $cb;
}

sub _error {
    my ($self, $id, $error) = @_;

    # Get error callback
    my $event = $self->_connections->{$id}->{error};

    # Cleanup
    $self->drop($id);

    # No event
    return unless $event;

    # Default error
    $error ||= 'Connection error on poll layer.';

    # Error callback
    $self->$event($id, $error);
}

sub _hup {
    my ($self, $id) = @_;

    # Get hup callback
    my $event = $self->_connections->{$id}->{hup};

    # Cleanup
    $self->drop($id);

    # No event
    return unless $event;

    # HUP callback
    $self->$event($id);
}

sub _is_listening {
    my $self = shift;
    return 1
      if keys %{$self->_listen}
          && keys %{$self->_connections} < $self->max_connections
          && $self->lock_cb->($self, !keys %{$self->_connections});
    return 0;
}

sub _prepare {
    my $self = shift;

    # Prepare
    for my $id (keys %{$self->_connections}) {

        # Connection
        my $c = $self->_connections->{$id};

        # Accepting?
        $self->_accepting($id) if $c->{accepting};

        # Connecting?
        $self->_connecting($id) if $c->{connecting};

        # Drop if buffer is empty
        $self->drop($id) and next
          if $c->{finish} && (!$c->{buffer} || !$c->{buffer}->size);

        # Read only
        $self->not_writing($id) if delete $c->{read_only};

        # Timeout
        my $timeout = $c->{timeout} || 15;

        # Last active
        my $time = $c->{active} || $self->_active($id);

        # HUP
        $self->_hup($id) if (time - $time) >= $timeout;
    }

    # Nothing to do
    return $self->_running(0)
      unless keys %{$self->_connections} || keys %{$self->_listen};

    return;
}

sub _read {
    my ($self, $id) = @_;

    # Listen socket? (new connection)
    my $listen;
    for my $l (keys %{$self->_listen}) {
        my $socket = $self->_listen->{$l}->{socket};
        if ($id eq $socket) {
            $listen = $socket;
            last;
        }
    }

    # Accept new connection
    return $self->_accept($listen) if $listen;

    # Connection
    my $c = $self->_connections->{$id};

    # Read chunk
    my $read = $c->{socket}->sysread(my $buffer, CHUNK_SIZE, 0);

    # Read error
    return $self->_error($id)
      unless defined $read && defined $buffer && length $buffer;

    # Callback
    return unless my $event = $c->{read};
    $self->$event($id, $buffer);

    # Active
    $self->_active($id);
}

sub _spin {
    my $self = shift;

    # Listening?
    if (!$self->_listening && $self->_is_listening) {

        # Add listen sockets
        for my $l (keys %{$self->_listen}) {
            my $listen = $self->_listen->{$l}->{socket};
            my $fd     = fileno($listen);

            # KQueue
            $self->_loop->EV_SET($fd, IO::KQueue::EVFILT_READ(),
                IO::KQueue::EV_ADD())
              if KQUEUE;

            # Epoll
            $self->_loop->mask($listen, IO::Epoll::POLLIN()) if EPOLL;

            # Poll
            $self->_loop->mask($listen, POLLIN) unless KQUEUE || EPOLL;
        }

        # Listening
        $self->_listening(1);
    }

    # Prepare
    return if $self->_prepare;

    # KQueue
    if (KQUEUE) {
        my $kq = $self->_loop;

        # Catch interrupted system call errors
        my @ret;
        eval { @ret = $kq->kevent($self->timeout * 10) };
        die "KQueue error: $@" if $@;

        # Events
        for my $kev (@ret) {
            my ($fd, $filter, $flags, $fflags) = @$kev;

            # Id
            my $id = $self->_fds->{$fd};
            next unless $id;

            # Read
            $self->_read($id) if $filter == IO::KQueue::EVFILT_READ();

            # Write
            $self->_write($id) if $filter == IO::KQueue::EVFILT_WRITE();

            if ($flags == IO::KQueue::EV_EOF()) {
                if   ($fflags) { $self->_error($id) }
                else           { $self->_hup($id) }
            }
        }
    }

    # Epoll
    elsif (EPOLL) {
        my $epoll = $self->_loop;
        $epoll->poll($self->timeout);

        # Error
        $self->_error("$_") for $epoll->handles(IO::Epoll::POLLERR());

        # HUP
        $self->_hup("$_") for $epoll->handles(IO::Epoll::POLLHUP());

        # Read
        $self->_read("$_") for $epoll->handles(IO::Epoll::POLLIN());

        # Write
        $self->_write("$_") for $epoll->handles(IO::Epoll::POLLOUT());
    }

    # Poll
    else {
        my $poll = $self->_loop;
        $poll->poll($self->timeout);

        # Error
        $self->_error("$_") for $poll->handles(POLLERR);

        # HUP
        $self->_hup("$_") for $poll->handles(POLLHUP);

        # Read
        $self->_read("$_") for $poll->handles(POLLIN);

        # Write
        $self->_write("$_") for $poll->handles(POLLOUT);
    }

    # Timers
    $self->_timer;
}

sub _timer {
    my $self = shift;

    # Timers
    for my $id (keys %{$self->_timers}) {
        my $t = $self->_timers->{$id};

        # Timer
        my $run = 0;
        if (defined $t->{after} && $t->{after} <= time - $t->{started}) {

            # Done
            delete $t->{after};
            $run++;
        }

        # Recurring
        elsif (!defined $t->{after} && defined $t->{interval}) {
            $t->{last} ||= 0;
            $run++ if $t->{last} + $t->{interval} <= time;
        }

        # Callback
        if ((my $cb = $t->{cb}) && $run) {
            $self->$cb("$t");
            $t->{last} = time;
        }

        # Continue?
        $self->drop($id) unless defined $t->{after} || defined $t->{interval};
    }
}

sub _write {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->_connections->{$id};

    # Connect has just completed
    return if $c->{connecting};

    # Buffer
    my $buffer = $c->{buffer};

    # Try to fill the buffer before writing
    while ($buffer->size < CHUNK_SIZE && !$c->{read_only} && !$c->{finish}) {

        # No write callback
        last unless my $event = $c->{write};

        # Write callback
        my $chunk = $self->$event($id);

        # Done for now
        last unless defined $chunk && length $chunk;

        # Add to buffer
        $buffer->add_chunk($chunk);
    }

    # Try to write whole buffer
    my $chunk = $buffer->to_string;

    # Write
    my $written = $c->{socket}->syswrite($chunk, length $chunk);

    # Write error
    return $self->_error($id) unless defined $written;

    # Remove written chunk from buffer
    $buffer->remove($written);

    # Active
    $self->_active($id);
}

1;
__END__

=head1 NAME

Mojo::IOLoop - IO Loop

=head1 SYNOPSIS

    use Mojo::IOLoop;

    # Create loop
    my $loop = Mojo::IOLoop->new;

    # Listen on port 3000
    $loop->listen(
        port => 3000,
        cb   => sub {
            my ($self, $id) = @_;

            # Incoming data
            $self->read_cb($id => sub {
                my ($self, $id, $chunk) = @_;

                # Got some data, time to write
                $self->writing($id);
            });

            # Ready to write
            $self->write_cb($id => sub {
                my ($self, $id) = @_;

                # Back to reading only
                $self->not_writing($id);

                # The loop will take care of buffering for us
                return 'HTTP/1.1 200 OK';
            });
        }
    );

    # Connect to port 3000 with TLS activated
    my $id = $loop->connect(host => 'localhost', port => 3000, tls => 1);

    # Loop starts writing
    $loop->writing($id);

    # Writing request
    $loop->write_cb($id => sub {
        my ($self, $id) = @_;

        # Back to reading only
        $self->not_writing($id);

        # The loop will take care of buffering for us
        return "GET / HTTP/1.1\r\n\r\n";
    });

    # Reading response
    $loop->read_cb($id => sub {
        my ($self, $id, $chunk) = @_;

        # Time to write more
        $self->writing($id);
    });

    # Add a timer
    $loop->timer(after => 5, cb => sub {
        my $self = shift;
        $self->drop($id);
    });

    # Add another timer
    $loop->timer(interval => 3, cb => sub {
        print "Timer is running again!\n";
    });

    # Start and stop loop
    $loop->start;
    $loop->stop;

=head1 DESCRIPTION

L<Mojo::IOLoop> is a general purpose IO loop for TCP clients and servers,
easy to subclass and extend.
L<IO::Poll>, L<IO::KQueue>, L<IO::Epoll>, L<IO::Socket::INET6> and
L<IO::Socket::SSL> are supported transparently.

=head2 ATTRIBUTES

L<Mojo::IOLoop> implements the following attributes.

=head2 C<accept_timeout>

    my $timeout = $loop->accept_timeout;
    $loop       = $loop->accept_timeout(5);

=head2 C<connect_timeout>

    my $timeout = $loop->connect_timeout;
    $loop       = $loop->connect_timeout(5);

=head2 C<lock_cb>

    my $cb = $loop->lock_cb;
    $loop  = $loop->lock_cb(sub { ... });

=head2 C<max_connections>

    my $max = $loop->max_connections;
    $loop   = $loop->max_connections(1000);

=head2 C<unlock_cb>

    my $cb = $loop->unlock_cb;
    $loop  = $loop->unlock_cb(sub { ... });

=head2 C<timeout>

    my $timeout = $loop->timeout;
    $loop       = $loop->timeout(5);

=head1 METHODS

L<Mojo::IOLoop> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $loop = Mojo::IOLoop->new;

=head2 C<connect>

    my $c = $loop->connect(
        address => '127.0.0.1',
        port    => 3000,
        cb      => sub {...}
    );
    my $c = $loop->connect({
        address => '127.0.0.1',
        port    => 3000,
        cb      => sub {...}
    });

=head2 C<connection_timeout>

    my $timeout = $loop->connection_timeout($id);
    $loop       = $loop->connection_timeout($id => 45);

=head2 C<drop>

    $loop = $loop->drop($id);

=head2 C<error_cb>

    $loop = $loop->error_cb($id => sub { ... });

=head2 C<finish>

    $loop = $loop->finish($id);

=head2 C<hup_cb>

    $loop = $loop->hup_cb($id => sub { ... });

=head2 C<listen>

    $loop->listen(port => 3000);
    $loop->listen({port => 3000});

=head2 C<local_info>

    my $info = $loop->local_info($id);

=head2 C<not_writing>

    $loop->not_writing($id);

=head2 C<read_cb>

    $loop = $loop->read_cb($id => sub { ... });

=head2 C<remote_info>

    my $info = $loop->remote_info($id);

=head2 C<singleton>

    my $loop = Mojo::IOLoop->singleton;

=head2 C<start>

    $loop->start;

=head2 C<stop>

    $loop->stop;

=head2 C<timer>

    my $id = $loop->timer(after => 5, cb => sub {...});
    my $id = $loop->timer(interval => 5, cb => sub {...});

=head2 C<write_cb>

    $loop = $loop->write_cb($id => sub { ... });

=head2 C<writing>

    $loop->writing($id);

=cut
