# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Server::Daemon;

use strict;
use warnings;

use base 'Mojo::Server';

use Carp 'croak';
use Fcntl ':flock';
use File::Spec;
use IO::File;
use Mojo::Command;
use Mojo::IOLoop;
use Scalar::Util 'weaken';
use Sys::Hostname 'hostname';

__PACKAGE__->attr([qw/group listen listen_queue_size silent user/]);
__PACKAGE__->attr(ioloop => sub { Mojo::IOLoop->singleton });
__PACKAGE__->attr(keep_alive_timeout => 15);
__PACKAGE__->attr(
    lock_file => sub {
        my $self = shift;
        return File::Spec->catfile(File::Spec->splitdir(File::Spec->tmpdir),
            Mojo::Command->class_to_file(ref $self->app) . '.lock');
    }
);
__PACKAGE__->attr(max_clients             => 1000);
__PACKAGE__->attr(max_keep_alive_requests => 100);
__PACKAGE__->attr(
    pid_file => sub {
        my $self = shift;
        return File::Spec->catfile(File::Spec->splitdir(File::Spec->tmpdir),
            Mojo::Command->class_to_file(ref $self->app) . '.pid');
    }
);
__PACKAGE__->attr(websocket_timeout => 300);

sub DESTROY {
    my $self = shift;

    # Shortcut
    return unless my $loop = $self->ioloop;

    # Cleanup connections
    my $cs = $self->{_cs} || {};
    for my $id (keys %$cs) { $loop->drop($id) }

    # Cleanup listen sockets
    return unless my $listen = $self->{_listen};
    for my $id (@$listen) { $loop->drop($id) }
}

sub accept_lock {
    my ($self, $blocking) = @_;

    # Lock
    my $flags = $blocking ? LOCK_EX : LOCK_EX | LOCK_NB;
    my $lock = flock($self->{_lock}, $flags);

    return $lock;
}

sub accept_unlock { flock(shift->{_lock}, LOCK_UN) }

sub prepare_ioloop {
    my $self = shift;

    # Lock callback
    my $loop = $self->ioloop;
    $loop->lock_cb(sub { $self->accept_lock($_[1]) });

    # Unlock callback
    $loop->unlock_cb(sub { $self->accept_unlock });

    # Stop ioloop on HUP signal
    $SIG{HUP} = sub { $loop->stop };

    # Listen
    my $listen = $self->listen || 'http://*:3000';
    $self->_listen($_) for split ',', $listen;

    # Max clients
    $loop->max_connections($self->max_clients);
}

sub prepare_lock_file {
    my $self = shift;

    my $file = $self->lock_file;

    # Create lock file
    my $fh = IO::File->new("> $file")
      or croak qq/Can't open lock file "$file"/;
    $self->{_lock} = $fh;
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

sub _build_tx {
    my ($self, $id, $c) = @_;

    # Build transaction
    my $tx = $self->build_tx_cb->($self);

    # Identify
    $tx->res->headers->server('Mojolicious (Perl)');

    # Connection
    $tx->connection($id);

    # Store connection information
    my $loop  = $self->ioloop;
    my $local = $loop->local_info($id);
    $tx->local_address($local->{address});
    $tx->local_port($local->{port});
    my $remote = $loop->remote_info($id);
    $tx->remote_address($remote->{address});
    $tx->remote_port($remote->{port});

    # TLS
    if ($c->{tls}) {
        my $url = $tx->req->url;
        $url->scheme('https');
        $url->base->scheme('https');
    }

    # Weaken
    weaken $self;

    # State change callback
    $tx->state_cb(sub { $self->_state($id, @_) });

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
    $tx->upgrade_cb(sub { $self->_upgrade($id, @_) });

    # New request on the connection
    $c->{requests}++;

    # Kept alive if we have more than one request on the connection
    $tx->kept_alive(1) if $c->{requests} > 1;

    return $tx;
}

sub _drop {
    my ($self, $id) = @_;

    # Drop connection
    delete $self->{_cs}->{$id};
}

sub _error {
    my ($self, $loop, $id, $error) = @_;

    # Log
    my $log = $self->app->log;
    $error
      ? $log->error($error)
      : $log->debug('Unknown connection error, probably harmless.');

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
        $self->{_cs}->{$id} = {tls => $options->{tls} ? 1 : 0};

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
    $self->{_listen} ||= [];
    push @{$self->{_listen}}, $id;

    # Log
    my $file    = $options->{file};
    my $address = $options->{address} || hostname;
    my $port    = $options->{port};
    my $scheme  = $options->{tls} ? 'https' : 'http';
    my $started = $file ? $file : "$scheme://$address:$port";
    $self->app->log->info("Server listening ($started)");

    # Friendly message
    print "Server available at $started.\n" unless $self->silent;
}

sub _read {
    my ($self, $loop, $id, $chunk) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Transaction
    my $tx = $c->{transaction} || $c->{websocket};

    # New transaction
    $tx = $c->{transaction} = $self->_build_tx($id) unless $tx;

    # Read
    $tx->server_read($chunk);

    # Last keep alive request
    $tx->res->headers->connection('Close')
      if ($c->{requests} || 0) >= $self->max_keep_alive_requests;
}

sub _state {
    my ($self, $id, $tx) = @_;

    # Finish
    if ($tx->is_finished) {

        # Connection
        my $c = $self->{_cs}->{$id};

        # Successful WebSocket upgrade
        my $upgraded = 0;
        $upgraded = 1
          if $c->{websocket} && $c->{websocket}->res->code eq '101';

        # Close connection
        if ($tx->req->has_error || (!$tx->keep_alive && !$upgraded)) {
            $self->_drop($id);
            $self->ioloop->drop($id);
        }

        # Cleanup connection
        else {
            delete $c->{transaction};
            delete $c->{websocket} unless $upgraded;

            # Allow early writing from the server side
            return $self->ioloop->writing($id)
              if $upgraded && $c->{websocket}->is_writing;

            # Leftovers
            if (defined(my $leftovers = $tx->server_leftovers)) {
                $tx = $c->{transaction} = $self->_build_tx($id, $c);
                $tx->server_read($leftovers);
            }
        }
    }

    # Writing
    return $tx->is_writing
      ? $self->ioloop->writing($id)
      : $self->ioloop->not_writing($id);
}

sub _upgrade {
    my ($self, $id, $tx) = @_;

    # WebSocket
    return unless $tx->req->headers->upgrade =~ /WebSocket/i;

    # Connection
    my $c = $self->{_cs}->{$id};

    # WebSocket handshake handler
    my $ws = $c->{websocket} = $self->websocket_handshake_cb->($self, $tx);

    # Upgrade connection timeout
    $self->ioloop->connection_timeout($id, $self->websocket_timeout);

    # State change callback
    $ws->state_cb(
        sub {
            my $ws = shift;

            # Writing
            return $self->ioloop->writing($id) if $ws->is_writing;

            # Finish
            if ($ws->is_finished) {
                $self->_drop($id);
                $self->ioloop->drop($id);
            }

            # Not writing
            $self->ioloop->not_writing($id);
        }
    );
}

sub _write {
    my ($self, $loop, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Transaction
    return unless my $tx = $c->{transaction} || $c->{websocket};

    # Get chunk
    my $chunk = $tx->server_write;

    return $chunk;
}

1;
__END__

=head1 NAME

Mojo::Server::Daemon - Async IO HTTP 1.1 And WebSocket Server

=head1 SYNOPSIS

    use Mojo::Server::Daemon;

    my $daemon = Mojo::Server::Daemon->new;
    $daemon->listen('http://*:8080');
    $daemon->run;

=head1 DESCRIPTION

L<Mojo::Server::Daemon> is a full featured async io HTTP 1.1 and WebSocket
server with C<IPv6>, C<TLS>, C<epoll>, C<kqueue>, hot deployment and UNIX
domain socket sharing support.

Optional modules L<IO::KQueue>, L<IO::Epoll>, L<IO::Socket::INET6> and
L<IO::Socket::SSL> are supported transparently and used if installed.

=head1 ATTRIBUTES

L<Mojo::Server::Daemon> inherits all attributes from L<Mojo::Server> and
implements the following new ones.

=head2 C<group>

    my $group = $daemon->group;
    $daemon   = $daemon->group('users');

Group for server process.

=head2 C<ioloop>

    my $loop = $daemon->ioloop;
    $daemon  = $daemon->ioloop(Mojo::IOLoop->new);

Event loop for server IO, defaults to the global L<Mojo::IOLoop> singleton.

=head2 C<keep_alive_timeout>

    my $keep_alive_timeout = $daemon->keep_alive_timeout;
    $daemon                = $daemon->keep_alive_timeout(15);

Timeout for keep alive connections in seconds, defaults to C<15>.

=head2 C<listen>

    my $listen = $daemon->listen;
    $daemon    = $daemon->listen('https://localhost:3000,file:/my.sock');

Ports and files to listen on, defaults to C<http://*:3000>.

=head2 C<listen_queue_size>

    my $listen_queue_size = $daemon->listen_queue_zise;
    $daemon               = $daemon->listen_queue_zise(128);

Listen queue size, defaults to C<SOMAXCONN>.

=head2 C<lock_file>

    my $lock_file = $daemon->lock_file;
    $daemon       = $daemon->lock_file('/tmp/mojo_daemon.lock');

Path to lock file, defaults to a random temporary file.

=head2 C<max_clients>

    my $max_clients = $daemon->max_clients;
    $daemon         = $daemon->max_clients(1000);

Maximum number of parallel client connections, defaults to C<1000>.

=head2 C<max_keep_alive_requests>

    my $max_keep_alive_requests = $daemon->max_keep_alive_requests;
    $daemon                     = $daemon->max_keep_alive_requests(100);

Maximum number of keep alive requests per connection, defaults to C<100>.

=head2 C<pid_file>

    my $pid_file = $daemon->pid_file;
    $daemon      = $daemon->pid_file('/tmp/mojo_daemon.pid');

Path to process id file, defaults to a random temporary file.

=head2 C<silent>

    my $silent = $daemon->silent;
    $daemon    = $daemon->silent(1);

Disable console messages.

=head2 C<user>

    my $user = $daemon->user;
    $daemon  = $daemon->user('web');

User for the server process.

=head2 C<websocket_timeout>

    my $websocket_timeout = $server->websocket_timeout;
    $server               = $server->websocket_timeout(300);

Timeout in seconds for WebSockets to be idle, defaults to C<300>.

=head1 METHODS

L<Mojo::Server::Daemon> inherits all methods from L<Mojo::Server> and
implements the following new ones.

=head2 C<accept_lock>

    my $lock = $daemon->accept_lock($blocking);

Try to get the accept lock.

=head2 C<accept_unlock>

    $daemon->accept_unlock;

Free the accept lock.

=head2 C<prepare_ioloop>

    $daemon->prepare_ioloop;

Prepare event loop.

=head2 C<prepare_lock_file>

    $daemon->prepare_lock_file;

Prepare the lock file.

=head2 C<prepare_pid_file>

    $daemon->prepare_pid_file;

Prepare process id file.

=head2 C<run>

    $daemon->run;

Start server.

=head2 C<setuidgid>

    $daemon->setuidgid;

Set user and group for process.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Book>, L<http://mojolicious.org>.

=cut
