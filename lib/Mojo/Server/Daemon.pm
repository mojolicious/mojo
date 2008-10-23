# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Server::Daemon;

use strict;
use warnings;

use base 'Mojo::Server';

use Carp 'croak';
use IO::Select;
use IO::Socket;

__PACKAGE__->attr('keep_alive_timeout',
    chained => 1,
    default => sub { 15 }
);
__PACKAGE__->attr('listen_queue_size',
    chained => 1,
    default => sub { SOMAXCONN }
);
__PACKAGE__->attr('max_clients', chained => 1, default => sub { 1000 });
__PACKAGE__->attr('max_keep_alive_requests',
    chained => 1,
    default => sub { 100 }
);
__PACKAGE__->attr('port', chained => 1, default => 3000);

sub accept_lock { return 1 }

sub accept_unlock { return 1 }

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

    # Friendly message
    print "Server available at http://127.0.0.1:$port.\n";
}

# 40 dollars!? This better be the best damn beer ever..
# *drinks beer* You got lucky.
sub run {
    my $self = shift;

    $SIG{HUP} = $SIG{PIPE} = 'IGNORE';

    # Listen
    $self->listen;

    # Spin
    $self->spin while 1;
}

sub spin {
    my $self = shift;

    $self->_prepare_connections;
    $self->_prepare_transactions;
    my ($reader, $writer) = $self->_prepare_select;

    # Select
    my ($read, $write, undef)
      = IO::Select->select($reader, $writer, undef, 5);
    $read  ||= [];
    $write ||= [];

    # Write
    if (@$write) { $self->_write($write) }

    # Read
    elsif (@$read) { $self->_read($read) }
}

sub _prepare_connections {
    my $self = shift;

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
        $self->{_connections}->{$name} = $accept;
    }
    $self->{_accepted} = [@accepted];
}

sub _prepare_select {
    my $self = shift;

    my @read = ();
    my $clients = keys %{$self->{_connections}};

    # Select listen socket if we get the lock on it
    if (($clients < $self->max_clients) && $self->accept_lock(!$clients)) {
        @read  = ($self->{listen});
    }

    my @write = ();

    # Sort read/write handles and timeouts
    for my $name (keys %{$self->{_connections}}) {
        my $connection = $self->{_connections}->{$name};

        # Transaction
        my $tx = $connection->{tx};

        # Keep alive timeout
        my $timeout = time - $connection->{time};
        if ($self->keep_alive_timeout < $timeout) {
            delete $self->{_connections}->{$name};
            next;
        }

        # No transaction in progress
        unless ($tx) {

            # Keep alive request limit
            if ($connection->{requests} >= $self->max_keep_alive_requests) {
                delete $self->{_connections}->{$name};
            }

            # Keep alive
            else { unshift @read, $connection->{socket} }
            next;
        }

        # Read
        if ($tx->is_state('read')) { unshift @read, $tx->connection }

        # Write
        if ($tx->is_state(qw/write_start_line write_headers write_body/)) {
            unshift @write, $tx->connection;
        }
    }

    # Prepare select
    my $reader = IO::Select->new(@read);
    my $writer = @write ? IO::Select->new(@write) : undef;

    return $reader, $writer;
}

sub _prepare_transactions {
    my $self = shift;

    # Prepare transactions
    for my $name (keys %{$self->{_connections}}) {
        my $connection = $self->{_connections}->{$name};

        # Cleanup dead connection
        unless ($connection->{socket}->connected) {
            delete $self->{_connections}->{$name};
            next;
        }

        # Transaction
        my $tx = $connection->{tx};

        # Just a keep alive, no transaction
        next unless $tx;

        # Writing
        if ($tx->is_state('write')) {

            # Ready for next state
            $tx->state('write_start_line');
            $tx->{_to_write} = $tx->res->start_line_length;
        }

        # Response start line
        if ($tx->is_state('write_start_line') && $tx->{_to_write} <= 0) {
            $tx->state('write_headers');
            $tx->{_offset} = 0;
            $tx->{_to_write} = $tx->res->header_length;
        }

        # Response headers
        if ($tx->is_state('write_headers') && $tx->{_to_write} <= 0) {
            $tx->state('write_body');
            $tx->{_offset} = 0;
            $tx->{_to_write} = $tx->res->body_length;
        }

        # Response body
        if ($tx->is_state('write_body') && $tx->{_to_write} <= 0) {

            # Continue done
            if (defined $tx->continued && $tx->continued == 0) {
                $tx->continued(1);
                $tx->state('read');
                $tx->state('done') unless $tx->res->code == 100;
                $tx->res->code(0);
                next;
            }

            # Done
            delete $connection->{tx};
            delete $self->{_connections}->{$name} unless $tx->keep_alive;
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
        push @{$self->{_accepted}}, {
            requests  => 0,
            socket    => $socket,
            time      => time
        };
        return 1;
    }

    return 0 unless my $name = $self->_socket_name($socket);

    my $connection = $self->{_connections}->{$name};
    unless ($connection->{tx}) {
        my $tx = $connection->{tx} ||= $self->build_tx_cb->($self);
        $tx->connection($socket);
        $tx->state('read');
        $connection->{requests}++;

        # Last keep alive request?
        $tx->res->headers->connection('close')
          if $connection->{requests} >= $self->max_keep_alive_requests;
    }

    my $tx  = $connection->{tx};
    my $req = $tx->req;

    # Read request
    my $read = $socket->sysread(my $buffer, 4096, 0);

    # Read error
    unless (defined $read) {
        delete $self->{_connections}->{$name};
        return 1;
    }

    # Parse
    $req->parse($buffer);

    # Expect 100 Continue?
    if ($req->content->is_state('body') && !defined $tx->continued) {
        if (($req->headers->expect || '') =~ /100-continue/i) {
            $tx->state('write');
            $tx->continued(0);
            $self->continue_handler_cb->($self, $tx);
        }
    }

    # EOF
    if(($read == 0) || $req->is_state(qw/done error/)) {
        $tx->state('write');

        # Handle
        $self->handler_cb->($self, $tx);
    }

    $connection->{time} = time;
}

sub _socket_name {
    my ($self, $s) = @_;
    return undef unless $s->connected;
    my $n = join ':', $s->sockaddr, $s->sockport, $s->peeraddr, $s->peerport;
    $n =~ s/[^\w]/x/gi;
    return $n;
}

sub _write {
    my ($self, $sockets) = @_;

    my ($name, $tx, $res, $chunk);

    # Check for content
    for my $socket (@$sockets) {
        next unless $name = $self->_socket_name($socket);
        my $connection = $self->{_connections}->{$name};
        $tx  = $connection->{tx};
        $res = $tx->res;

        # Body
        $chunk = $res->get_body_chunk($tx->{_offset} || 0)
          if $tx->is_state('write_body');

        # Headers
        $chunk = $res->get_header_chunk($tx->{_offset} || 0)
          if $tx->is_state('write_headers');

        # Start line
        $chunk = $res->get_start_line_chunk($tx->{_offset} || 0)
          if $tx->is_state('write_start_line');

        # Content generator ready?
        last if defined $chunk;
    }
    return 0 unless $name;

    # Write chunk
    return 0 unless $tx->connection->connected;
    my $written = $tx->connection->syswrite($chunk, length $chunk);
    $tx->error("Can't write request: $!") unless defined $written;
    return 1 if $tx->has_error;

    $tx->{_to_write} -= $written;
    $tx->{_offset}   += $written;

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

=head2 C<spin>

    $daemon->spin;

=cut