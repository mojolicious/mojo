# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Client;

use strict;
use warnings;

use base 'Mojo::Base';

use IO::Poll qw/POLLERR POLLHUP POLLIN POLLOUT/;
use IO::Socket::INET;
use Mojo::Pipeline;
use Mojo::Server;
use Socket;

__PACKAGE__->attr('continue_timeout',   default => 5);
__PACKAGE__->attr('keep_alive_timeout', default => 15);
__PACKAGE__->attr('poll_timeout',       default => 5);

sub connect {
    my ($self, $tx) = @_;

    my ($scheme, $host, $address, $port) = $tx->client_info;

    # Try to get a cached connection
    my $connection = $self->withdraw_connection("$scheme:$host:$port");
    $tx->kept_alive(1) if $connection;

    # Non blocking connect
    unless ($connection) {
        $connection = $self->open_connection($scheme, $address, $port);
        $tx->{_connect_timeout} = time + 5;
    }
    $tx->connection($connection);

    # State machine
    $tx->client_connect;

    return $tx;
}

sub disconnect {
    my ($self, $tx) = @_;

    my ($scheme, $host, $address, $port) = $tx->client_info;

    # Deposit connection for later or kill socket
    $tx->keep_alive
      ? $self->deposit_connection("$scheme:$host:$port", $tx->connection)
      : $tx->connection(undef);

    return $tx;
}

sub deposit_connection {
    my ($self, $name, $connection, $timeout) = @_;

    # Drop connections after 30 seconds from queue
    $timeout ||= $self->keep_alive_timeout;

    $self->{_connections} ||= [];

    # Store socket if it is in a good state
    if ($self->test_connection($connection)) {
        push @{$self->{_connections}}, [$name, $connection, time + $timeout];
        return 1;
    }
    return 0;
}

sub open_connection {
    my ($self, $scheme, $address, $port) = @_;

    my $connection = IO::Socket::INET->new(
        Proto => 'tcp',
        Type  => SOCK_STREAM
    );

    # Non blocking
    $connection->blocking(0);

    my $sin = sockaddr_in($port, inet_aton($address));
    $connection->connect($sin);

    return $connection;
}

# Marge, I'm going to Moe's. Send the kids to the neighbors,
# I'm coming back loaded!
sub process {
    my ($self, @transactions) = @_;

    # Parallel async io main loop... woot!
    while (1) { last if $self->spin(@transactions) }

    # Finished transactions should be returned first
    my @sorted;
    while (my $tx = shift @transactions) {
        $tx->is_finished ? unshift(@sorted, $tx) : push(@sorted, $tx);
    }

    return @sorted;
}

sub process_all {
    my ($self, @transactions) = @_;

    my @finished;
    my @progress = @transactions;

    # Process until all transactions are finished
    while (1) {
        my @done = $self->process(@progress);
        @progress = ();
        for my $tx (@done) {
            $tx->is_finished ? push(@finished, $tx) : push(@progress, $tx);
        }
        last unless @progress;
    }

    return @finished;
}

sub process_app {
    my ($self, $class, $client) = @_;

    # Remote server
    if (my $authority = $ENV{MOJO_REMOTE_APP}) {
        $client->req->url->authority($authority);
        return $self->process($client);
    }

    # Daemon start
    my $daemon = Mojo::Server->new(app_class => $class);

    # Client connecting
    $client->client_connect;
    $client->client_connected;

    # Server accepting
    my $server =
      Mojo::Pipeline->new->server_accept($daemon->build_tx_cb->($daemon));

    # Exchange
    while ($client->is_writing || $server->is_writing) {

        # Client writing?
        if ($client->is_writing) {

            # Client grabs chunk
            my $buffer = $client->client_get_chunk || '';

            # Client write and server read
            $server->server_read($buffer);

            # Client written
            $client->client_written(length $buffer);
        }

        # Spin both
        $client->client_spin;
        $server->server_spin;

        # Server writing?
        if ($server->is_writing) {

            # Server grabs chunk
            my $buffer = $server->server_get_chunk || '';

            # Server write and client read
            $client->client_read($buffer);

            # Server written
            $server->server_written(length $buffer);
        }

        # Handle
        $self->_handle_app($daemon, $server);

        # Spin both
        $server->server_spin;
        $client->client_spin;

        # Server takes care of leftovers
        if (my $leftovers = $server->server_leftovers) {

            # Server adds transaction
            $server->server_accept($daemon->build_tx_cb->($daemon));

            # Server reads leftovers
            $server->server_read($leftovers);

            # Handle
            $self->_handle_app($daemon, $server);
        }
    }

    return $client;
}

sub spin {
    my ($self, @transactions) = @_;

    # Name to transaction map for fast lookups
    my %transaction;

    # Prepare
    my $done = 0;
    for my $tx (@transactions) {

        # Sanity check
        if ($tx->has_error) {
            $done++;
            next;
        }

        # Connect transaction
        $self->connect($tx) if $tx->is_state('start');

        # Check connect status
        if (!$tx->connection->connected) {
            if (time > $tx->{_connect_timeout}) {
                $tx->error("Couldn't connect to peer before timeout.");
                $done++;
            }
            next;
        }

        # Connected
        elsif ($tx->is_state('connect')) {

            $tx->continue_timeout($self->continue_timeout);

            # Store connection information
            my ($lport, $laddr) = sockaddr_in(getsockname($tx->connection));
            $tx->local_address(inet_ntoa($laddr));
            $tx->local_port($lport);
            my ($rport, $raddr) = sockaddr_in(getpeername($tx->connection));
            $tx->remote_address(inet_ntoa($raddr));
            $tx->remote_port($rport);

            # State machine
            $tx->client_connected;
        }

        # State machine
        $tx->client_spin;

        # Map
        my $name = $self->_socket_name($tx->connection);
        $transaction{$name} = $tx;

        # Done?
        if ($tx->is_done) {
            $done++;

            # Disconnect
            $self->disconnect($tx) if $tx->is_done;
        }
    }
    return 1 if $done;

    # Sort read/write sockets
    my $poll    = IO::Poll->new;
    my $waiting = 0;
    for my $tx (@transactions) {

        # Not yet connected
        next if $tx->is_state('connect');

        my $connection = $tx->connection;

        # We always try to read as suggested by RFC 2616 for HTTP 1.1 clients
        $tx->is_writing
          ? $poll->mask($connection, POLLIN | POLLOUT)
          : $poll->mask($connection, POLLIN);

        $waiting++;
    }

    # No sockets ready yet
    return 0 unless $waiting;

    # Poll
    $poll->poll($self->poll_timeout);
    my @readers = $poll->handles(POLLIN | POLLHUP | POLLERR);
    my @writers = $poll->handles(POLLOUT);

    # Make a random decision about reading or writing
    my $do = -1;
    $do = 0 if @readers;
    $do = 1 if @writers;
    $do = int(rand(3)) - 1 if @readers && @writers;

    # Write
    if ($do == 1) {

        my ($tx, $chunk);

        # Check for content randomly
        for my $connection (sort { int(rand(3)) - 1 } @writers) {

            my $name = $self->_socket_name($connection);
            $tx = $transaction{$name};

            $chunk = $tx->client_get_chunk;

            # Content generator ready?
            last if defined $chunk;
        }

        # Nothing to write
        return $done unless $chunk;

        # Write chunk
        my $written = $tx->connection->syswrite($chunk, length $chunk);
        $tx->error("Can't write to socket: $!") unless defined $written;
        return 1 if $tx->has_error;

        $tx->client_written($written);
    }

    # Read
    elsif ($do == 0) {

        my $connection = $readers[rand(@readers)];
        my $name       = $self->_socket_name($connection);
        my $tx         = $transaction{$name};

        my $buffer;
        my $read = $connection->sysread($buffer, 1024, 0);
        $tx->error("Can't read from socket: $!") unless defined $read;
        return 1 if $tx->has_error;

        $tx->client_read($buffer);
    }

    return $done;
}

sub test_connection {
    my ($self, $connection) = @_;

    # There are garbage bytes on the socket, or the peer closed the
    # connection if it is readable
    my $poll = IO::Poll->new;
    $poll->mask($connection, POLLIN);
    $poll->poll(0);
    my @readers = $poll->handles(POLLIN);
    return @readers ? 0 : 1;
}

sub withdraw_connection {
    my ($self, $match) = @_;

    # Shortcut
    return 0 unless $self->{_connections};

    my $result;
    my @connections;

    # Check all connections for name, timeout and if they are still alive
    for my $conn (@{$self->{_connections}}) {
        my ($name, $connection, $timeout) = @{$conn};
        if ($match eq $name) {
            $result = $connection
              if (time < $timeout) && $self->test_connection($connection);
        }
        else { push(@connections, $conn) if time < $timeout }
    }

    $self->{_connections} = \@connections;
    return $result;
}

sub _handle_app {
    my ($self, $daemon, $server) = @_;

    # Handle continue
    if ($server->is_state('handle_continue')) {

        # Continue handler
        $daemon->continue_handler_cb->($daemon, $server->server_tx);

        # Handled
        $server->server_handled;
    }

    # Handle request
    if ($server->is_state('handle_request')) {

        # Handler
        $daemon->handler_cb->($daemon, $server->server_tx);

        # Handled
        $server->server_handled;
    }
}

sub _socket_name {
    my ($self, $s) = @_;
    return
        unpack('H*', $s->sockaddr)
      . $s->sockport
      . unpack('H*', $s->peeraddr)
      . $s->peerport;
}

1;
__END__

=head1 NAME

Mojo::Client - Client

=head1 SYNOPSIS

    use Mojo::Client;
    use Mojo::Transaction;

    my $tx = Mojo::Transaction->new;
    $tx->req->method('GET');
    $tx->req->url->parse('http://cpan.org');

    my $client = Mojo::Client->new;
    $client->process($tx);

=head1 DESCRIPTION

L<Mojo::Client> is a full featured async io HTTP 1.1 client.

=head1 ATTRIBUTES

L<Mojo::Client> implements the following attributes.

=head2 C<continue_timeout>

    my $timeout = $client->continue_timeout;
    $client     = $client->continue_timeout(5);

=head2 C<keep_alive_timeout>

    my $keep_alive_timeout = $client->keep_alive_timeout;
    $client                = $client->keep_alive_timeout(15);

=head2 C<poll_timeout>

    my $timeout = $client->poll_timeout;
    $client     = $client->poll_timeout(5);

=head1 METHODS

L<Mojo::Client> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<connect>

    $tx = $client->connect($tx);

=head2 C<disconnect>

    $tx = $client->disconnect($tx);

=head2 C<deposit_connection>

    $client->deposit_connection($name, $connection, $timeout);

=head2 C<open_connection>

    my $connection = $client->open_connection($scheme, $address, $port);

=head2 C<process>

    @transactions = $client->process(@transactions);

=head2 C<process_all>

    @transactions = $client->process_all(@transactions);

=head2 C<process_app>

    $tx = $client->process_app('MyApp', $tx);

=head2 C<spin>

    my $done = $client->spin(@transactions);

=head2 C<test_connection>

    my $alive = $client->test_connection($connection);

=head2 C<withdraw_connection>

    my $connection = $client->withdraw_connection($name);

=cut
