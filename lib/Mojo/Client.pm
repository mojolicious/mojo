# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Client;

use strict;
use warnings;

use base 'Mojo::Base';
use bytes;

use Mojo::IOLoop;
use Mojo::Server;
use Mojo::Transaction::Pipeline;
use Mojo::Transaction::Single;
use Scalar::Util qw/isweak weaken/;
use Socket;

__PACKAGE__->attr([qw/app default_cb/]);
__PACKAGE__->attr([qw/continue_timeout max_keep_alive_connections/] => 5);
__PACKAGE__->attr(ioloop => sub { Mojo::IOLoop->new });
__PACKAGE__->attr(keep_alive_timeout => 15);

__PACKAGE__->attr([qw/_app_queue _cache/] => sub { [] });
__PACKAGE__->attr(_connections            => sub { {} });
__PACKAGE__->attr([qw/_finite _queued/]   => 0);

sub delete { shift->_build_tx('DELETE', @_) }
sub get    { shift->_build_tx('GET',    @_) }
sub head   { shift->_build_tx('HEAD',   @_) }
sub post   { shift->_build_tx('POST',   @_) }

sub process {
    my $self = shift;

    # Weaken
    weaken $self;

    # Connect callback
    $self->ioloop->connect_cb(
        sub {
            my ($loop, $id) = @_;

            # Connected
            $self->_connect($id);
        }
    );

    # Queue transactions
    $self->queue(@_) if @_;

    # Process app
    return $self->_app_process if $self->app;

    # Loop is finite
    $self->_finite(1);

    # Start IOLoop
    $self->ioloop->start;

    # Cleanup
    $self->_finite(undef);

    return $self;
}

sub put { shift->_build_tx('PUT', @_) }

sub queue {
    my $self = shift;

    # Callback
    my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

    # Queue transactions
    $self->_queue($_, $cb) for @_;

    return $self;
}

sub _app_process {
    my $self = shift;

    # Process queued transactions
    while (my $queued = shift @{$self->_app_queue}) {

        # Transaction
        my $client = $queued->[0];

        # App
        my $app = $self->app;

        # Daemon start
        my $daemon = Mojo::Server->new;
        $daemon->app($app) if ref $app;
        $daemon->app_class(ref $app || $app);

        # Client connecting
        $client->client_connected;

        # Server accepting
        my $server = Mojo::Transaction::Pipeline->new;

        # Transaction builder callback
        $server->build_tx_cb(
            sub {

                # Build transaction
                my $tx = $daemon->build_tx_cb->($daemon);

                # Handler callback
                $tx->handler_cb(
                    sub {

                        # Weaken
                        weaken $tx unless isweak $tx;

                        # Handler
                        $daemon->handler_cb->($daemon, $tx);
                    }
                );

                # Continue handler callback
                $tx->continue_handler_cb(
                    sub {

                        # Weaken
                        weaken $tx;

                        # Handler
                        $daemon->continue_handler_cb->($daemon, $tx);
                    }
                );

                return $tx;
            }
        );

        # Spin
        while (1) { last if $self->_app_spin($client, $server, $daemon) }

        # Callback
        my $cb = $queued->[1] || $self->default_cb;

        # Execute callback
        $self->$cb($client) if $cb;
    }

    return $self;
}

sub _app_spin {
    my ($self, $client, $server, $daemon) = @_;

    # Exchange
    if ($client->client_is_writing || $server->server_is_writing) {

        # Client writing?
        if ($client->client_is_writing) {

            # Client grabs chunk
            my $buffer = $client->client_get_chunk;
            $buffer = '' unless defined $buffer;

            # Client write and server read
            $server->server_read($buffer);
        }

        # Spin both
        $client->client_spin;
        $server->server_spin;

        # Server writing?
        if ($server->server_is_writing) {

            # Server grabs chunk
            my $buffer = $server->server_get_chunk;
            $buffer = '' unless defined $buffer;

            # Server write and client read
            $client->client_read($buffer);
        }

        # Spin both
        $server->server_spin;
        $client->client_spin;

        # Server takes care of leftovers
        if (my $leftovers = $server->server_leftovers) {

            # Server reads leftovers
            $server->server_read($leftovers);
        }
    }

    # Done
    return 1 if $client->is_finished;

    # Check if server closed the connection
    $client->error('Server closed connection.') and return 1
      if $server->is_done && !$server->keep_alive;

    # More to do
    return;
}

sub _build_tx {
    my $self = shift;

    # New transaction
    my $tx = Mojo::Transaction::Single->new;

    # Request
    my $req = $tx->req;

    # Method
    $req->method(shift);

    # URL
    $req->url->parse(shift);

    # Callback
    my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

    # Headers
    my $headers = ref $_[0] eq 'HASH' ? $_[0] : {@_};
    for my $name (keys %$headers) {
        $req->headers->header($name, $headers->{$name});
    }

    # Queue transaction with callback
    $self->queue($tx, $cb);
}

sub _connect {
    my ($self, $id) = @_;

    # Transaction
    my $tx = $self->_connections->{$id}->{tx};

    # Connected
    $tx->client_connected;

    # Store connection information in transaction
    my $local = $self->ioloop->local_info($id);
    $tx->local_address($local->{address});
    $tx->local_port($local->{port});
    my $remote = $self->ioloop->remote_info($id);
    $tx->remote_address($remote->{address});
    $tx->remote_port($remote->{port});

    # Keep alive timeout
    $self->ioloop->connection_timeout($id => $self->keep_alive_timeout);

    # Weaken
    weaken $self;

    # Callbacks
    $self->ioloop->error_cb($id => sub { $self->_error(@_) });
    $self->ioloop->hup_cb($id => sub { $self->_hup(@_) });
    $self->ioloop->read_cb($id => sub { $self->_read(@_) });
    $self->ioloop->write_cb($id => sub { $self->_write(@_) });
}

sub _deposit {
    my ($self, $name, $id) = @_;

    # Limit keep alive connections
    while (@{$self->_cache} >= $self->max_keep_alive_connections) {
        my $cached = shift @{$self->_cache};
        $self->_drop($cached->[1]);
    }

    # Deposit
    push @{$self->_cache}, [$name, $id];
}

sub _drop {
    my ($self, $id) = @_;

    # Keep connection alive
    if (my $tx = $self->_connections->{$id}->{tx}) {

        # Read only
        $self->ioloop->not_writing($id);

        # Deposit
        my $info   = $tx->client_info;
        my $host   = $info->{host};
        my $port   = $info->{port};
        my $scheme = $info->{scheme};
        $self->_deposit("$scheme:$host:$port", $id) if $tx->keep_alive;
    }

    # Connection close
    else {
        $self->ioloop->finish($id);
        $self->_withdraw($id);
    }

    # Drop connection
    delete $self->_connections->{$id};
}

sub _error {
    my ($self, $loop, $id, $error) = @_;

    # Transaction
    if (my $tx = $self->_connections->{$id}->{tx}) {

        # Add error message
        $tx->error($error);
    }

    # Finish
    $self->_finish($id);
}

sub _finish {
    my ($self, $id) = @_;

    # Transaction
    my $tx = $self->_connections->{$id}->{tx};

    # Get callback
    my $cb = $self->_connections->{$id}->{cb} || $self->default_cb;

    # Transaction still in progress
    if ($tx) {

        # Callback
        $self->$cb($tx) if $cb && $tx;

        # Counter
        $self->_queued($self->_queued - 1) if $tx;
    }

    # Drop
    $self->_drop($id);

    # Stop IOLoop
    $self->ioloop->stop if $self->_finite && !$self->_queued;
}

sub _hup {
    my ($self, $loop, $id) = @_;

    # Transaction
    if (my $tx = $self->_connections->{$id}->{tx}) {

        # Add error message
        $tx->error('Connection closed.');
    }

    # Finish
    $self->_finish($id);
}

sub _queue {
    my ($self, $tx, $cb) = @_;

    # Add to app queue
    push @{$self->_app_queue}, [$tx, $cb] and return if $self->app;

    # Info
    my $info   = $tx->client_info;
    my $host   = $info->{host};
    my $port   = $info->{port};
    my $scheme = $info->{scheme};

    # Cached connection
    my $id;
    if ($id = $self->_withdraw("$scheme:$host:$port")) {

        # Writing
        $self->ioloop->writing($id);

        # Kept alive
        $tx->kept_alive(1);

        # Add new connection
        $self->_connections->{$id} = {cb => $cb, tx => $tx};

        # Connected
        $self->_connect($id);
    }

    # New connection
    else {

        # Address
        my $address =
            $host =~ /\b(?:\d{1,3}\.){3}\d{1,3}\b/
          ? $host
          : inet_ntoa(inet_aton($host));

        # Connect
        $id = $self->ioloop->connect(address => $address, port => $port);

        # Error
        unless (defined $id) {
            $tx->error("Couldn't create connection.");
            $cb ||= $self->default_cb;
            $self->$cb($tx) if $cb;
            return;
        }

        # Add new connection
        $self->_connections->{$id} = {cb => $cb, tx => $tx};
    }

    # Weaken
    weaken $self;
    weaken $tx;

    # State change callback
    $tx->state_cb(
        sub {

            # Finished?
            return $self->_finish($id) if $tx->is_finished;

            # Writing?
            $tx->client_is_writing
              ? $self->ioloop->writing($id)
              : $self->ioloop->not_writing($id);
        }
    );

    # Counter
    $self->_queued($self->_queued + 1);
}

sub _read {
    my ($self, $loop, $id, $chunk) = @_;

    # Transaction
    if (my $tx = $self->_connections->{$id}->{tx}) {

        # Read
        $tx->client_read($chunk);

        # State machine
        $tx->client_spin;
    }

    # Corrupted connection
    else { $self->_drop($id) }
}

sub _withdraw {
    my ($self, $name) = @_;

    # Withdraw
    my $found;
    my @cache;
    for my $cached (@{$self->_cache}) {

        # Search for name or id
        $found = $cached->[1] and next
          if $cached->[1] eq $name || $cached->[0] eq $name;

        # Cache again
        push @cache, $cached;
    }
    $self->_cache(\@cache);

    return $found;
}

sub _write {
    my ($self, $loop, $id) = @_;

    # Transaction
    my $tx = $self->_connections->{$id}->{tx};

    # Get chunk
    my $chunk = $tx->client_get_chunk;

    # State machine
    $tx->client_spin;

    return $chunk;
}

1;
__END__

=head1 NAME

Mojo::Client - Client

=head1 SYNOPSIS

    use Mojo::Client;

    my $client = Mojo::Client->new;
    $client->get(
        'http://kraih.com' => sub {
            my ($self, $tx) = @_;
            print $tx->res->code;
        }
    )->process;

=head1 DESCRIPTION

L<Mojo::Client> is a full featured async io HTTP 1.1 client.

=head1 ATTRIBUTES

L<Mojo::Client> implements the following attributes.

=head2 C<app>

    my $app = $client->app;
    $client = $client->app(Mojolicious::Lite->new);

=head2 C<continue_timeout>

    my $timeout = $client->continue_timeout;
    $client     = $client->continue_timeout(5);

=head2 C<default_cb>

    my $cb  = $client->default_cb;
    $client = $client->default_cb(sub {...});

=head2 C<ioloop>

    my $loop = $client->ioloop;
    $client  = $client->ioloop(Mojo::IOLoop->new);

=head2 C<keep_alive_timeout>

    my $keep_alive_timeout = $client->keep_alive_timeout;
    $client                = $client->keep_alive_timeout(15);

=head2 C<max_keep_alive_connections>

    my $max_keep_alive_connections = $client->max_keep_alive_connections;
    $client                        = $client->max_keep_alive_connections(5);

=head1 METHODS

L<Mojo::Client> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $client = Mojo::Client->new;

=head2 C<delete>

    $client = $client->delete('http://kraih.com' => sub {...});
    $client = $client->delete(
      'http://kraih.com' => (Connection => 'close') => sub {...}
    );

=head2 C<get>

    $client = $client->get('http://kraih.com' => sub {...});
    $client = $client->get(
      'http://kraih.com' => (Connection => 'close') => sub {...}
    );

=head2 C<head>

    $client = $client->head('http://kraih.com' => sub {...});
    $client = $client->head(
      'http://kraih.com' => (Connection => 'close') => sub {...}
    );

=head2 C<post>

    $client = $client->post('http://kraih.com' => sub {...});
    $client = $client->post(
      'http://kraih.com' => (Connection => 'close') => sub {...}
    );

=head2 C<process>

    $client = $client->process;
    $client = $client->process(@transactions);
    $client = $client->process(@transactions => sub {...});

=head2 C<put>

    $client = $client->put('http://kraih.com' => sub {...});
    $client = $client->put(
      'http://kraih.com' => (Connection => 'close') => sub {...}
    );

=head2 C<queue>

    $client = $client->queue(@transactions);
    $client = $client->queue(@transactions => sub {...});

=cut
