# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::IOLoop;

use strict;
use warnings;

use base 'Mojo::Base';
use bytes;

use Carp 'croak';
use IO::Poll qw/POLLERR POLLHUP POLLIN POLLOUT/;
use IO::Socket;
use Mojo::Buffer;

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 4096;
use constant EPOLL => ($ENV{MOJO_POLL} || $ENV{MOJO_KQUEUE})
  ? 0
  : eval { require IO::EPoll; 1 };
use constant KQUEUE => ($ENV{MOJO_POLL} || $ENV{MOJO_EPOLL})
  ? 0
  : eval { require IO::KQueue; 1 };

__PACKAGE__->attr(
    [qw/accept_cb lock_cb unlock_cb/] => sub {
        sub {1}
    }
);
__PACKAGE__->attr([qw/accept_timeout connect_timeout/] => 5);
__PACKAGE__->attr([qw/clients servers connecting/]     => 0);
__PACKAGE__->attr(max_clients                          => 1000);
__PACKAGE__->attr(timeout                              => '0.25');

__PACKAGE__->attr(_accepted               => sub { [] });
__PACKAGE__->attr([qw/_connections _fds/] => sub { {} });
__PACKAGE__->attr([qw/_listen _listening _running/]);
__PACKAGE__->attr(
    _loop => sub {
        return IO::KQueue->new if KQUEUE;
        return IO::EPoll->new  if EPOLL;
        return IO::Poll->new;
    }
);

# Singleton
our $LOOP;

# Instantiate singleton
sub new { $LOOP ||= shift->SUPER::new(@_) }

sub connect {
    my $self = shift;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # New connection
    my $socket = IO::Socket::INET->new(
        Proto => 'tcp',
        Type  => SOCK_STREAM
    ) or return;

    # Non blocking
    $socket->blocking(0);

    # Connect
    my $sin = sockaddr_in($args->{port} || 80, inet_aton($args->{address}));
    $socket->connect($sin);

    # Add connection
    $self->_connections->{$socket} = {
        buffer        => Mojo::Buffer->new,
        socket        => $socket,
        connect_cb    => $args->{cb},
        connecting    => 1,
        connect_start => time
    };

    # File descriptor
    my $fd = fileno($socket);
    $self->_fds->{$fd} = "$socket";

    # Connecting counter
    $self->connecting($self->connecting + 1);

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

    # Client counter
    $self->clients($self->clients - 1)
      if $self->_connections->{$id}->{client};

    # Server counter
    $self->servers($self->servers - 1)
      if $self->_connections->{$id}->{server};

    # Connecting counter
    $self->connecting($self->connecting - 1)
      if $self->_connections->{$id}->{connecting};

    # Socket
    if (my $socket = $self->_connections->{$id}->{socket}) {

        # Remove file descriptor
        my $fd = fileno($socket);
        delete $self->_fds->{$fd};

        # Remove socket from kqueue
        if (KQUEUE) {
            my $writing = $self->_connections->{$id}->{writing};
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

    # Remove connection
    delete $self->_connections->{$id};

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

    # Options
    my %options = (
        Listen => $args->{queue_size} || SOMAXCONN,
        Type => SOCK_STREAM
    );

    # Listen on UNIX domain socket
    my $listen;
    if (my $file = $args->{file}) {

        # Options
        $options{Local} = $file;

        # Create socket
        $listen = IO::Socket::UNIX->new(%options)
          or croak "Can't create listen socket: $!";
    }

    # Listen on port
    else {

        # Options
        my $address = $args->{address};
        $options{LocalAddr} = $address if $address;
        $options{LocalPort} = $args->{port} || 3000;
        $options{Proto}     = 'tcp';
        $options{ReuseAddr} = 1;

        # Create socket
        $listen = IO::Socket::INET->new(%options)
          or croak "Can't create listen socket: $!";
    }

    # Non blocking
    $listen->blocking(0);

    # Add listen socket
    $self->_listen($listen);

    # File descriptor
    my $fd = fileno($listen);
    $self->_fds->{$fd} = "$listen";

    return $self;
}

sub local_info {
    my ($self, $id) = @_;
    my ($port, $addr) =
      sockaddr_in(getsockname($self->_connections->{$id}->{socket}));
    return {address => inet_ntoa($addr), port => $port};
}

sub not_writing {
    my ($self, $id) = @_;

    # Chunk still in buffer
    my $buffer = $self->_connections->{$id}->{buffer};
    if ($buffer && $buffer->size) {
        $self->_connections->{$id}->{read_only} = 1;
    }

    # Not writing
    elsif (my $socket = $self->_connections->{$id}->{socket}) {

        # KQueue
        if (KQUEUE) {
            my $fd      = fileno($socket);
            my $writing = $self->_connections->{$id}->{writing};
            $self->_loop->EV_SET($fd, IO::KQueue::EVFILT_READ(),
                IO::KQueue::EV_ADD())
              unless defined $writing;
            $self->_loop->EV_SET($fd, IO::KQueue::EVFILT_WRITE(),
                IO::KQueue::EV_DELETE())
              if $writing;
            $self->_connections->{$id}->{writing} = 0;
        }

        # EPoll
        elsif (EPOLL) { $self->_loop->mask($socket, IO::EPoll::POLLIN()) }

        # Poll
        else { $self->_loop->mask($socket, POLLIN) }
    }

    # Time
    $self->_connections->{$id}->{time} = time;
}

sub read_cb { shift->_add_event('read', @_) }

sub remote_info {
    my ($self, $id) = @_;
    my ($port, $addr) =
      sockaddr_in(getpeername($self->_connections->{$id}->{socket}));
    return {address => inet_ntoa($addr), port => $port};
}

sub start {
    my $self = shift;

    # Already running?
    return if $self->_running;

    # Signals
    $SIG{PIPE} = 'IGNORE';
    $SIG{HUP} = sub { $self->_running(0) };

    # Running
    $self->_running(1);

    # Mainloop
    $self->_spin while $self->_running;

    return $self;
}

sub stop { shift->_running(0) }

sub write_cb { shift->_add_event('write', @_) }

sub writing {
    my ($self, $id) = @_;

    # Writing
    if (my $socket = $self->_connections->{$id}->{socket}) {

        # KQueue
        if (KQUEUE) {
            my $fd      = fileno($socket);
            my $writing = $self->_connections->{$id}->{writing};
            $self->_loop->EV_SET($fd, IO::KQueue::EVFILT_READ(),
                IO::KQueue::EV_ADD())
              unless defined $writing;
            $self->_loop->EV_SET($fd, IO::KQueue::EVFILT_WRITE(),
                IO::KQueue::EV_ADD())
              unless $writing;
            $self->_connections->{$id}->{writing} = 1;
        }

        # EPoll
        elsif (EPOLL) {
            $self->_loop->mask($socket,
                IO::EPoll::POLLIN() | IO::EPoll::POLLOUT());
        }

        # Poll
        else { $self->_loop->mask($socket, POLLIN | POLLOUT) }
    }

    # Time
    $self->_connections->{$id}->{time} = time;
}

sub _accept {
    my $self = shift;

    # Accepted?
    my @accepted;
    for my $accept (@{$self->_accepted}) {

        # New socket
        my $socket = $accept->[0];

        # Not yet
        unless ($socket->connected) {

            # Timeout
            $self->_error("$socket", 'Accept timeout.') and next
              if time - $accept->[1] > $self->accept_timeout;

            # Another try
            push @accepted, $accept;
            next;
        }

        # Non blocking
        $socket->blocking(0);

        # Add socket to poll
        $self->not_writing("$socket");
    }
    $self->_accepted(\@accepted);
}

sub _add_event {
    my ($self, $event, $id, $cb) = @_;

    # Add event callback to connection
    $self->_connections->{$id}->{$event} = $cb;

    return $self;
}

sub _connect {
    my $self = shift;

    # Connecting
    my $c = $self->_connections;
    for my $id (keys %$c) {

        # Connecting?
        my $connect = $c->{$id};
        next unless $connect->{connecting};

        # New socket
        my $socket = $connect->{socket};

        # Not yet connected
        if (!$socket->connected) {

            # Timeout
            if (time - $connect->{connect_start} > $self->connect_timeout) {
                $self->_error("$socket", 'Connect timeout.');
                $self->drop($id);
            }

        }

        # Connected
        else {

            # Connected counter
            $connect->{connecting} = 0;
            $self->connecting($self->connecting - 1);

            # Server counter
            $connect->{server} = 1;
            $self->servers($self->servers + 1);

            # Connect callback
            my $cb = $connect->{connect_cb};
            $self->$cb("$socket") if $cb;
        }
    }
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
      if $self->_listen
          && $self->clients < $self->max_clients
          && $self->lock_cb->($self, !keys %{$self->_connections});
    return 0;
}

sub _prepare {
    my $self = shift;

    # Accept
    $self->_accept;

    # Connect
    $self->_connect if $self->connecting;

    # Check timeouts
    my $c = $self->_connections;
    for my $id (keys %$c) {

        # Drop if buffer is empty
        $self->drop($id)
          and next
          if $c->{$id}->{finish} && (!$c->{$id}->{buffer}
                  || !$c->{$id}->{buffer}->size);

        # Read only
        $self->not_writing($id) if delete $c->{$id}->{read_only};

        # Timeout
        my $timeout = $c->{$id}->{timeout} || 15;

        # Last active
        my $time = $c->{$id}->{time} ||= time;

        # HUP
        $self->_hup($id) if (time - $time) >= $timeout;
    }

    # Nothing to do
    return $self->_running(0)
      unless keys %{$self->_connections}
          || $self->_listen
          || $self->connecting;

    return;
}

sub _read {
    my ($self, $id) = @_;

    # New connection
    if ($self->_listen && $id eq $self->_listen) {

        # Accept
        my $socket = $self->_listen->accept or return;
        push @{$self->_accepted}, [$socket, time];

        # Add connection
        $self->_connections->{$socket} = {
            buffer => Mojo::Buffer->new,
            client => 1,
            socket => $socket
        };

        # File descriptor
        my $fd = fileno($socket);
        $self->_fds->{$fd} = "$socket";

        # Client counter
        $self->clients($self->clients + 1);

        # Accept callback
        $self->accept_cb->($self, "$socket");

        # Unlock
        $self->unlock_cb->($self);

        # Remove listen socket from kqueue
        if (KQUEUE) {
            $self->_loop->EV_SET(fileno($self->_listen),
                IO::KQueue::EVFILT_READ(), IO::KQueue::EV_DELETE());
        }

        # Remove listen socket from poll or epoll
        else { $self->_loop->remove($self->_listen) }

        # Not listening anymore
        $self->_listening(0);

        return;
    }

    # Conenction
    my $c = $self->_connections->{$id};

    # Read chunk
    my $read = $c->{socket}->sysread(my $buffer, CHUNK_SIZE, 0);

    # Read error
    return $self->_error($id)
      unless defined $read && defined $buffer && length $buffer;

    # Get read callback
    return unless my $event = $c->{read};

    # Read callback
    $self->$event($id, $buffer);

    # Time
    $c->{time} = time;
}

sub _spin {
    my $self = shift;

    # Listening?
    if (!$self->_listening && $self->_is_listening) {
        my $fd = fileno($self->_listen);
        $self->_loop->EV_SET($fd, IO::KQueue::EVFILT_READ(),
            IO::KQueue::EV_ADD())
          if KQUEUE;
        $self->_loop->mask($self->_listen, IO::EPoll::POLLIN()) if EPOLL;
        $self->_loop->mask($self->_listen, POLLIN) unless KQUEUE || EPOLL;
        $self->_listening(1);
    }

    # Prepare
    return if $self->_prepare;

    # KQueue
    if (KQUEUE) {
        my $kq  = $self->_loop;
        my @ret = $kq->kevent($self->timeout * 1000);

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

    # EPoll
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
    while ($buffer->size < CHUNK_SIZE
        && !$c->{read_only}
        && !$c->{finish})
    {

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

    # Time
    $c->{time} = time;
}

1;
__END__

=head1 NAME

Mojo::IOLoop - IO Loop

=head1 SYNOPSIS

    use Mojo::IOLoop;

    # Create loop and listen on port 3000
    my $loop = Mojo::IOLoop->new;
    $loop->listen(port => 3000);

    # Accept connections
    $loop->accept_cb(sub {
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
    });

    # Start and stop loop
    $loop->start;
    $loop->stop;

=head1 DESCRIPTION

L<Mojo::IOLoop> is a general purpose IO loop for TCP clients and servers,
easy to subclass and extend.

=head2 ATTRIBUTES

L<Mojo::IOLoop> implements the following attributes.

=head2 C<accept_cb>

    my $cb = $loop->accept_cb;
    $loop  = $loop->accept_cb(sub { ... });

=head2 C<accept_timeout>

    my $timeout = $loop->accept_timeout;
    $loop       = $loop->accept_timeout(5);

=head2 C<clients>

    my $clients = $loop->clients;
    $loop       = $loop->clients(25);

=head2 C<connect_timeout>

    my $timeout = $loop->connect_timeout;
    $loop       = $loop->connect_timeout(5);

=head2 C<connecting>

    my $connecting = $loop->connecting;
    $loop          = $loop->connecting(25);

=head2 C<lock_cb>

    my $cb = $loop->lock_cb;
    $loop  = $loop->lock_cb(sub { ... });

=head2 C<max_clients>

    my $max = $loop->max_clients;
    $loop   = $loop->max_clients(1000);

=head2 C<servers>

    my $servers = $loop->servers;
    $loop       = $loop->servers(25);

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

=head2 C<start>

    $loop->start;

=head2 C<stop>

    $loop->stop;

=head2 C<write_cb>

    $loop = $loop->write_cb($id => sub { ... });

=head2 C<writing>

    $loop->writing($id);

=cut
