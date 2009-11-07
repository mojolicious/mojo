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

__PACKAGE__->attr(
    [qw/accept_cb connect_cb lock_cb unlock_cb/] => sub {
        sub {1}
    }
);
__PACKAGE__->attr([qw/accept_timeout connect_timeout/] => 5);
__PACKAGE__->attr([qw/clients servers/]                => 0);
__PACKAGE__->attr(max_clients                          => 1000);
__PACKAGE__->attr(timeout                              => '0.25');

__PACKAGE__->attr([qw/_accepted _connecting/] => sub { [] });
__PACKAGE__->attr(_connections                => sub { {} });
__PACKAGE__->attr(_poll                       => sub { IO::Poll->new });
__PACKAGE__->attr([qw/_listen _running/]);

# Singleton
my $LOOP;

# Instantiate singleton
sub new { $LOOP ||= shift->SUPER::new(@_) }

sub connect {
    my $self = shift;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # New connection
    my $new = IO::Socket::INET->new(
        Proto => 'tcp',
        Type  => SOCK_STREAM
    );

    # Non blocking
    $new->blocking(0);

    # Connect
    my $sin = sockaddr_in($args->{port} || 80, inet_aton($args->{address}));
    $new->connect($sin);

    # Connecting
    push @{$self->_connecting}, [$new, time];

    return $new;
}

sub connection_timeout {
    my ($self, $socket, $timeout) = @_;
    $self->_connections->{$socket}->{timeout} = $timeout and return $self
      if $timeout;
    return $self->_connections->{$socket}->{timeout};
}

sub drop {
    my ($self, $socket) = @_;

    # Client counter
    $self->clients($self->clients - 1)
      if $self->_connections->{$socket}->{client};

    # Server counter
    $self->servers($self->servers - 1)
      if $self->_connections->{$socket}->{server};

    # Remove socket from poll
    $self->_poll->remove($socket);

    # Remove connection
    delete $self->_connections->{$socket};

    # Close socket
    close $socket;

    return $self;
}

sub error_cb { shift->_add_event('error', @_) }
sub hup_cb   { shift->_add_event('hup',   @_) }

# Fat Tony is a cancer on this fair city!
# He is the cancer and I am the… uh… what cures cancer?
sub listen {
    my $self = shift;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # Options
    my %options = (
        Listen    => $args->{queue_size} || SOMAXCONN,
        LocalPort => $args->{port}       || 3000,
        Proto     => 'tcp',
        ReuseAddr => 1,
        Type      => SOCK_STREAM
    );
    my $address = $args->{address};
    $options{LocalAddr} = $address if $address;

    # Create socket
    my $listen = IO::Socket::INET->new(%options)
      or croak "Can't create listen socket: $!";

    # Non blocking
    $listen->blocking(0);

    # Add listen socket
    $self->_listen($listen);

    return $self;
}

sub local_info {
    my ($self, $socket) = @_;
    my ($port, $addr)   = sockaddr_in(getsockname($socket));
    return (inet_ntoa($addr), $port);
}

sub not_writing {
    my ($self, $socket) = @_;

    # Chunk still in buffer
    my $buffer = $self->_connections->{$socket}->{buffer};
    if ($buffer && $buffer->size) {
        $self->_connections->{$socket}->{read_only} = 1;
    }

    # Not writing
    else { $self->_poll->mask($socket, POLLIN) }

    # Time
    $self->_connections->{$socket}->{time} = time;
}

sub read_cb { shift->_add_event('read', @_) }

sub remote_info {
    my ($self, $socket) = @_;
    my ($port, $addr)   = sockaddr_in(getpeername($socket));
    return (inet_ntoa($addr), $port);
}

sub start {
    my $self = shift;

    # Already running?
    return if $self->_running;

    # Signals
    $SIG{PIPE} = 'IGNORE';
    $SIG{HUP} = sub { $self->_running(0) };

    # Mainloop
    $self->_running(1);
    $self->_spin while $self->_running;

    return $self;
}

sub stop { shift->_running(0) }

sub write_cb { shift->_add_event('write', @_) }

sub writing {
    my ($self, $socket) = @_;

    # Writing
    $self->_poll->mask($socket, POLLIN | POLLOUT);

    # Time
    $self->_connections->{$socket}->{time} = time;
}

sub _accept {
    my $self = shift;

    # Accepted?
    my @accepted;
    for my $accept (@{$self->_accepted}) {

        # New socket
        my $new = $accept->[0];

        # Not yet
        unless ($new->connected) {

            # Timeout
            $self->_error($new, 'Accept timeout.') and next
              if time - $accept->[1] < $self->accept_timeout;

            # Another try
            push @accepted, $accept;
            next;
        }

        # Non blocking
        $new->blocking(0);

        # Add socket to poll
        $self->not_writing($new);
    }
    $self->_accepted(\@accepted);
}

sub _add_event {
    my ($self, $event, $socket, $cb) = @_;

    # Add event callback to connection
    $self->_connections->{$socket}->{$event} = $cb;

    return $self;
}

sub _connect {
    my $self = shift;

    # Connecting
    my @connecting;
    for my $connect (@{$self->_connecting}) {

        # New socket
        my $new = $connect->[0];

        # Not yet connected
        if (!$new->connected) {

            # Timeout
            $self->_error($new, 'Connect timeout.') and next
              if time - $connect->[1] > $self->connect_timeout;

            # Another try
            push @connecting, $connect;
        }

        # Connected
        else {

            # Add connection
            $self->_connections->{$new} =
              {buffer => Mojo::Buffer->new, server => 1};

            # Server counter
            $self->servers($self->servers + 1);

            # Connect callback
            $self->connect_cb->($self, $new);

            # Add socket to poll
            $self->writing($new);
        }
    }
    $self->_connecting(\@connecting);
}

sub _error {
    my ($self, $socket, $error) = @_;

    # Get error callback
    my $event = $self->_connections->{$socket}->{error};

    # Cleanup
    $self->drop($socket);

    # No event
    return unless $event;

    # Default error
    $error ||= 'Connection error on poll layer.';

    # Error callback
    $self->$event($socket, $error);
}

sub _hup {
    my ($self, $socket) = @_;

    # Get hup callback
    my $event = $self->_connections->{$socket}->{hup};

    # Cleanup
    $self->drop($socket);

    # No event
    return unless $event;

    # HUP callback
    $self->$event($socket);
}

sub _prepare {
    my $self = shift;

    # Check timeouts
    for my $socket (keys %{$self->_connections}) {

        # Read only
        $self->not_writing($socket)
          if delete $self->_connections->{$socket}->{read_only};

        # Timeout
        my $timeout = $self->_connections->{$socket}->{timeout} || 15;

        # Last active
        my $time = $self->_connections->{$socket}->{time} ||= time;

        # HUP
        $self->_hup($socket) if (time - $time) >= $timeout;
    }
}

sub _read {
    my ($self, $socket) = @_;

    # New connection
    if ($self->_listen && $socket eq $self->_listen) {

        # Accept
        my $new = $socket->accept;
        push @{$self->_accepted}, [$new, time];

        # Add connection
        $self->_connections->{$new} =
          {buffer => Mojo::Buffer->new, client => 1};

        # Client counter
        $self->clients($self->clients + 1);

        # Accept callback
        $self->accept_cb->($self, $new);

        # Unlock
        $self->unlock_cb->($self);

        return;
    }

    # Conenction
    my $c = $self->_connections->{$socket};

    # Read chunk
    my $read = $socket->sysread(my $buffer, CHUNK_SIZE, 0);

    # Read error
    return $self->_error($socket)
      unless defined $read && defined $buffer && length $buffer;

    # Get read callback
    return unless my $event = $c->{read};

    # Read callback
    $self->$event($socket, $buffer);

    # Time
    $c->{time} = time;
}

sub _spin {
    my $self = shift;

    # Listening?
    my $poll      = $self->_poll;
    my $listening = 1
      if $self->_listen && $self->clients < $self->max_clients;
    my $cs = keys %{$self->_connections};
    if ($listening && $self->lock_cb->($self, !$cs)) {
        $self->not_writing($self->_listen);
    }
    elsif ($self->_listen) { $poll->remove($self->_listen) }

    # Accept
    $self->_accept;

    # Connect
    $self->_connect;

    # Prepare
    $self->_prepare;

    # Poll
    $poll->poll($self->timeout);

    # Error
    $self->_error($_) for $poll->handles(POLLERR);

    # HUP
    $self->_hup($_) for $poll->handles(POLLHUP);

    # Read
    $self->_read($_) for $poll->handles(POLLIN);

    # Write
    $self->_write($_) for $poll->handles(POLLOUT);
}

sub _write {
    my ($self, $socket) = @_;

    # Conenction
    my $c = $self->_connections->{$socket};

    # Buffer
    my $buffer = $c->{buffer};

    # Not enough bytes in buffer
    unless ($buffer->size >= CHUNK_SIZE && $c->{read_only}) {

        # Get write callback
        return unless my $event = $c->{write};

        # Write callback
        $buffer->add_chunk($self->$event($socket));
    }

    # Try to write whole buffer
    my $chunk = $buffer->to_string;

    # Write
    my $written = $socket->syswrite($chunk, length $chunk);

    # Write error
    return $self->_error($socket) unless defined $written;

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
        my ($self, $c) = @_;

        # Incoming data
        $self->read_cb($c => sub {
            my ($self, $c, $chunk) = @_;

            # Got some data, time to write
            $self->writing($c);
        });

        # Ready to write
        $self->write_cb($c => sub {
            my ($self, $c) = @_;

            # Back to reading only
            $self->not_writing($c);

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

=head2 C<connect_cb>

    my $cb = $loop->connect_cb;
    $loop  = $loop->connect_cb(sub { ... });

=head2 C<connect_timeout>

    my $timeout = $loop->connect_timeout;
    $loop       = $loop->connect_timeout(5);

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

    my $c = $loop->connect(address => '127.0.0.1', port => 3000);
    my $c = $loop->connect({address => '127.0.0.1', port => 3000});

=head2 C<connection_timeout>

    my $timeout = $loop->connection_timeout($c);
    $loop       = $loop->connection_timeout($c => 45);

=head2 C<drop>

    $loop = $loop->drop($c);

=head2 C<error_cb>

    $loop = $loop->error_cb($c => sub { ... });

=head2 C<hup_cb>

    $loop = $loop->hup_cb($c => sub { ... });

=head2 C<listen>

    $loop->listen(port => 3000);
    $loop->listen({port => 3000});

=head2 C<local_info>

    my ($address, $port) = $loop->local_info($c);

=head2 C<not_writing>

    $loop->not_writing($c);

=head2 C<read_cb>

    $loop = $loop->read_cb($c => sub { ... });

=head2 C<remote_info>

    my ($address, $port) = $loop->remote_info($c);

=head2 C<start>

    $loop->start;

=head2 C<stop>

    $loop->stop;

=head2 C<write_cb>

    $loop = $loop->write_cb($c => sub { ... });

=head2 C<writing>

    $loop->writing($c);

=cut
