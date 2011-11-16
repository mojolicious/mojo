package Mojo::Server::Daemon;
use Mojo::Base 'Mojo::Server';

use Carp 'croak';
use Mojo::IOLoop;
use POSIX;
use Scalar::Util 'weaken';
use Sys::Hostname;

# Bonjour
use constant BONJOUR => $ENV{MOJO_NO_BONJOUR}
  ? 0
  : eval 'use Net::Rendezvous::Publish 0.04 (); 1';

use constant DEBUG => $ENV{MOJO_DAEMON_DEBUG} || 0;

has [qw/backlog group listen silent user/];
has ioloop => sub { Mojo::IOLoop->singleton };
has keep_alive_timeout => 15;
has max_clients        => 1000;
has max_requests       => 25;
has websocket_timeout  => 300;

my $SOCKET_RE = qr|
  ^
  (?<scheme>http(?:s)?)\://   # Scheme
  (?<address>.+)                # Address
  \:(?<port>\d+)                # Port
  (?:
    \:(?<cert>.*?)              # Certificate
    \:(?<key>.*?)               # Key
    (?:\:(?<ca>.+)?)?           # Certificate Authority
  )?
  $
|x;

sub DESTROY {
  my $self = shift;

  # Clean up connections
  return unless my $loop = $self->ioloop;
  my $cs = $self->{connections} || {};
  for my $id (keys %$cs) { $loop->drop($id) }

  # Clean up listen sockets
  return unless my $listen = $self->{listening};
  for my $id (@$listen) { $loop->drop($id) }
}

sub prepare_ioloop {
  my $self = shift;
  $self->_listen($_) for @{$self->listen || ['http://*:3000']};
  $self->ioloop->max_connections($self->max_clients);
}

# "40 dollars!? This better be the best damn beer ever..
#  *drinks beer* You got lucky."
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
  $self->_group;
  $self->_user;
  return $self;
}

sub _build_tx {
  my ($self, $id, $c) = @_;

  # Build transaction
  my $tx = $self->build_tx;
  $tx->connection($id);

  # Identify
  $tx->res->headers->server('Mojolicious (Perl)');

  # Store connection information
  my $handle = $self->ioloop->stream($id)->handle;
  $tx->local_address($handle->sockhost);
  $tx->local_port($handle->sockport);
  $tx->remote_address($handle->peerhost);
  $tx->remote_port($handle->peerport);

  # TLS
  $tx->req->url->base->scheme('https') if $c->{tls};

  # Events
  weaken $self;
  $tx->on(
    upgrade => sub {
      my ($tx, $ws) = @_;
      $self->{connections}->{$id}->{websocket} = $ws->server_handshake;
    }
  );
  $tx->on(
    request => sub {
      my $tx = shift;
      $self->emit(request => $self->{connections}->{$id}->{websocket} || $tx);
      $tx->on(resume => sub { $self->_write($id) });
    }
  );

  # New request on the connection
  $c->{requests} ||= 0;
  $c->{requests}++;

  # Kept alive if we have more than one request on the connection
  $tx->kept_alive(1) if $c->{requests} > 1;

  return $tx;
}

sub _close { shift->_drop(pop) }

sub _drop {
  my ($self, $id) = @_;

  # Finish gracefully
  my $c = $self->{connections}->{$id};
  if (my $tx = $c->{websocket} || $c->{transaction}) { $tx->server_close }

  # Drop connection
  delete $self->{connections}->{$id};
}

sub _error {
  my ($self, $id, $error) = @_;
  $self->app->log->error($error);
  $self->_drop($id);
}

sub _finish {
  my ($self, $id, $tx) = @_;

  # WebSocket
  if ($tx->is_websocket) {
    $self->_drop($id);
    return $self->ioloop->drop($id);
  }

  # Finish transaction
  my $c = $self->{connections}->{$id};
  delete $c->{transaction};
  $tx->server_close;

  # WebSocket
  my $s = 0;
  if (my $ws = $c->{websocket}) {

    # Successful upgrade
    if ($ws->res->code eq '101') {

      # Upgrade connection timeout
      $self->ioloop->timeout($id, $self->websocket_timeout);

      # Resume
      weaken $self;
      $ws->on(resume => sub { $self->_write($id) });
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

sub _group {
  my $self = shift;
  return unless my $group = $self->group;
  croak qq/Group "$group" does not exist/
    unless defined(my $gid = (getgrnam($group))[2]);
  POSIX::setgid($gid) or croak qq/Can't switch to group "$group": $!/;
}

sub _listen {
  my ($self, $listen) = @_;
  return unless $listen;

  # Check listen value
  croak qq/Invalid listen value "$listen"/ unless $listen =~ $SOCKET_RE;
  my $options = {};
  my $tls;
  $tls = $options->{tls} = 1 if $+{scheme} eq 'https';
  $options->{address}  = $+{address} if $+{address} ne '*';
  $options->{port}     = $+{port};
  $options->{tls_cert} = $+{cert} if $+{cert};
  $options->{tls_key}  = $+{key} if $+{key};
  $options->{tls_ca}   = $+{ca} if $+{ca};

  # Listen backlog size
  my $backlog = $self->backlog;
  $options->{backlog} = $backlog if $backlog;

  # Listen
  weaken $self;
  my $id = $self->ioloop->server(
    $options => sub {
      my ($loop, $stream, $id) = @_;

      # Add new connection
      $self->{connections}->{$id} = {tls => $tls};

      # Keep alive timeout
      $loop->timeout($id => $self->keep_alive_timeout);

      # Events
      $stream->on(close => sub { $self->_close($id) });
      $stream->on(error => sub { $self->_error($id, pop) });
      $stream->on(read  => sub { $self->_read($id, pop) });
    }
  );
  $self->{listening} ||= [];
  push @{$self->{listening}}, $id;

  # Bonjour
  if (BONJOUR && (my $p = Net::Rendezvous::Publish->new)) {
    my $port = $options->{port};
    my $name = $options->{address} || Sys::Hostname::hostname();
    $p->publish(
      name   => "Mojolicious ($name:$port)",
      type   => '_http._tcp',
      domain => 'local',
      port   => $port
    ) if $port && !$tls;
  }

  # Friendly message
  return if $self->silent;
  $self->app->log->info("Server listening ($listen)");
  $listen =~ s|^(https?\://)\*|${1}127.0.0.1|i;
  say "Server available at $listen.";
}

sub _read {
  my ($self, $id, $chunk) = @_;
  warn "< $chunk\n" if DEBUG;

  # Make sure we have a transaction
  my $c = $self->{connections}->{$id};
  my $tx = $c->{transaction} || $c->{websocket};
  $tx ||= $c->{transaction} = $self->_build_tx($id, $c);

  # Parse chunk
  $tx->server_read($chunk);

  # Last keep alive request
  $tx->res->headers->connection('close')
    if ($c->{requests} || 0) >= $self->max_requests;

  # Finish or start writing
  if ($tx->is_finished) { $self->_finish($id, $tx) }
  elsif ($tx->is_writing) { $self->_write($id) }
}

sub _user {
  my $self = shift;
  return unless my $user = $self->user;
  croak qq/User "$user" does not exist/
    unless defined(my $uid = (getpwnam($self->user))[2]);
  POSIX::setuid($uid) or croak qq/Can't switch to user "$user": $!/;
}

sub _write {
  my ($self, $id) = @_;

  # Not writing
  my $c = $self->{connections}->{$id};
  return unless my $tx = $c->{transaction} || $c->{websocket};
  return unless $tx->is_writing;

  # Get chunk
  return if $c->{writing}++;
  my $chunk = $tx->server_write;
  delete $c->{writing};
  warn "> $chunk\n" if DEBUG;

  # Write
  my $stream = $self->ioloop->stream($id);
  $stream->write($chunk);

  # Finish or continue writing
  weaken $self;
  my $cb = sub { $self->_write($id) };
  if ($tx->is_finished) {
    if ($tx->has_subscribers('finish')) {
      $cb = sub { $self->_finish($id, $tx) }
    }
    else {
      $self->_finish($id, $tx);
      return unless $c->{transaction} || $c->{websocket};
    }
  }
  $stream->write('', $cb);
}

1;
__END__

=head1 NAME

Mojo::Server::Daemon - Non-blocking I/O HTTP 1.1 and WebSocket server

=head1 SYNOPSIS

  use Mojo::Server::Daemon;

  my $daemon = Mojo::Server::Daemon->new(listen => ['http://*:8080']);
  $daemon->unsubscribe('request');
  $daemon->on(request => sub {
    my ($daemon, $tx) = @_;

    # Request
    my $method = $tx->req->method;
    my $path   = $tx->req->url->path;

    # Response
    $tx->res->code(200);
    $tx->res->headers->content_type('text/plain');
    $tx->res->body("$method request for $path!");

    # Resume transaction
    $tx->resume;
  });
  $daemon->run;

=head1 DESCRIPTION

L<Mojo::Server::Daemon> is a full featured non-blocking I/O HTTP 1.1 and
WebSocket server with C<IPv6>, C<TLS>, C<Bonjour> and C<libev> support.

Optional modules L<EV>, L<IO::Socket::IP>, L<IO::Socket::SSL> and
L<Net::Rendezvous::Publish> are supported transparently and used if
installed.

See L<Mojolicious::Guides::Cookbook> for deployment recipes.

=head1 EVENTS

L<Mojo::Server::Daemon> inherits all events from L<Mojo::Server>.

=head1 ATTRIBUTES

L<Mojo::Server::Daemon> inherits all attributes from L<Mojo::Server> and
implements the following new ones.

=head2 C<backlog>

  my $backlog = $daemon->backlog;
  $daemon     = $daemon->backlog(128);

Listen backlog size, defaults to C<SOMAXCONN>.

=head2 C<group>

  my $group = $daemon->group;
  $daemon   = $daemon->group('users');

Group for server process.

=head2 C<ioloop>

  my $loop = $daemon->ioloop;
  $daemon  = $daemon->ioloop(Mojo::IOLoop->new);

Loop object to use for I/O operations, defaults to the global L<Mojo::IOLoop>
singleton.

=head2 C<keep_alive_timeout>

  my $keep_alive_timeout = $daemon->keep_alive_timeout;
  $daemon                = $daemon->keep_alive_timeout(5);

Maximum amount of time in seconds a connection can be inactive before getting
dropped, defaults to C<15>.

=head2 C<listen>

  my $listen = $daemon->listen;
  $daemon    = $daemon->listen(['https://localhost:3000']);

List of one or more locations to listen on, defaults to C<http://*:3000>.

  # Listen on two ports with HTTP and HTTPS at the same time
  $daemon->listen(['http://*:3000', 'https://*:4000']);

  # Use a custom certificate and key
  $daemon->listen(['https://*:3000:/x/server.crt:/y/server.key']);

  # Or even a custom certificate authority
  $daemon->listen(['https://*:3000:/x/server.crt:/y/server.key:/z/ca.crt']);

=head2 C<max_clients>

  my $max_clients = $daemon->max_clients;
  $daemon         = $daemon->max_clients(1000);

Maximum number of parallel client connections, defaults to C<1000>.

=head2 C<max_requests>

  my $max_requests = $daemon->max_requests;
  $daemon          = $daemon->max_requests(100);

Maximum number of keep alive requests per connection, defaults to C<25>.

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

Maximum amount of time in seconds a WebSocket connection can be inactive
before getting dropped, defaults to C<300>.

=head1 METHODS

L<Mojo::Server::Daemon> inherits all methods from L<Mojo::Server> and
implements the following new ones.

=head2 C<prepare_ioloop>

  $daemon->prepare_ioloop;

Prepare loop.

=head2 C<run>

  $daemon->run;

Start server.

=head2 C<setuidgid>

  $daemon->setuidgid;

Set user and group for process.

=head1 DEBUGGING

You can set the C<MOJO_DAEMON_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_DAEMON_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
