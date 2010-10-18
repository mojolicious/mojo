package Mojo::Server::Daemon;

use strict;
use warnings;

use base 'Mojo::Server';

use Carp 'croak';
use File::Spec;
use IO::File;
use Mojo::Command;
use Mojo::IOLoop;
use Scalar::Util 'weaken';
use Sys::Hostname;

# Bonjour
use constant BONJOUR => $ENV{MOJO_NO_BONJOUR}
  ? 0
  : eval 'use Net::Rendezvous::Publish 0.04 (); 1';

# Debug
use constant DEBUG => $ENV{MOJO_DAEMON_DEBUG} || 0;

__PACKAGE__->attr([qw/group listen listen_queue_size silent user/]);
__PACKAGE__->attr(ioloop => sub { Mojo::IOLoop->singleton });
__PACKAGE__->attr(keep_alive_timeout => 5);
__PACKAGE__->attr(max_clients        => 1000);
__PACKAGE__->attr(max_requests       => 100);
__PACKAGE__->attr(websocket_timeout  => 300);

# DEPRECATED in Comet!
*max_keep_alive_requests = \&max_requests;

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

sub prepare_ioloop {
    my $self = shift;

    # Loop
    my $loop = $self->ioloop;

    # Listen
    my $listen = $self->listen || 'http://*:3000';
    $self->_listen($_) for split ',', $listen;

    # Max clients
    $loop->max_connections($self->max_clients);
}

# 40 dollars!? This better be the best damn beer ever..
# *drinks beer* You got lucky.
sub run {
    my $self = shift;

    # Prepare ioloop
    $self->prepare_ioloop;

    # User and group
    $self->setuidgid;

    # Signals
    $SIG{INT} = $SIG{TERM} = sub { exit 0 };

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
    my $tx = $self->on_build_tx->($self);

    # Identify
    $tx->res->headers->server('Mojolicious (Perl)');

    # Connection
    $tx->connection($id);

    # Store connection information
    my $loop  = $self->ioloop;
    my $local = $loop->local_info($id);
    $tx->local_address($local->{address} || '127.0.0.1');
    $tx->local_port($local->{port});
    my $remote = $loop->remote_info($id);
    $tx->remote_address($remote->{address} || '127.0.0.1');
    $tx->remote_port($remote->{port});

    # TLS
    $tx->req->url->base->scheme('https') if $c->{tls};

    # Weaken
    weaken $self;

    # Handler callback
    $tx->on_handler(
        sub {
            my $tx = shift;

            # Handler
            $self->on_handler->($self, $tx);

            # Resume callback
            $tx->on_resume(sub { $self->_write($id) });
        }
    );

    # Upgrade callback
    $tx->on_upgrade(sub { $self->_upgrade($id, @_) });

    # New request on the connection
    $c->{requests} ||= 0;
    $c->{requests}++;

    # Kept alive if we have more than one request on the connection
    $tx->kept_alive(1) if $c->{requests} > 1;

    return $tx;
}

sub _drop {
    my ($self, $id) = @_;

    # WebSocket
    if (my $ws = $self->{_cs}->{$id}->{websocket}) { $ws->server_close }

    # Drop connection
    delete $self->{_cs}->{$id};
}

sub _error {
    my ($self, $loop, $id, $error) = @_;

    # Log
    $self->app->log->error($error);

    # Drop
    $self->_drop($id);
}

sub _finish {
    my ($self, $id, $tx) = @_;

    # WebSocket
    if ($tx->is_websocket) {
        $self->_drop($id);
        return $self->ioloop->drop($id);
    }

    # Connection
    my $c = $self->{_cs}->{$id};

    # Finish transaction
    delete $c->{transaction};
    $tx->server_close;

    # WebSocket
    my $s = 0;
    if (my $ws = $c->{websocket}) {

        # Successful upgrade
        if ($ws->res->code eq '101') {

            # Make sure connection stays active
            $tx->keep_alive(1);

            # Weaken
            weaken $self;

            # Resume callback
            $ws->on_resume(sub { $self->_write($id) });
        }

        # Failed upgrade
        else {
            delete $c->{websocket};
            $ws->server_close;
        }
    }

    # Close connection
    if ($tx->req->error || !$tx->keep_alive) {
        $self->_drop($id);
        $self->ioloop->drop($id);
    }

    # Leftovers
    elsif (defined(my $leftovers = $tx->server_leftovers)) {
        $tx = $c->{transaction} = $self->_build_tx($id, $c);
        $tx->server_read($leftovers);
    }
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
    if ($listen =~ /^file\:\/\/(.+)$/) { unlink $options->{file} = $1 }

    # Internet socket
    elsif ($listen =~ /^(http(?:s)?)\:\/\/(.+)\:(\d+)(?:\:(.*)\:(.*))?$/) {
        $options->{tls} = 1 if $1 eq 'https';
        $options->{address}  = $2 if $2 ne '*';
        $options->{port}     = $3;
        $options->{tls_cert} = $4 if $4;
        $options->{tls_key}  = $5 if $5;
    }

    # Listen queue size
    my $queue = $self->listen_queue_size;
    $options->{queue_size} = $queue if $queue;

    # Weaken
    weaken $self;

    # Callbacks
    $options->{on_accept} = sub {
        my ($loop, $id) = @_;

        # Add new connection
        $self->{_cs}->{$id} = {tls => $options->{tls} ? 1 : 0};

        # Keep alive timeout
        $loop->connection_timeout($id => $self->keep_alive_timeout);
    };
    $options->{on_error} = sub { $self->_error(@_) };
    $options->{on_hup}   = sub { $self->_hup(@_) };
    $options->{on_read}  = sub { $self->_read(@_) };

    # Listen
    my $id = $self->ioloop->listen($options);
    $self->{_listen} ||= [];
    push @{$self->{_listen}}, $id;

    # Bonjour
    if (BONJOUR && (my $p = Net::Rendezvous::Publish->new)) {
        my $port = $options->{port};
        my $name = $options->{address} || Sys::Hostname::hostname();
        $p->publish(
            name   => "Mojolicious ($name:$port)",
            type   => '_http._tcp',
            domain => 'local',
            port   => $port
        ) if $port && !$options->{tls};
    }

    # Log
    $self->app->log->info("Server listening ($listen)");

    # Friendly message
    print "Server available at $listen.\n" unless $self->silent;
}

sub _read {
    my ($self, $loop, $id, $chunk) = @_;

    # Debug
    warn "< $chunk\n" if DEBUG;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Transaction
    my $tx = $c->{transaction} || $c->{websocket};

    # New transaction
    $tx = $c->{transaction} = $self->_build_tx($id, $c) unless $tx;

    # Read
    $tx->server_read($chunk);

    # Last keep alive request
    $tx->res->headers->connection('Close')
      if ($c->{requests} || 0) >= $self->max_requests;

    # Finish
    if ($tx->is_done) { $self->_finish($id, $tx) }

    # Writing
    elsif ($tx->is_writing) { $self->_write($id) }
}

sub _upgrade {
    my ($self, $id, $tx) = @_;

    # WebSocket
    return unless $tx->req->headers->upgrade =~ /WebSocket/i;

    # Connection
    my $c = $self->{_cs}->{$id};

    # WebSocket handshake handler
    my $ws = $c->{websocket} = $self->on_websocket_handshake->($self, $tx);

    # Upgrade connection timeout
    $self->ioloop->connection_timeout($id, $self->websocket_timeout);

    # Not resumable yet
    $ws->on_resume(sub {1});
}

sub _write {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Transaction
    return unless my $tx = $c->{transaction} || $c->{websocket};

    # Not writing
    return unless $tx->is_writing;

    # Get chunk
    my $chunk = $tx->server_write;

    # Weaken
    weaken $self;

    # Callback
    my $cb = sub { $self->_write($id) };

    # Done
    if ($tx->is_done) {

        # Finish
        $self->_finish($id, $tx);

        # No followup
        $cb = undef unless $c->{transaction} || $c->{websocket};
    }

    # Not writing
    elsif (!$tx->is_writing) { $cb = undef }

    # Write
    $self->ioloop->write($id, $chunk, $cb);

    # Debug
    warn "> $chunk\n" if DEBUG;
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
server with C<IPv6>, C<TLS>, C<Bonjour>, C<epoll>, C<kqueue>, hot deployment
and UNIX domain socket sharing support.

Optional modules L<IO::KQueue>, L<IO::Epoll>, L<IO::Socket::IP>,
L<IO::Socket::SSL> and L<Net::Rendezvous::Publish> are supported
transparently and used if installed.

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

Timeout for keep alive connections in seconds, defaults to C<5>.

=head2 C<listen>

    my $listen = $daemon->listen;
    $daemon    = $daemon->listen('https://localhost:3000,file:///my.sock');

Ports and files to listen on, defaults to C<http://*:3000>.

=head2 C<listen_queue_size>

    my $listen_queue_size = $daemon->listen_queue_zise;
    $daemon               = $daemon->listen_queue_zise(128);

Listen queue size, defaults to C<SOMAXCONN>.

=head2 C<max_clients>

    my $max_clients = $daemon->max_clients;
    $daemon         = $daemon->max_clients(1000);

Maximum number of parallel client connections, defaults to C<1000>.

=head2 C<max_requests>

    my $max_requests = $daemon->max_requests;
    $daemon          = $daemon->max_requests(100);

Maximum number of keep alive requests per connection, defaults to C<100>.

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

=head2 C<prepare_ioloop>

    $daemon->prepare_ioloop;

Prepare event loop.

=head2 C<run>

    $daemon->run;

Start server.

=head2 C<setuidgid>

    $daemon->setuidgid;

Set user and group for process.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
