package Mojo::Server::Daemon;
use Mojo::Base 'Mojo::Server';

use Carp 'croak';
use Mojo::IOLoop;
use Mojo::URL;
use POSIX;
use Scalar::Util 'weaken';

use constant DEBUG => $ENV{MOJO_DAEMON_DEBUG} || 0;

has [qw(backlog group silent user)];
has inactivity_timeout => sub { $ENV{MOJO_INACTIVITY_TIMEOUT} // 15 };
has ioloop => sub { Mojo::IOLoop->singleton };
has listen => sub { [split /,/, $ENV{MOJO_LISTEN} || 'http://*:3000'] };
has max_clients  => 1000;
has max_requests => 25;

sub DESTROY {
  my $self = shift;
  return unless my $loop = $self->ioloop;
  $self->_remove($_) for keys %{$self->{connections} || {}};
  $loop->remove($_) for @{$self->{acceptors} || []};
}

sub run {
  my $self = shift;
  local $SIG{INT} = local $SIG{TERM} = sub { $self->ioloop->stop };
  $self->start->setuidgid->ioloop->start;
}

sub setuidgid {
  my $self = shift;

  # Group
  if (my $group = $self->group) {
    croak qq{Group "$group" does not exist}
      unless defined(my $gid = (getgrnam($group))[2]);
    POSIX::setgid($gid) or croak qq{Can't switch to group "$group": $!};
  }

  # User
  if (my $user = $self->user) {
    croak qq{User "$user" does not exist}
      unless defined(my $uid = (getpwnam($self->user))[2]);
    POSIX::setuid($uid) or croak qq{Can't switch to user "$user": $!};
  }

  return $self;
}

sub start {
  my $self = shift;

  # Resume accepting connections
  my $loop = $self->ioloop;
  if (my $acceptors = $self->{acceptors}) {
    push @$acceptors, $loop->acceptor(delete $self->{servers}{$_})
      for keys %{$self->{servers}};
  }

  # Start listening
  else { $self->_listen($_) for @{$self->listen} }
  $loop->max_connections($self->max_clients);

  return $self;
}

sub stop {
  my $self = shift;

  # Suspend accepting connections but keep listen sockets open
  my $loop = $self->ioloop;
  while (my $id = shift @{$self->{acceptors}}) {
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

  # Handle upgrades and requests
  weaken $self;
  $tx->on(
    upgrade => sub {
      my ($tx, $ws) = @_;
      $ws->server_handshake;
      $self->{connections}{$id}{ws} = $ws;
    }
  );
  $tx->on(
    request => sub {
      my $tx = shift;
      $self->emit(request => $self->{connections}{$id}{ws} || $tx);
      $tx->on(resume => sub { $self->_write($id) });
    }
  );

  # Kept alive if we have more than one request on the connection
  return ++$c->{requests} > 1 ? $tx->kept_alive(1) : $tx;
}

sub _close {
  my ($self, $id) = @_;

  # Finish gracefully
  if (my $tx = $self->{connections}{$id}{tx}) { $tx->server_close }

  delete $self->{connections}{$id};
}

sub _finish {
  my ($self, $id, $tx) = @_;

  # Always remove connection for WebSockets
  return $self->_remove($id) if $tx->is_websocket;

  # Finish transaction
  $tx->server_close;

  # Upgrade connection to WebSocket
  my $c = $self->{connections}{$id};
  if (my $ws = $c->{tx} = delete $c->{ws}) {

    # Successful upgrade
    if ($ws->res->code eq '101') {
      weaken $self;
      $ws->on(resume => sub { $self->_write($id) });
    }

    # Failed upgrade
    else {
      delete $c->{tx};
      $ws->server_close;
    }
  }

  # Close connection if necessary
  my $req = $tx->req;
  return $self->_remove($id) if $req->error || !$tx->keep_alive;

  # Build new transaction for leftovers
  return unless length(my $leftovers = $req->content->leftovers);
  $tx = $c->{tx} = $self->_build_tx($id, $c);
  $tx->server_read($leftovers);
}

sub _listen {
  my ($self, $listen) = @_;

  my $url     = Mojo::URL->new($listen);
  my $query   = $url->query;
  my $options = {
    address  => $url->host,
    backlog  => $self->backlog,
    port     => $url->port,
    tls_ca   => scalar $query->param('ca'),
    tls_cert => scalar $query->param('cert'),
    tls_key  => scalar $query->param('key')
  };
  my $verify = $query->param('verify');
  $options->{tls_verify} = hex $verify if defined $verify;
  delete $options->{address} if $options->{address} eq '*';
  my $tls = $options->{tls} = $url->protocol eq 'https' ? 1 : undef;

  weaken $self;
  my $id = $self->ioloop->server(
    $options => sub {
      my ($loop, $stream, $id) = @_;

      my $c = $self->{connections}{$id} = {tls => $tls};
      warn "-- Accept (@{[$stream->handle->peerhost]})\n" if DEBUG;
      $stream->timeout($self->inactivity_timeout);

      $stream->on(close => sub { $self->_close($id) });
      $stream->on(
        error => sub {
          return unless $self;
          $self->app->log->error(pop);
          $self->_close($id);
        }
      );
      $stream->on(read => sub { $self->_read($id => pop) });
      $stream->on(timeout =>
          sub { $self->app->log->debug('Inactivity timeout.') if $c->{tx} });
    }
  );
  push @{$self->{acceptors} ||= []}, $id;

  return if $self->silent;
  $self->app->log->info(qq{Listening at "$listen".});
  $listen =~ s!//\*!//127.0.0.1!i;
  say "Server available at $listen.";
}

sub _read {
  my ($self, $id, $chunk) = @_;

  # Make sure we have a transaction and parse chunk
  return unless my $c = $self->{connections}{$id};
  my $tx = $c->{tx} ||= $self->_build_tx($id, $c);
  warn "-- Server <<< Client (@{[$tx->req->url->to_abs]})\n$chunk\n" if DEBUG;
  $tx->server_read($chunk);

  # Last keep-alive request or corrupted connection
  $tx->res->headers->connection('close')
    if (($c->{requests} || 0) >= $self->max_requests) || $tx->req->error;

  # Finish or start writing
  if ($tx->is_finished) { $self->_finish($id, $tx) }
  elsif ($tx->is_writing) { $self->_write($id) }
}

sub _remove {
  my ($self, $id) = @_;
  $self->ioloop->remove($id);
  $self->_close($id);
}

sub _write {
  my ($self, $id) = @_;

  # Not writing
  return unless my $c  = $self->{connections}{$id};
  return unless my $tx = $c->{tx};
  return unless $tx->is_writing;

  # Get chunk and write
  return if $c->{writing}++;
  my $chunk = $tx->server_write;
  delete $c->{writing};
  warn "-- Server >>> Client (@{[$tx->req->url->to_abs]})\n$chunk\n" if DEBUG;
  my $stream = $self->ioloop->stream($id)->write($chunk);

  # Finish or continue writing
  weaken $self;
  my $cb = sub { $self->_write($id) };
  if ($tx->is_finished) {
    if ($tx->has_subscribers('finish')) {
      $cb = sub { $self->_finish($id, $tx) }
    }
    else {
      $self->_finish($id, $tx);
      return unless $c->{tx};
    }
  }
  $stream->write('' => $cb);
}

1;

=head1 NAME

Mojo::Server::Daemon - Non-blocking I/O HTTP and WebSocket server

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

L<Mojo::Server::Daemon> is a full featured, highly portable non-blocking I/O
HTTP and WebSocket server, with C<IPv6>, C<TLS>, C<Comet> (long polling),
C<keep-alive>, connection pooling, timeout, cookie, multipart and multiple
event loop support.

Optional modules L<EV> (4.0+), L<IO::Socket::IP> (0.16+) and
L<IO::Socket::SSL> (1.75+) are supported transparently through
L<Mojo::IOLoop>, and used if installed. Individual features can also be
disabled with the MOJO_NO_IPV6 and MOJO_NO_TLS environment variables.

See L<Mojolicious::Guides::Cookbook> for more.

=head1 EVENTS

L<Mojo::Server::Daemon> inherits all events from L<Mojo::Server>.

=head1 ATTRIBUTES

L<Mojo::Server::Daemon> inherits all attributes from L<Mojo::Server> and
implements the following new ones.

=head2 backlog

  my $backlog = $daemon->backlog;
  $daemon     = $daemon->backlog(128);

Listen backlog size, defaults to C<SOMAXCONN>.

=head2 group

  my $group = $daemon->group;
  $daemon   = $daemon->group('users');

Group for server process.

=head2 inactivity_timeout

  my $timeout = $daemon->inactivity_timeout;
  $daemon     = $daemon->inactivity_timeout(5);

Maximum amount of time in seconds a connection can be inactive before getting
closed, defaults to the value of the MOJO_INACTIVITY_TIMEOUT environment
variable or C<15>. Setting the value to C<0> will allow connections to be
inactive indefinitely.

=head2 ioloop

  my $loop = $daemon->ioloop;
  $daemon  = $daemon->ioloop(Mojo::IOLoop->new);

Event loop object to use for I/O operations, defaults to the global
L<Mojo::IOLoop> singleton.

=head2 listen

  my $listen = $daemon->listen;
  $daemon    = $daemon->listen(['https://localhost:3000']);

List of one or more locations to listen on, defaults to the value of the
MOJO_LISTEN environment variable or C<http://*:3000>.

  # Listen on IPv6 interface
  $daemon->listen(['http://[::1]:4000']);

  # Listen on two ports with HTTP and HTTPS at the same time
  $daemon->listen([qw(http://*:3000 https://*:4000)]);

  # Use a custom certificate and key
  $daemon->listen(['https://*:3000?cert=/x/server.crt&key=/y/server.key']);

  # Or even a custom certificate authority
  $daemon->listen(
    ['https://*:3000?cert=/x/server.crt&key=/y/server.key&ca=/z/ca.crt']);

These parameters are currently available:

=over 4

=item ca

Path to TLS certificate authority file.

=item cert

Path to the TLS cert file, defaults to a built-in test certificate.

=item key

Path to the TLS key file, defaults to a built-in test key.

=item verify

TLS verification mode, defaults to C<0x03>.

=back

=head2 max_clients

  my $max = $daemon->max_clients;
  $daemon = $daemon->max_clients(1000);

Maximum number of parallel client connections, defaults to C<1000>.

=head2 max_requests

  my $max = $daemon->max_requests;
  $daemon = $daemon->max_requests(100);

Maximum number of keep-alive requests per connection, defaults to C<25>.

=head2 silent

  my $silent = $daemon->silent;
  $daemon    = $daemon->silent(1);

Disable console messages.

=head2 user

  my $user = $daemon->user;
  $daemon  = $daemon->user('web');

User for the server process.

=head1 METHODS

L<Mojo::Server::Daemon> inherits all methods from L<Mojo::Server> and
implements the following new ones.

=head2 run

  $daemon->run;

Run server.

=head2 setuidgid

  $daemon = $daemon->setuidgid;

Set user and group for process.

=head2 start

  $daemon = $daemon->start;

Start accepting connections.

=head2 stop

  $daemon = $daemon->stop;

Stop accepting connections.

=head1 DEBUGGING

You can set the MOJO_DAEMON_DEBUG environment variable to get some advanced
diagnostics information printed to C<STDERR>.

  MOJO_DAEMON_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
