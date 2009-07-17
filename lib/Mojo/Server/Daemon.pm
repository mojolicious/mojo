# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Server::Daemon;

use strict;
use warnings;

use base 'Mojo::Server';

use Carp 'croak';
use IO::Poll qw/POLLERR POLLHUP POLLIN POLLOUT/;
use IO::Socket;
use Mojo::Pipeline;

__PACKAGE__->attr([qw/group user/]);
__PACKAGE__->attr('keep_alive_timeout',      default => 15);
__PACKAGE__->attr('listen_queue_size',       default => SOMAXCONN);
__PACKAGE__->attr('max_clients',             default => 1000);
__PACKAGE__->attr('max_keep_alive_requests', default => 100);
__PACKAGE__->attr('port',                    default => 3000);

sub accept_lock {1}

sub accept_unlock {1}

sub listen {
    my $self = shift;

    # Create socket
    my $port = $self->port;
    $self->{listen} ||= IO::Socket::INET->new(
        Listen    => $self->listen_queue_size,
        LocalPort => $port,
        Proto     => 'tcp',
        ReuseAddr => 1,
        Type      => SOCK_STREAM
    ) or croak "Can't create listen socket: $!";

    # Non blocking
    $self->{listen}->blocking(0);

    # Log
    $self->app->log->info("Server started (http://127.0.0.1:$port)");

    # Friendly message
    print "Server available at http://127.0.0.1:$port.\n";
}

# 40 dollars!? This better be the best damn beer ever..
# *drinks beer* You got lucky.
sub run {
    my $self = shift;

    # Signals
    $SIG{HUP} = $SIG{PIPE} = 'IGNORE';

    # Listen
    $self->listen;

    # User and group
    $self->setuidgid;

    # Spin
    $self->spin while 1;
}

sub setuidgid {
    my $self = shift;

    # Group
    if (my $group = $self->group) {
        if (my $gid = (getgrnam($group))[2]) {

            # Cleanup
            undef $!;

            # Switch
            $) = $gid;
            croak qq/Can't switch to effective group "$group": $!/ if $!;
        }
    }

    # User
    if (my $user = $self->user) {
        if (my $uid = (getpwnam($user))[2]) {

            # Cleanup
            undef $!;

            # Switch
            $> = $uid;
            croak qq/Can't switch to effective user "$user": $!/ if $!;
        }
    }

    return $self;
}

sub spin {
    my $self = shift;

    # Default poll instance
    $self->{_poll} ||= IO::Poll->new;

    # Prepare
    $self->_prepare_connections;
    $self->_prepare_transactions;
    $self->_prepare_poll;

    # Poll
    my $poll = $self->{_poll};
    $poll->poll(5);
    my @readers = $poll->handles(POLLIN | POLLHUP | POLLERR);
    my @writers = $poll->handles(POLLOUT);

    # Make a random decision about reading or writing
    my $do = -1;
    $do = 0 if @readers;
    $do = 1 if @writers;
    $do = int(rand(3)) - 1 if @readers && @writers;

    # Read
    if ($do == 0) { $self->_read(\@readers) }

    # Write
    elsif ($do == 1) { $self->_write(\@writers) }

}

sub _drop_connection {
    my ($self, $name) = @_;

    # Cleanup
    $self->{_poll}->remove($self->{_connections}->{$name}->{socket});
    close $self->{_connections}->{$name}->{socket};

    # Remove
    delete $self->{_reverse}->{$self->{_connections}->{$name}};
    delete $self->{_connections}->{$name};
}

sub _handle {
    my ($self, $p) = @_;

    # Handle continue
    if ($p->is_state('handle_continue')) {

        # Continue handler
        $self->continue_handler_cb->($self, $p->server_tx);

        # Handled
        $p->server_handled;
    }

    # Handle request
    if ($p->is_state('handle_request')) {

        # Handler
        $self->handler_cb->($self, $p->server_tx);

        # Handled
        $p->server_handled;
    }
}

sub _prepare_connections {
    my $self = shift;

    # Initialize
    $self->{_accepted}    ||= [];
    $self->{_connections} ||= {};

    # Accept
    my @accepted = ();
    for my $accept (@{$self->{_accepted}}) {

        # Not yet connected
        unless ($accept->{socket}->connected) {
            push @accepted, $accept;
            next;
        }

        # Connected
        $accept->{socket}->blocking(0);
        next unless my $name = $self->_socket_name($accept->{socket});
        $self->{_reverse}->{$accept->{socket}} = $name;
        $self->{_connections}->{$name} = $accept;
    }

    # Accepted
    $self->{_accepted} = [@accepted];
}

sub _prepare_poll {
    my $self = shift;

    my $poll    = $self->{_poll};
    my $clients = keys %{$self->{_connections}};

    # Add listen socket if we get the lock on it
    if (($clients < $self->max_clients) && $self->accept_lock(!$clients)) {
        $poll->mask($self->{listen}, POLLIN);
    }

    # Remove listen otherwise
    else { $poll->remove($self->{listen}) }

    # Sort read/write handles and timeouts
    for my $name (keys %{$self->{_connections}}) {
        my $connection = $self->{_connections}->{$name};

        # Transaction
        my $p = $connection->{pipeline};

        # Keep alive timeout
        my $timeout = time - $connection->{time};
        if ($self->keep_alive_timeout < $timeout) {
            $self->_drop_connection($name);
            next;
        }

        # No transaction in progress
        unless ($p) {

            # Keep alive request limit
            if ($connection->{requests} >= $self->max_keep_alive_requests) {
                $self->_drop_connection($name);

            }

            # Keep alive
            else { $poll->mask($connection->{socket}, POLLIN) }
            next;
        }

        # We always try to read as sugegsted by the HTTP spec
        $p->is_writing
          ? $poll->mask($p->connection, POLLIN | POLLOUT)
          : $poll->mask($p->connection, POLLIN);
    }
}

sub _prepare_transactions {
    my $self = shift;

    # Prepare transactions
    for my $name (keys %{$self->{_connections}}) {
        my $connection = $self->{_connections}->{$name};

        # Cleanup dead connection
        unless ($connection->{socket}->connected) {
            $self->_drop_connection($name);
            next;
        }

        # Transaction
        my $p = $connection->{pipeline};

        # Just a keep alive, no transaction
        next unless $p;

        # Handle
        $self->_handle($p);

        # State machine
        $p->server_spin;

        # Add transactions to the pipe for leftovers
        if (my $leftovers = $p->server_leftovers) {

            # New transaction
            my $tx = $self->build_tx_cb->($self);

            # Add to pipeline
            $p->server_accept($tx);

            # Read leftovers
            $p->server_read($leftovers);

            # Handle
            $self->_handle($p);
        }

        # Pipeline finished?
        elsif ($p->is_finished) {

            # Drop
            delete $connection->{pipeline};
            $self->_drop_connection($name) unless $p->keep_alive;
        }
    }
}

sub _read {
    my ($self, $sockets) = @_;

    my $socket = $sockets->[0];

    # Accept
    unless ($socket->connected) {
        $socket = $socket->accept;
        $self->accept_unlock;
        return 0 unless $socket;
        push @{$self->{_accepted}},
          {requests => 0, socket => $socket, time => time};
        return 1;
    }

    return 0 unless my $name = $self->_socket_name($socket);

    # No pipeline yet
    my $connection = $self->{_connections}->{$name};
    unless ($connection->{pipeline}) {

        # New pipeline
        my $p = $connection->{pipeline}
          ||= Mojo::Pipeline->new->server_accept($self->build_tx_cb->($self));
        $p->connection($socket);
        $connection->{requests}++;
        $p->kept_alive(1) if $connection->{requests} > 1;

        # Last keep alive request?
        $p->server_tx->res->headers->connection('Close')
          if $connection->{requests} >= $self->max_keep_alive_requests;

        # Store connection information
        my ($lport, $laddr) = sockaddr_in(getsockname($p->connection));
        $p->local_address(inet_ntoa($laddr));
        $p->local_port($lport);
        my ($rport, $raddr) = sockaddr_in(getpeername($p->connection));
        $p->remote_address(inet_ntoa($raddr));
        $p->remote_port($rport);
    }

    my $p = $connection->{pipeline};

    # Read request
    my $read = $socket->sysread(my $buffer, 4096, 0);

    # Read error
    unless (defined $read && $buffer) {
        $self->_drop_connection($name);
        return 1;
    }

    # Need a new transaction?
    unless ($p->server_tx) {

        # New transaction
        my $new_tx = $self->build_tx_cb->($self);

        # Add to pipeline
        $p->server_accept($new_tx);
    }

    # Read
    $p->server_read($buffer);

    # Time
    $connection->{time} = time;
}

sub _socket_name {
    my ($self, $s) = @_;

    # Cache
    return $self->{_reverse}->{$s} if $self->{_reverse}->{$s};

    # Connected?
    return unless $s->connected;

    # Generate
    return
        unpack('H*', $s->sockaddr)
      . $s->sockport
      . unpack('H*', $s->peeraddr)
      . $s->peerport;
}

sub _write {
    my ($self, $sockets) = @_;

    my ($name, $p, $chunk);

    # Check for content
    for my $socket (sort { int(rand(3)) - 1 } @$sockets) {

        # Shortcut
        next unless $name = $self->_socket_name($socket);

        my $connection = $self->{_connections}->{$name};
        $p = $connection->{pipeline};

        # Get chunk
        $chunk = $p->server_get_chunk;

        # Content generator ready?
        last if defined $chunk;
    }

    # No name
    return 0 unless $name;

    # Nothing to write
    return 0 unless $chunk;

    # Connected?
    return 0 unless $p->connection->connected;

    # Write
    my $written = $p->connection->syswrite($chunk, length $chunk);
    $p->error("Can't write request: $!") unless defined $written;
    return 1 if $p->has_error;

    # Written
    $p->server_written($written);

    # Time
    $self->{_connections}->{$name}->{time} = time;
}

1;
__END__

=head1 NAME

Mojo::Server::Daemon - HTTP Server

=head1 SYNOPSIS

    use Mojo::Server::Daemon;

    my $daemon = Mojo::Server::Daemon->new;
    $daemon->port(8080);
    $daemon->run;

=head1 DESCRIPTION

L<Mojo::Server::Daemon> is a simple and portable async io based HTTP server.

=head1 ATTRIBUTES

L<Mojo::Server::Daemon> inherits all attributes from L<Mojo::Server> and
implements the following new ones.

=head2 C<group>

    my $group = $daemon->group;
    $daemon   = $daemon->group('users');

=head2 C<keep_alive_timeout>

    my $keep_alive_timeout = $daemon->keep_alive_timeout;
    $daemon                = $daemon->keep_alive_timeout(15);

=head2 C<listen_queue_size>

    my $listen_queue_size = $daemon->listen_queue_zise;
    $daemon               = $daemon->listen_queue_zise(128);

=head2 C<max_clients>

    my $max_clients = $daemon->max_clients;
    $daemon         = $daemon->max_clients(1000);

=head2 C<max_keep_alive_requests>

    my $max_keep_alive_requests = $daemon->max_keep_alive_requests;
    $daemon                     = $daemon->max_keep_alive_requests(100);

=head2 C<port>

    my $port = $daemon->port;
    $daemon  = $daemon->port(3000);

=head2 C<user>

    my $user = $daemon->user;
    $daemon  = $daemon->user('web');

=head1 METHODS

L<Mojo::Server::Daemon> inherits all methods from L<Mojo::Server> and
implements the following new ones.

=head2 C<accept_lock>

    my $locked = $daemon->accept_lock;
    my $locked = $daemon->accept_lock(1);

=head2 C<accept_unlock>

    $daemon->accept_unlock;

=head2 C<listen>

    $daemon->listen;

=head2 C<run>

    $daemon->run;

=head2 C<setuidgid>

    $daemon->setuidgid;

=head2 C<spin>

    $daemon->spin;

=cut
