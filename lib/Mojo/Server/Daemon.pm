package Mojo::Server::Daemon;
use Mojo::Base 'Mojo::Server';

use Carp 'croak';
use Mojo::IOLoop;
use Mojo::Transaction::WebSocket;
use Mojo::URL;
use Mojo::Util qw(deprecated term_escape);
use Mojo::WebSocket 'server_handshake';
use Scalar::Util 'weaken';

use constant DEBUG => $ENV{MOJO_DAEMON_DEBUG} || 0;

has acceptors => sub { [] };
has [qw(backlog max_clients silent)];
has inactivity_timeout => sub { $ENV{MOJO_INACTIVITY_TIMEOUT} // 15 };
has ioloop => sub { Mojo::IOLoop->singleton };
has listen => sub { [split ',', $ENV{MOJO_LISTEN} || 'http://*:3000'] };
has max_requests => 100;

sub DESTROY {
  return if Mojo::Util::_global_destruction();
  my $self = shift;
  $self->_remove($_) for keys %{$self->{connections} || {}};
  my $loop = $self->ioloop;
  $loop->remove($_) for @{$self->acceptors};
}

# DEPRECATED!
sub multi_accept {
  deprecated 'Mojo::Server::Daemon::multi_accept is DEPRECATED';
  @_ > 1 ? $_[0] : undef;
}

sub run {
  my $self = shift;

  # Make sure the event loop can be stopped in regular intervals
  my $loop = $self->ioloop;
  my $int = $loop->recurring(1 => sub { });
  local $SIG{INT} = local $SIG{TERM} = sub { $loop->stop };
  $self->start->ioloop->start;
  $loop->remove($int);
}

sub start {
  my $self = shift;

  my $loop = $self->ioloop;
  if (my $max = $self->max_clients) { $loop->max_connections($max) }

  # Resume accepting connections
  if (my $servers = $self->{servers}) {
    push @{$self->acceptors}, $loop->acceptor(delete $servers->{$_})
      for keys %$servers;
  }

  # Start listening
  elsif (!@{$self->acceptors}) { $self->_listen($_) for @{$self->listen} }

  return $self;
}

sub stop {
  my $self = shift;

  # Suspend accepting connections but keep listen sockets open
  my $loop = $self->ioloop;
  while (my $id = shift @{$self->acceptors}) {
    my $server = $self->{servers}{$id} = $loop->acceptor($id);
    $loop->remove($id);
    $server->stop;
  }

  return $self;
}

sub _build_tx {
  my ($self, $id, $c) = @_;

  my $tx = $self->build_tx->connection($id);
  $tx->res->headers->server('Mojolicious (Perl)');
  my $handle = $self->ioloop->stream($id)->handle;
  $tx->local_address($handle->sockhost)->local_port($handle->sockport);
  $tx->remote_address($handle->peerhost)->remote_port($handle->peerport);
  $tx->req->url->base->scheme('https') if $c->{tls};

  weaken $self;
  $tx->on(
    request => sub {
      my $tx = shift;

      # WebSocket
      if ($tx->req->is_handshake) {
        my $ws = $self->{connections}{$id}{next}
          = Mojo::Transaction::WebSocket->new(handshake => $tx);
        $self->emit(request => server_handshake $ws);
      }

      # HTTP
      else { $self->emit(request => $tx) }

      # Last keep-alive request or corrupted connection
      my $c = $self->{connections}{$id};
      $tx->res->headers->connection('close')
        if $c->{requests} >= $self->max_requests || $tx->req->error;

      $tx->on(resume => sub { $self->_write($id) });
      $self->_write($id);
    }
  );

  # Kept alive if we have more than one request on the connection
  return ++$c->{requests} > 1 ? $tx->kept_alive(1) : $tx;
}

sub _close {
  my ($self, $id) = @_;
  if (my $tx = $self->{connections}{$id}{tx}) { $tx->closed }
  delete $self->{connections}{$id};
}

sub _debug { $_[0]->app->log->debug($_[2]) if $_[0]{connections}{$_[1]}{tx} }

sub _finish {
  my ($self, $id) = @_;

  # Always remove connection for WebSockets
  my $c = $self->{connections}{$id};
  return unless my $tx = $c->{tx};
  return $self->_remove($id) if $tx->is_websocket;

  # Finish transaction
  delete($c->{tx})->closed;

  # Upgrade connection to WebSocket
  if (my $ws = delete $c->{next}) {

    # Successful upgrade
    if ($ws->handshake->res->code == 101) {
      $c->{tx} = $ws->established(1);
      weaken $self;
      $ws->on(resume => sub { $self->_write($id) });
      $self->_write($id);
    }

    # Failed upgrade
    else { $ws->closed }
  }

  # Close connection if necessary
  return $self->_remove($id) if $tx->error || !$tx->keep_alive;

  # Build new transaction for leftovers
  return unless length(my $leftovers = $tx->req->content->leftovers);
  $tx = $c->{tx} = $self->_build_tx($id, $c);
  $tx->server_read($leftovers);
}

sub _listen {
  my ($self, $listen) = @_;

  my $url   = Mojo::URL->new($listen);
  my $proto = $url->protocol;
  croak qq{Invalid listen location "$listen"} unless $proto =~ /^https?$/;

  my $query   = $url->query;
  my $options = {
    address       => $url->host,
    backlog       => $self->backlog,
    single_accept => $query->param('single_accept'),
    reuse         => $query->param('reuse')
  };
  if (my $port = $url->port) { $options->{port} = $port }
  $options->{"tls_$_"} = $query->param($_) for qw(ca ciphers version);
  /^(.*)_(cert|key)$/ and $options->{"tls_$2"}{$1} = $query->param($_)
    for @{$query->names};
  if (my $cert = $query->param('cert')) { $options->{'tls_cert'}{''} = $cert }
  if (my $key  = $query->param('key'))  { $options->{'tls_key'}{''}  = $key }
  my $verify = $query->param('verify');
  $options->{tls_verify} = hex $verify if defined $verify;
  delete $options->{address} if $options->{address} eq '*';
  my $tls = $options->{tls} = $proto eq 'https';

  weaken $self;
  push @{$self->acceptors}, $self->ioloop->server(
    $options => sub {
      my ($loop, $stream, $id) = @_;

      $self->{connections}{$id} = {tls => $tls};
      warn "-- Accept $id (@{[$stream->handle->peerhost]})\n" if DEBUG;
      $stream->timeout($self->inactivity_timeout);

      $stream->on(close => sub { $self && $self->_close($id) });
      $stream->on(error =>
          sub { $self && $self->app->log->error(pop) && $self->_close($id) });
      $stream->on(read => sub { $self->_read($id => pop) });
      $stream->on(timeout => sub { $self->_debug($id, 'Inactivity timeout') });
    }
  );

  return if $self->silent;
  $self->app->log->info(qq{Listening at "$url"});
  $query->pairs([]);
  $url->host('127.0.0.1') if $url->host eq '*';
  say "Server available at $url";
}

sub _read {
  my ($self, $id, $chunk) = @_;

  # Make sure we have a transaction
  my $c = $self->{connections}{$id};
  my $tx = $c->{tx} ||= $self->_build_tx($id, $c);
  warn term_escape "-- Server <<< Client (@{[_url($tx)]})\n$chunk\n" if DEBUG;
  $tx->server_read($chunk);
}

sub _remove {
  my ($self, $id) = @_;
  $self->ioloop->remove($id);
  $self->_close($id);
}

sub _url { shift->req->url->to_abs }

sub _write {
  my ($self, $id) = @_;

  # Protect from resume event recursion
  my $c = $self->{connections}{$id};
  return if !(my $tx = $c->{tx}) || $c->{writing};
  local $c->{writing} = 1;
  my $chunk = $tx->server_write;
  warn term_escape "-- Server >>> Client (@{[_url($tx)]})\n$chunk\n" if DEBUG;
  my $next = $tx->is_finished ? '_finish' : length $chunk ? '_write' : undef;
  return $self->ioloop->stream($id)->write($chunk) unless $next;
  weaken $self;
  $self->ioloop->stream($id)->write($chunk => sub { $self->$next($id) });
}

1;

=encoding utf8

=head1 NAME

Mojo::Server::Daemon - Non-blocking I/O HTTP and WebSocket server

=head1 SYNOPSIS

  use Mojo::Server::Daemon;

  my $daemon = Mojo::Server::Daemon->new(listen => ['http://*:8080']);
  $daemon->unsubscribe('request')->on(request => sub {
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

L<Mojo::Server::Daemon> is a full featured, highly portable non-blocking I/O
HTTP and WebSocket server, with IPv6, TLS, SNI, Comet (long polling), keep-alive
and multiple event loop support.

For better scalability (epoll, kqueue) and to provide non-blocking name
resolution, SOCKS5 as well as TLS support, the optional modules L<EV> (4.0+),
L<Net::DNS::Native> (0.15+), L<IO::Socket::Socks> (0.64+) and
L<IO::Socket::SSL> (1.94+) will be used automatically if possible. Individual
features can also be disabled with the C<MOJO_NO_NDN>, C<MOJO_NO_SOCKS> and
C<MOJO_NO_TLS> environment variables.

See L<Mojolicious::Guides::Cookbook/"DEPLOYMENT"> for more.

=head1 SIGNALS

The L<Mojo::Server::Daemon> process can be controlled at runtime with the
following signals.

=head2 INT, TERM

Shut down server immediately.

=head1 EVENTS

L<Mojo::Server::Daemon> inherits all events from L<Mojo::Server>.

=head1 ATTRIBUTES

L<Mojo::Server::Daemon> inherits all attributes from L<Mojo::Server> and
implements the following new ones.

=head2 acceptors

  my $acceptors = $daemon->acceptors;
  $daemon       = $daemon->acceptors(['6be0c140ef00a389c5d039536b56d139']);

Active acceptor ids.

  # Check port
  mu $port = $daemon->ioloop->acceptor($daemon->acceptors->[0])->port;

=head2 backlog

  my $backlog = $daemon->backlog;
  $daemon     = $daemon->backlog(128);

Listen backlog size, defaults to C<SOMAXCONN>.

=head2 inactivity_timeout

  my $timeout = $daemon->inactivity_timeout;
  $daemon     = $daemon->inactivity_timeout(5);

Maximum amount of time in seconds a connection can be inactive before getting
closed, defaults to the value of the C<MOJO_INACTIVITY_TIMEOUT> environment
variable or C<15>. Setting the value to C<0> will allow connections to be
inactive indefinitely.

=head2 ioloop

  my $loop = $daemon->ioloop;
  $daemon  = $daemon->ioloop(Mojo::IOLoop->new);

Event loop object to use for I/O operations, defaults to the global
L<Mojo::IOLoop> singleton.

=head2 listen

  my $listen = $daemon->listen;
  $daemon    = $daemon->listen(['https://127.0.0.1:8080']);

Array reference with one or more locations to listen on, defaults to the value
of the C<MOJO_LISTEN> environment variable or C<http://*:3000> (shortcut for
C<http://0.0.0.0:3000>).

  # Listen on all IPv4 interfaces
  $daemon->listen(['http://*:3000']);

  # Listen on all IPv4 and IPv6 interfaces
  $daemon->listen(['http://[::]:3000']);

  # Listen on IPv6 interface
  $daemon->listen(['http://[::1]:4000']);

  # Listen on IPv4 and IPv6 interfaces
  $daemon->listen(['http://127.0.0.1:3000', 'http://[::1]:3000']);

  # Allow multiple servers to use the same port (SO_REUSEPORT)
  $daemon->listen(['http://*:8080?reuse=1']);

  # Listen on two ports with HTTP and HTTPS at the same time
  $daemon->listen(['http://*:3000', 'https://*:4000']);

  # Use a custom certificate and key
  $daemon->listen(['https://*:3000?cert=/x/server.crt&key=/y/server.key']);

  # Domain specific certificates and keys (SNI)
  $daemon->listen(
    ['https://*:3000?example.com_cert=/x/my.crt&example.com_key=/y/my.key']);

  # Or even a custom certificate authority
  $daemon->listen(
    ['https://*:3000?cert=/x/server.crt&key=/y/server.key&ca=/z/ca.crt']);

These parameters are currently available:

=over 2

=item ca

  ca=/etc/tls/ca.crt

Path to TLS certificate authority file used to verify the peer certificate.

=item cert

  cert=/etc/tls/server.crt
  mojolicious.org_cert=/etc/tls/mojo.crt

Path to the TLS cert file, defaults to a built-in test certificate.

=item ciphers

  ciphers=AES128-GCM-SHA256:RC4:HIGH:!MD5:!aNULL:!EDH

TLS cipher specification string. For more information about the format see
L<https://www.openssl.org/docs/manmaster/apps/ciphers.html#CIPHER-STRINGS>.

=item key

  key=/etc/tls/server.key
  mojolicious.org_key=/etc/tls/mojo.key

Path to the TLS key file, defaults to a built-in test key.

=item reuse

  reuse=1

Allow multiple servers to use the same port with the C<SO_REUSEPORT> socket
option.

=item single_accept

  single_accept=1

Only accept one connection at a time.

=item verify

  verify=0x00

TLS verification mode, defaults to C<0x03>.

=item version

  version=TLSv1_2

TLS protocol version.

=back

=head2 max_clients

  my $max = $daemon->max_clients;
  $daemon = $daemon->max_clients(100);

Maximum number of accepted connections this server is allowed to handle
concurrently, before stopping to accept new incoming connections, passed along
to L<Mojo::IOLoop/"max_connections">.

=head2 max_requests

  my $max = $daemon->max_requests;
  $daemon = $daemon->max_requests(250);

Maximum number of keep-alive requests per connection, defaults to C<100>.

=head2 silent

  my $bool = $daemon->silent;
  $daemon  = $daemon->silent($bool);

Disable console messages.

=head1 METHODS

L<Mojo::Server::Daemon> inherits all methods from L<Mojo::Server> and
implements the following new ones.

=head2 run

  $daemon->run;

Run server and wait for L</"SIGNALS">.

=head2 start

  $daemon = $daemon->start;

Start or resume accepting connections through L</"ioloop">.

  # Listen on random port
  my $id   = $daemon->listen(['http://127.0.0.1'])->start->acceptors->[0];
  my $port = $daemon->ioloop->acceptor($id)->port;

  # Run multiple web servers concurrently
  my $daemon1 = Mojo::Server::Daemon->new(listen => ['http://*:3000'])->start;
  my $daemon2 = Mojo::Server::Daemon->new(listen => ['http://*:4000'])->start;
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 stop

  $daemon = $daemon->stop;

Stop accepting connections through L</"ioloop">.

=head1 DEBUGGING

You can set the C<MOJO_DAEMON_DEBUG> environment variable to get some advanced
diagnostics information printed to C<STDERR>.

  MOJO_DAEMON_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
