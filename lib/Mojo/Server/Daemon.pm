# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Server::Daemon;

use strict;
use warnings;

use base 'Mojo::Server';
use bytes;

use Carp 'croak';
use Mojo::IOLoop;
use Mojo::Transaction::Pipeline;
use Scalar::Util qw/isweak weaken/;

__PACKAGE__->attr([qw/address group listen_queue_size user/]);
__PACKAGE__->attr(ioloop => sub { Mojo::IOLoop->new });
__PACKAGE__->attr(keep_alive_timeout      => 15);
__PACKAGE__->attr(max_clients             => 1000);
__PACKAGE__->attr(max_keep_alive_requests => 100);
__PACKAGE__->attr(port                    => 3000);

__PACKAGE__->attr(_connections => sub { {} });

sub prepare_ioloop {
    my $self = shift;

    my $options = {};

    # Address
    my $address = $self->address;
    $options->{address} = $address if $address;
    $address ||= '127.0.0.1';

    # Port
    my $port = $options->{port} = $self->port;

    # Listen queue size
    my $queue = $self->listen_queue_size;
    $options->{queue_size} = $queue if $queue;

    # Listen
    $self->ioloop->listen($options);

    # Log
    $self->app->log->info("Server started (http://$address:$port)");

    # Friendly message
    print "Server available at http://$address:$port.\n";

    # Max clients
    $self->ioloop->max_clients($self->max_clients);

    # Weaken
    weaken $self;

    # Accept callback
    $self->ioloop->accept_cb(
        sub {
            my ($loop, $id) = @_;

            # Add new connection
            $self->_connections->{$id} = {};

            # Keep alive timeout
            $loop->connection_timeout($id => $self->keep_alive_timeout);

            # Callbacks
            $loop->error_cb($id => sub { $self->_error(@_) });
            $loop->hup_cb($id => sub { $self->_hup(@_) });
            $loop->read_cb($id => sub { $self->_read(@_) });
            $loop->write_cb($id => sub { $self->_write(@_) });
        }
    );
}

# 40 dollars!? This better be the best damn beer ever..
# *drinks beer* You got lucky.
sub run {
    my $self = shift;

    # User and group
    $self->setuidgid;

    # Prepare ioloop
    $self->prepare_ioloop;

    # Start loop
    $self->ioloop->start;
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

sub _create_pipeline {
    my ($self, $id) = @_;

    # Connection
    my $conn = $self->_connections->{$id};

    # New pipeline
    my $p = Mojo::Transaction::Pipeline->new;
    $p->connection($id);

    # Store connection information in pipeline
    my $local = $self->ioloop->local_info($id);
    $p->local_address($local->{address});
    $p->local_port($local->{port});
    my $remote = $self->ioloop->remote_info($id);
    $p->remote_address($remote->{address});
    $p->remote_port($remote->{port});

    # Weaken
    weaken $self;
    weaken $conn;

    # State change callback
    $p->state_cb(
        sub {
            my $p = shift;

            # Finish
            if ($p->is_finished) {

                # Close connection
                if (!$conn->{pipeline}->keep_alive) {
                    $self->_drop($id);
                    $self->ioloop->finish($id);
                }

                # End pipeline
                else { delete $conn->{pipeline} }
            }

            # Writing?
            $p->server_is_writing
              ? $self->ioloop->writing($id)
              : $self->ioloop->not_writing($id);
        }
    );

    # Transaction builder callback
    $p->build_tx_cb(
        sub {

            # Build transaction
            my $tx = $self->build_tx_cb->($self);

            # Handler callback
            $tx->handler_cb(
                sub {

                    # Weaken
                    weaken $tx unless isweak $tx;

                    # Handler
                    $self->handler_cb->($self, $tx);
                }
            );

            # Continue handler callback
            $tx->continue_handler_cb(
                sub {

                    # Weaken
                    weaken $tx;

                    # Continue handler
                    $self->continue_handler_cb->($self, $tx);
                }
            );

            return $tx;
        }
    );

    # New request on the connection
    $conn->{requests}++;

    # Kept alive if we have more than one request on the connection
    $p->kept_alive(1) if $conn->{requests} > 1;

    return $p;
}

sub _drop {
    my ($self, $id) = @_;

    # Drop connection
    delete $self->_connections->{$id};
}

sub _error {
    my ($self, $loop, $id, $error) = @_;

    # Drop
    $self->_drop($id);
}

sub _hup {
    my ($self, $loop, $id) = @_;

    # Drop
    $self->_drop($id);
}

sub _read {
    my ($self, $loop, $id, $chunk) = @_;

    # Pipeline
    my $p = $self->_connections->{$id}->{pipeline}
      ||= $self->_create_pipeline($id);

    # Read
    $p->server_read($chunk);

    # State machine
    $p->server_spin;

    # Add transactions to the pipe for leftovers
    if (my $leftovers = $p->server_leftovers) {

        # Read leftovers
        $p->server_read($leftovers);
    }

    # Last keep alive request?
    $p->server_tx->res->headers->connection('Close')
      if $p->server_tx
          && $self->_connections->{$id}->{requests}
          >= $self->max_keep_alive_requests;
}

sub _write {
    my ($self, $loop, $id) = @_;

    # Pipeline
    return unless my $p = $self->_connections->{$id}->{pipeline};

    # Get chunk
    my $chunk = $p->server_get_chunk;

    # State machine
    $p->server_spin;

    return $chunk;
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

=head2 C<address>

    my $address = $daemon->address;
    $daemon     = $daemon->address('127.0.0.1');

=head2 C<group>

    my $group = $daemon->group;
    $daemon   = $daemon->group('users');

=head2 C<ioloop>

    my $loop = $daemon->ioloop;
    $daemon  = $daemon->ioloop(Mojo::IOLoop->new);

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

=head2 C<prepare_ioloop>

    $daemon->prepare_ioloop;

=head2 C<run>

    $daemon->run;

=head2 C<setuidgid>

    $daemon->setuidgid;

=cut
