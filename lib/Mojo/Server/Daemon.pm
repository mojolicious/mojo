# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Server::Daemon;

use strict;
use warnings;

use base 'Mojo::Server';
use bytes;

use Carp 'croak';
use Fcntl ':flock';
use File::Spec;
use IO::File;
use Mojo::IOLoop;
use Mojo::Transaction::Pipeline;
use Mojo::Transaction::WebSocket;
use Scalar::Util 'weaken';
use Sys::Hostname 'hostname';

__PACKAGE__->attr([qw/group listen listen_queue_size user/]);
__PACKAGE__->attr(ioloop => sub { Mojo::IOLoop->singleton });
__PACKAGE__->attr(keep_alive_timeout => 15);
__PACKAGE__->attr(
    lock_file => sub {
        return File::Spec->catfile(File::Spec->splitdir(File::Spec->tmpdir),
            'mojo_daemon.lock');
    }
);
__PACKAGE__->attr(max_clients             => 1000);
__PACKAGE__->attr(max_keep_alive_requests => 100);
__PACKAGE__->attr(
    pid_file => sub {
        return File::Spec->catfile(File::Spec->splitdir(File::Spec->tmpdir),
            'mojo_daemon.pid');
    }
);

__PACKAGE__->attr(_connections => sub { {} });
__PACKAGE__->attr(_listening   => sub { [] });
__PACKAGE__->attr('_lock');

sub DESTROY {
    my $self = shift;

    # Shortcut
    return unless $self->ioloop;

    # Cleanup connections
    for my $id (keys %{$self->_connections}) { $self->ioloop->drop($id) }

    # Cleanup listen sockets
    for my $id (@{$self->_listening}) { $self->ioloop->drop($id) }
}

sub accept_lock {
    my ($self, $blocking) = @_;

    # Lock
    my $flags = $blocking ? LOCK_EX : LOCK_EX | LOCK_NB;
    my $lock = flock($self->_lock, $flags);

    return $lock;
}

sub accept_unlock { flock(shift->_lock, LOCK_UN) }

sub prepare_ioloop {
    my $self = shift;

    # Lock callback
    $self->ioloop->lock_cb(sub { $self->accept_lock($_[1]) });

    # Unlock callback
    $self->ioloop->unlock_cb(sub { $self->accept_unlock });

    # Stop ioloop on HUP signal
    $SIG{HUP} = sub { $self->ioloop->stop };

    # Listen
    my $listen = $self->listen || 'http://*:3000';
    $self->_listen($_) for split ',', $listen;

    # Max clients
    $self->ioloop->max_connections($self->max_clients);
}

sub prepare_lock_file {
    my $self = shift;

    my $file = $self->lock_file;

    # Create lock file
    my $fh = IO::File->new("> $file")
      or croak qq/Can't open lock file "$file"/;
    $self->_lock($fh);
}

sub prepare_pid_file {
    my $self = shift;

    my $file = $self->pid_file;

    # PID file
    my $fh;
    if (-e $file) {
        $fh = IO::File->new("< $file")
          or croak qq/Can't open PID file "$file": $!/;
        my $pid = <$fh>;
        warn "Server already running with PID $pid.\n" if kill 0, $pid;
        warn qq/Can't unlink PID file "$file".\n/
          unless -w $file && unlink $file;
    }

    # Create new PID file
    $fh = IO::File->new($file, O_WRONLY | O_CREAT | O_EXCL, 0644)
      or croak qq/Can't create PID file "$file"/;

    # PID
    print $fh $$;
    close $fh;

    # Signals
    $SIG{INT} = $SIG{TERM} = sub {

        # Remove PID file
        unlink $self->pid_file;

        # Done
        exit 0;
    };
}

# 40 dollars!? This better be the best damn beer ever..
# *drinks beer* You got lucky.
sub run {
    my $self = shift;

    # User and group
    $self->setuidgid;

    # Prepare PID file
    $self->prepare_pid_file;

    # Prepare lock file
    $self->prepare_lock_file;

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
                if (!$conn->{pipeline}->keep_alive && !$conn->{websocket}) {
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

            # TLS
            if ($conn->{tls}) {
                $tx->req->url->scheme('https');
                $tx->req->url->base->scheme('https');
            }

            # Handler callback
            $tx->handler_cb(
                sub {
                    my $tx = shift;

                    # Handler
                    $self->handler_cb->($self, $tx);
                }
            );

            # Continue handler callback
            $tx->continue_handler_cb(
                sub {
                    my $tx = shift;

                    # Continue handler
                    $self->continue_handler_cb->($self, $tx);
                }
            );

            # Upgrade callback
            $tx->upgrade_cb(
                sub {
                    my $tx = shift;

                    # WebSocket?
                    return unless $tx->req->headers->upgrade =~ /WebSocket/i;

                    # WebSocket handshake handler
                    my $ws = $conn->{websocket} =
                      $self->websocket_handshake_cb->($self, $tx);

                    # State change callback
                    $ws->state_cb(
                        sub {
                            my $ws = shift;

                            # Finish
                            if ($ws->is_finished) {
                                $self->_drop($id);
                                $self->ioloop->finish($id);
                            }

                            # Writing?
                            $ws->server_is_writing
                              ? $self->ioloop->writing($id)
                              : $self->ioloop->not_writing($id);
                        }
                    );
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

sub _listen {
    my ($self, $listen) = @_;

    # Shortcut
    return unless $listen;

    # Options
    my $options = {};

    # UNIX domain socket
    if ($listen =~ /^file\:\/\/\/(.+)$/) { $options->{file} = $1 }

    # Internet socket
    elsif ($listen =~ /^(http(?:s)?)\:\/\/(.+)\:(\d+)(?:\:(.*)\:(.*))?$/) {
        $options->{tls} = 1 if $1 eq 'https';
        $options->{address}  = $2 unless $2 eq '*';
        $options->{port}     = $3;
        $options->{tls_cert} = $4 if $4;
        $options->{tls_key}  = $5 if $5;
    }

    # Listen queue size
    my $queue = $self->listen_queue_size;
    $options->{queue_size} = $queue if $queue;

    # Weaken
    weaken $self;

    # Accept callback
    $options->{cb} = sub {
        my ($loop, $id) = @_;

        # Add new connection
        $self->_connections->{$id} = {tls => $options->{tls} ? 1 : 0};

        # Keep alive timeout
        $loop->connection_timeout($id => $self->keep_alive_timeout);

        # Callbacks
        $loop->error_cb($id => sub { $self->_error(@_) });
        $loop->hup_cb($id => sub { $self->_hup(@_) });
        $loop->read_cb($id => sub { $self->_read(@_) });
        $loop->write_cb($id => sub { $self->_write(@_) });
    };

    # Listen
    my $id = $self->ioloop->listen($options);
    push @{$self->_listening}, $id;

    # Log
    my $file    = $options->{file};
    my $address = $options->{address} || hostname;
    my $port    = $options->{port};
    my $scheme  = $options->{tls} ? 'https' : 'http';
    my $started = $file ? $file : "$scheme://$address:$port";
    $self->app->log->info("Server listening ($started)");

    # Friendly message
    print "Server available at $started.\n";
}

sub _read {
    my ($self, $loop, $id, $chunk) = @_;

    # Pipeline?
    my $tx = $self->_connections->{$id}->{pipeline};

    # WebSocket
    $tx ||= $self->_connections->{$id}->{websocket};

    # Create pipeline
    $tx = $self->_connections->{$id}->{pipeline} =
      $self->_create_pipeline($id)
      unless $tx;

    # Read
    $tx->server_read($chunk);

    # WebSocket?
    return if $tx->is_websocket;

    # State machine
    $tx->server_spin;

    # Add transactions to the pipe for leftovers
    if (my $leftovers = $tx->server_leftovers) {

        # Read leftovers
        $tx->server_read($leftovers);
    }

    # Last keep alive request?
    $tx->server_tx->res->headers->connection('Close')
      if $tx->server_tx
          && $self->_connections->{$id}->{requests}
          >= $self->max_keep_alive_requests;
}

sub _write {
    my ($self, $loop, $id) = @_;

    # Pipeline
    my $tx = $self->_connections->{$id}->{pipeline};

    # WebSocket
    $tx ||= $self->_connections->{$id}->{websocket};

    # No transaction
    return unless $tx;

    # Get chunk
    my $chunk = $tx->server_get_chunk;

    # WebSocket?
    return $chunk if $tx->is_websocket;

    # State machine
    $tx->server_spin;

    return $chunk;
}

1;
__END__

=head1 NAME

Mojo::Server::Daemon - HTTP Server

=head1 SYNOPSIS

    use Mojo::Server::Daemon;

    my $daemon = Mojo::Server::Daemon->new;
    $daemon->listen('http://*:8080');
    $daemon->run;

=head1 DESCRIPTION

L<Mojo::Server::Daemon> is a simple and portable async io based HTTP server.

=head1 ATTRIBUTES

L<Mojo::Server::Daemon> inherits all attributes from L<Mojo::Server> and
implements the following new ones.

=head2 C<group>

    my $group = $daemon->group;
    $daemon   = $daemon->group('users');

=head2 C<ioloop>

    my $loop = $daemon->ioloop;
    $daemon  = $daemon->ioloop(Mojo::IOLoop->new);

=head2 C<keep_alive_timeout>

    my $keep_alive_timeout = $daemon->keep_alive_timeout;
    $daemon                = $daemon->keep_alive_timeout(15);

=head2 C<listen>

    my $listen = $daemon->listen;
    $daemon    = $daemon->listen('https:localhost:3000,file:/my.sock');

=head2 C<listen_queue_size>

    my $listen_queue_size = $daemon->listen_queue_zise;
    $daemon               = $daemon->listen_queue_zise(128);

=head2 C<lock_file>

    my $lock_file = $daemon->lock_file;
    $daemon       = $daemon->lock_file('/tmp/mojo_daemon.lock');

=head2 C<max_clients>

    my $max_clients = $daemon->max_clients;
    $daemon         = $daemon->max_clients(1000);

=head2 C<max_keep_alive_requests>

    my $max_keep_alive_requests = $daemon->max_keep_alive_requests;
    $daemon                     = $daemon->max_keep_alive_requests(100);

=head2 C<pid_file>

    my $pid_file = $daemon->pid_file;
    $daemon      = $daemon->pid_file('/tmp/mojo_daemon.pid');

=head2 C<user>

    my $user = $daemon->user;
    $daemon  = $daemon->user('web');

=head1 METHODS

L<Mojo::Server::Daemon> inherits all methods from L<Mojo::Server> and
implements the following new ones.

=head2 C<accept_lock>

    my $lock = $daemon->accept_lock($blocking);

=head2 C<accept_unlock>

    $daemon->accept_unlock;

=head2 C<prepare_ioloop>

    $daemon->prepare_ioloop;

=head2 C<prepare_lock_file>

    $daemon->prepare_lock_file;

=head2 C<prepare_pid_file>

    $daemon->prepare_pid_file;

=head2 C<run>

    $daemon->run;

=head2 C<setuidgid>

    $daemon->setuidgid;

=cut
