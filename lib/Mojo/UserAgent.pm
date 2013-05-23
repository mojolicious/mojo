package Mojo::UserAgent;
use Mojo::Base 'Mojo::EventEmitter';

# "Fry: Since when is the Internet about robbing people of their privacy?
#  Bender: August 6, 1991."
use Carp 'croak';
use List::Util 'first';
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::URL;
use Mojo::Util 'monkey_patch';
use Mojo::UserAgent::CookieJar;
use Mojo::UserAgent::Transactor;
use Scalar::Util 'weaken';

use constant DEBUG => $ENV{MOJO_USERAGENT_DEBUG} || 0;

has ca              => sub { $ENV{MOJO_CA_FILE} };
has cert            => sub { $ENV{MOJO_CERT_FILE} };
has connect_timeout => sub { $ENV{MOJO_CONNECT_TIMEOUT} || 10 };
has cookie_jar      => sub { Mojo::UserAgent::CookieJar->new };
has [qw(http_proxy https_proxy local_address no_proxy)];
has inactivity_timeout => sub { $ENV{MOJO_INACTIVITY_TIMEOUT} // 20 };
has ioloop             => sub { Mojo::IOLoop->new };
has key                => sub { $ENV{MOJO_KEY_FILE} };
has max_connections    => 5;
has max_redirects => sub { $ENV{MOJO_MAX_REDIRECTS} || 0 };
has name => 'Mojolicious (Perl)';
has request_timeout => sub { $ENV{MOJO_REQUEST_TIMEOUT} // 0 };
has transactor => sub { Mojo::UserAgent::Transactor->new };

# Common HTTP methods
for my $name (qw(DELETE GET HEAD OPTIONS PATCH POST PUT)) {
  monkey_patch __PACKAGE__, lc($name), sub {
    my $self = shift;
    my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
    return $self->start($self->build_tx($name, @_), $cb);
  };
}

sub DESTROY { shift->_cleanup }

sub app {
  my ($self, $app) = @_;

  # Singleton application
  state $singleton;
  return $singleton = $app ? $app : $singleton unless ref $self;

  # Default to singleton application
  return $self->{app} || $singleton unless $app;
  $self->{app} = $app;
  return $self;
}

sub app_url {
  my $self = shift;
  $self->_server(@_);
  return Mojo::URL->new("$self->{proto}://localhost:$self->{port}/");
}

sub build_tx           { shift->transactor->tx(@_) }
sub build_websocket_tx { shift->transactor->websocket(@_) }

sub detect_proxy {
  my $self = shift;
  $self->http_proxy($ENV{HTTP_PROXY}   || $ENV{http_proxy});
  $self->https_proxy($ENV{HTTPS_PROXY} || $ENV{https_proxy});
  return $self->no_proxy([split /,/, $ENV{NO_PROXY} || $ENV{no_proxy} || '']);
}

sub need_proxy {
  my ($self, $host) = @_;
  return !first { $host =~ /\Q$_\E$/ } @{$self->no_proxy || []};
}

sub start {
  my ($self, $tx, $cb) = @_;

  # Non-blocking
  if ($cb) {
    warn "-- Non-blocking request (@{[$tx->req->url->to_abs]})\n" if DEBUG;
    unless ($self->{nb}) {
      croak 'Blocking request in progress' if keys %{$self->{connections}};
      warn "-- Switching to non-blocking mode\n" if DEBUG;
      $self->_cleanup;
      $self->{nb}++;
    }
    return $self->_start($tx, $cb);
  }

  # Blocking
  warn "-- Blocking request (@{[$tx->req->url->to_abs]})\n" if DEBUG;
  if ($self->{nb}) {
    croak 'Non-blocking requests in progress' if keys %{$self->{connections}};
    warn "-- Switching to blocking mode\n" if DEBUG;
    $self->_cleanup;
    delete $self->{nb};
  }
  $self->_start($tx => sub { shift->ioloop->stop; $tx = shift });
  $self->ioloop->start;

  return $tx;
}

sub websocket {
  my $self = shift;
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
  $self->start($self->build_websocket_tx(@_), $cb);
}

sub _cache {
  my ($self, $name, $id) = @_;

  # Enqueue and enforce connection limit
  my $old = $self->{cache} ||= [];
  if ($id) {
    my $max = $self->max_connections;
    $self->_remove(shift(@$old)->[1]) while @$old > $max;
    push @$old, [$name, $id] if $max;
    return undef;
  }

  # Dequeue
  my $found;
  my $loop = $self->_loop;
  my $new = $self->{cache} = [];
  for my $cached (@$old) {

    # Search for id/name and remove corrupted connections
    if (!$found && ($cached->[1] eq $name || $cached->[0] eq $name)) {
      my $stream = $loop->stream($cached->[1]);
      if ($stream && !$stream->is_readable) { $found = $cached->[1] }
      else                                  { $loop->remove($cached->[1]) }
    }

    # Requeue
    else { push @$new, $cached }
  }

  return $found;
}

sub _cleanup {
  my $self = shift;
  return unless my $loop = $self->_loop;

  # Clean up active connections (by closing them)
  $self->_handle($_ => 1) for keys %{$self->{connections} || {}};

  # Clean up keep-alive connections
  $loop->remove($_->[1]) for @{delete $self->{cache} || []};

  # Stop server
  delete $self->{server};
}

sub _connect {
  my ($self, $proto, $host, $port, $handle, $cb) = @_;

  weaken $self;
  my $id;
  return $id = $self->_loop->client(
    address       => $host,
    handle        => $handle,
    local_address => $self->local_address,
    port          => $port,
    timeout       => $self->connect_timeout,
    tls           => $proto eq 'https' ? 1 : 0,
    tls_ca        => $self->ca,
    tls_cert      => $self->cert,
    tls_key       => $self->key,
    sub {
      my ($loop, $err, $stream) = @_;

      # Connection error
      return unless $self;
      return $self->_error($id, $err) if $err;

      # Connection established
      $stream->on(timeout => sub { $self->_error($id, 'Inactivity timeout') });
      $stream->on(close => sub { $self->_handle($id => 1) });
      $stream->on(error => sub { $self && $self->_error($id, pop, 1) });
      $stream->on(read => sub { $self->_read($id => pop) });
      $cb->();
    }
  );
}

sub _connect_proxy {
  my ($self, $old, $cb) = @_;

  # Start CONNECT request
  return undef unless my $new = $self->transactor->proxy_connect($old);
  return $self->_start(
    $new => sub {
      my ($self, $tx) = @_;

      # CONNECT failed
      unless (($tx->res->code // '') eq '200') {
        $old->req->error('Proxy connection failed');
        return $self->_finish($old, $cb);
      }

      # Prevent proxy reassignment and start real transaction
      $old->req->proxy(0);
      return $self->_start($old->connection($tx->connection), $cb)
        unless $tx->req->url->protocol eq 'https';

      # TLS upgrade
      return unless my $id = $tx->connection;
      my $loop   = $self->_loop;
      my $handle = $loop->stream($id)->steal_handle;
      my $c      = delete $self->{connections}{$id};
      $loop->remove($id);
      weaken $self;
      $id = $self->_connect($self->transactor->endpoint($old),
        $handle, sub { $self->_start($old->connection($id), $cb) });
      $self->{connections}{$id} = $c;
    }
  );
}

sub _connected {
  my ($self, $id) = @_;

  # Inactivity timeout
  my $stream = $self->_loop->stream($id)->timeout($self->inactivity_timeout);

  # Store connection information in transaction
  my $tx     = $self->{connections}{$id}{tx}->connection($id);
  my $handle = $stream->handle;
  $tx->local_address($handle->sockhost)->local_port($handle->sockport);
  $tx->remote_address($handle->peerhost)->remote_port($handle->peerport);

  # Start writing
  weaken $self;
  $tx->on(resume => sub { $self->_write($id) });
  $self->_write($id);
}

sub _connection {
  my ($self, $tx, $cb) = @_;

  # Reuse connection
  my $id = $tx->connection;
  my ($proto, $host, $port) = $self->transactor->endpoint($tx);
  $id ||= $self->_cache("$proto:$host:$port");
  if ($id && !ref $id) {
    warn "-- Reusing connection ($proto:$host:$port)\n" if DEBUG;
    $self->{connections}{$id} = {cb => $cb, tx => $tx};
    $tx->kept_alive(1) unless $tx->connection;
    $self->_connected($id);
    return $id;
  }

  # CONNECT request to proxy required
  if (my $id = $self->_connect_proxy($tx, $cb)) { return $id }

  # Connect
  warn "-- Connect ($proto:$host:$port)\n" if DEBUG;
  ($proto, $host, $port) = $self->transactor->peer($tx);
  weaken $self;
  $id = $self->_connect(
    ($proto, $host, $port, $id) => sub { $self->_connected($id) });
  $self->{connections}{$id} = {cb => $cb, tx => $tx};

  return $id;
}

sub _error {
  my ($self, $id, $err, $emit) = @_;
  if (my $tx = $self->{connections}{$id}{tx}) { $tx->res->error($err) }
  $self->emit(error => $err) if $emit;
  $self->_handle($id => $err);
}

sub _finish {
  my ($self, $tx, $cb, $close) = @_;

  # Remove code from parser errors
  my $res = $tx->res;
  if (my $err = $res->error) { $res->error($err) }

  else {

    # Premature connection close
    if ($close && !$res->code) { $res->error('Premature connection close') }

    # 400/500
    elsif ($res->is_status_class(400) || $res->is_status_class(500)) {
      $res->error($res->message, $res->code);
    }
  }

  $self->$cb($tx);
}

sub _handle {
  my ($self, $id, $close) = @_;

  # Remove request timeout
  return unless my $loop = $self->_loop;
  my $c = $self->{connections}{$id};
  $loop->remove($c->{timeout}) if $c->{timeout};

  # Finish WebSocket
  my $old = $c->{tx};
  if ($old && $old->is_websocket) {
    delete $self->{connections}{$id};
    $self->_remove($id, $close);
    $old->client_close;
  }

  # Upgrade connection to WebSocket
  elsif ($old && (my $new = $self->_upgrade($id))) {
    if (my $jar = $self->cookie_jar) { $jar->extract($old) }
    $old->client_close;
    $self->_finish($new, $c->{cb});
    $new->client_read($old->res->content->leftovers);
  }

  # Finish normal connection
  else {
    $self->_remove($id, $close);
    return unless $old;
    if (my $jar = $self->cookie_jar) { $jar->extract($old) }
    $old->client_close;

    # Handle redirects
    $self->_finish($new || $old, $c->{cb}, $close)
      unless $self->_redirect($c, $old);
  }
}

sub _loop { $_[0]{nb} ? Mojo::IOLoop->singleton : $_[0]->ioloop }

sub _read {
  my ($self, $id, $chunk) = @_;

  # Corrupted connection
  return                     unless my $c  = $self->{connections}{$id};
  return $self->_remove($id) unless my $tx = $c->{tx};

  # Process incoming data
  warn "-- Client <<< Server (@{[$tx->req->url->to_abs]})\n$chunk\n" if DEBUG;
  $tx->client_read($chunk);
  if    ($tx->is_finished)     { $self->_handle($id) }
  elsif ($c->{tx}->is_writing) { $self->_write($id) }
}

sub _remove {
  my ($self, $id, $close) = @_;

  # Close connection
  my $tx = (delete($self->{connections}{$id}) || {})->{tx};
  unless (!$close && $tx && $tx->keep_alive && !$tx->error) {
    $self->_cache($id);
    return $self->_loop->remove($id);
  }

  # Keep connection alive
  $self->_cache(join(':', $self->transactor->endpoint($tx)), $id)
    unless uc $tx->req->method eq 'CONNECT' && ($tx->res->code // '') eq '200';
}

sub _redirect {
  my ($self, $c, $old) = @_;

  # Follow redirect unless the maximum has been reached already
  return undef unless my $new = $self->transactor->redirect($old);
  my $redirects = delete $c->{redirects} || 0;
  return undef unless $redirects < $self->max_redirects;
  my $id = $self->_start($new, delete $c->{cb});

  return $self->{connections}{$id}{redirects} = $redirects + 1;
}

sub _server {
  my ($self, $proto) = @_;

  # Reuse server
  return $self->{server} if $self->{server} && !$proto;

  # Start application server
  my $loop   = $self->_loop;
  my $server = $self->{server}
    = Mojo::Server::Daemon->new(ioloop => $loop, silent => 1);
  my $port = $self->{port} ||= $loop->generate_port;
  die "Couldn't find a free TCP port for application.\n" unless $port;
  $self->{proto} = $proto ||= 'http';
  $server->listen(["$proto://127.0.0.1:$port"])->start;
  warn "-- Application server started ($proto://127.0.0.1:$port)\n" if DEBUG;
  return $server;
}

sub _start {
  my ($self, $tx, $cb) = @_;

  # Embedded server (update application if necessary)
  my $req = $tx->req;
  my $url = $req->url;
  if ($self->{port} || !$url->is_abs) {
    if (my $app = $self->app) { $self->_server->app($app) }
    my $base = $self->app_url;
    $url->scheme($base->scheme)->authority($base->authority)
      unless $url->is_abs;
  }

  # Proxy
  $self->detect_proxy if $ENV{MOJO_PROXY};
  my $proto = $url->protocol;
  if ($self->need_proxy($url->host)) {

    # HTTP proxy
    my $http = $self->http_proxy;
    $req->proxy($http) if $http && !defined $req->proxy && $proto eq 'http';

    # HTTPS proxy
    my $https = $self->https_proxy;
    $req->proxy($https) if $https && !defined $req->proxy && $proto eq 'https';
  }

  # We identify ourselves and accept gzip compression
  my $headers = $req->headers;
  $headers->user_agent($self->name) unless $headers->user_agent;
  $headers->accept_encoding('gzip') unless $headers->accept_encoding;
  if (my $jar = $self->cookie_jar) { $jar->inject($tx) }

  # Connect and add request timeout if necessary
  my $id = $self->emit(start => $tx)->_connection($tx, $cb);
  if (my $timeout = $self->request_timeout) {
    weaken $self;
    $self->{connections}{$id}{timeout} = $self->_loop->timer(
      $timeout => sub { $self->_error($id => 'Request timeout') });
  }

  return $id;
}

sub _upgrade {
  my ($self, $id) = @_;

  my $c = $self->{connections}{$id};
  return undef unless my $new = $self->transactor->upgrade($c->{tx});
  weaken $self;
  $new->on(resume => sub { $self->_write($id) });

  return $c->{tx} = $new;
}

sub _write {
  my ($self, $id) = @_;

  # Get and write chunk
  return unless my $c  = $self->{connections}{$id};
  return unless my $tx = $c->{tx};
  return unless $tx->is_writing;
  return if $c->{writing}++;
  my $chunk = $tx->client_write;
  delete $c->{writing};
  warn "-- Client >>> Server (@{[$tx->req->url->to_abs]})\n$chunk\n" if DEBUG;
  my $stream = $self->_loop->stream($id)->write($chunk);
  $self->_handle($id) if $tx->is_finished;

  # Continue writing
  return unless $tx->is_writing;
  weaken $self;
  $stream->write('' => sub { $self->_write($id) });
}

1;

=encoding utf8

=head1 NAME

Mojo::UserAgent - Non-blocking I/O HTTP and WebSocket user agent

=head1 SYNOPSIS

  use Mojo::UserAgent;
  my $ua = Mojo::UserAgent->new;

  # Say hello to the Unicode snowman with "Do Not Track" header
  say $ua->get('www.☃.net?hello=there' => {DNT => 1})->res->body;

  # Form POST with exception handling
  my $tx = $ua->post('https://metacpan.org/search' => form => {q => 'mojo'});
  if (my $res = $tx->success) { say $res->body }
  else {
    my ($err, $code) = $tx->error;
    say $code ? "$code response: $err" : "Connection error: $err";
  }

  # Quick JSON API request with Basic authentication
  say $ua->get('https://sri:s3cret@search.twitter.com/search.json?q=perl')
    ->res->json('/results/0/text');

  # Extract data from HTML and XML resources
  say $ua->get('mojolicio.us')->res->dom->html->head->title->text;

  # Scrape the latest headlines from a news site
  say $ua->max_redirects(5)->get('www.reddit.com/r/perl/')
    ->res->dom('p.title > a.title')->pluck('text')->shuffle;

  # IPv6 PUT request with content
  my $tx
    = $ua->put('[::1]:3000' => {'Content-Type' => 'text/plain'} => 'Hello!');

  # Grab the latest Mojolicious release :)
  $ua->max_redirects(5)->get('latest.mojolicio.us')
    ->res->content->asset->move_to('/Users/sri/mojo.tar.gz');

  # TLS certificate authentication and JSON POST
  my $tx = $ua->cert('tls.crt')->key('tls.key')
    ->post('https://mojolicio.us' => json => {top => 'secret'});

  # Blocking parallel requests (does not work inside a running event loop)
  my $delay = Mojo::IOLoop->delay;
  for my $url ('mojolicio.us', 'cpan.org') {
    my $end = $delay->begin(0);
    $ua->get($url => sub {
      my ($ua, $tx) = @_;
      $end->($tx->res->dom->at('title')->text);
    });
  }
  my @titles = $delay->wait;

  # Non-blocking parallel requests (does work inside a running event loop)
  my $delay = Mojo::IOLoop->delay(sub {
    my ($delay, @titles) = @_;
    ...
  });
  for my $url ('mojolicio.us', 'cpan.org') {
    my $end = $delay->begin(0);
    $ua->get($url => sub {
      my ($ua, $tx) = @_;
      $end->($tx->res->dom->at('title')->text);
    });
  }
  $delay->wait unless Mojo::IOLoop->is_running;

  # Non-blocking WebSocket connection sending and receiving JSON messages
  $ua->websocket('ws://example.com/echo.json' => sub {
    my ($ua, $tx) = @_;
    say 'WebSocket handshake failed!' and return unless $tx->is_websocket;
    $tx->on(json => sub {
      my ($tx, $hash) = @_;
      say "WebSocket message via JSON: $hash->{msg}";
      $tx->finish;
    });
    $tx->send({json => {msg => 'Hello World!'}});
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head1 DESCRIPTION

L<Mojo::UserAgent> is a full featured non-blocking I/O HTTP and WebSocket user
agent, with C<IPv6>, C<TLS>, C<SNI>, C<IDNA>, C<Comet> (long polling),
C<keep-alive>, connection pooling, timeout, cookie, multipart, proxy, C<gzip>
compression and multiple event loop support.

Optional modules L<EV> (4.0+), L<IO::Socket::IP> (0.16+) and
L<IO::Socket::SSL> (1.75+) are supported transparently through
L<Mojo::IOLoop>, and used if installed. Individual features can also be
disabled with the MOJO_NO_IPV6 and MOJO_NO_TLS environment variables.

See L<Mojolicious::Guides::Cookbook> for more.

=head1 EVENTS

L<Mojo::UserAgent> inherits all events from L<Mojo::EventEmitter> and can emit
the following new ones.

=head2 error

  $ua->on(error => sub {
    my ($ua, $err) = @_;
    ...
  });

Emitted if an error occurs that can't be associated with a transaction.

  $ua->on(error => sub {
    my ($ua, $err) = @_;
    say "This looks bad: $err";
  });

=head2 start

  $ua->on(start => sub {
    my ($ua, $tx) = @_;
    ...
  });

Emitted whenever a new transaction is about to start, this includes
automatically prepared proxy C<CONNECT> requests and followed redirects.

  $ua->on(start => sub {
    my ($ua, $tx) = @_;
    $tx->req->headers->header('X-Bender' => 'Bite my shiny metal ass!');
  });

=head1 ATTRIBUTES

L<Mojo::UserAgent> implements the following attributes.

=head2 ca

  my $ca = $ua->ca;
  $ua    = $ua->ca('/etc/tls/ca.crt');

Path to TLS certificate authority file, defaults to the value of the
MOJO_CA_FILE environment variable. Also activates hostname verification.

  # Show certificate authorities for debugging
  IO::Socket::SSL::set_defaults(
    SSL_verify_callback => sub { say "Authority: $_[2]" and return $_[0] });

=head2 cert

  my $cert = $ua->cert;
  $ua      = $ua->cert('/etc/tls/client.crt');

Path to TLS certificate file, defaults to the value of the MOJO_CERT_FILE
environment variable.

=head2 connect_timeout

  my $timeout = $ua->connect_timeout;
  $ua         = $ua->connect_timeout(5);

Maximum amount of time in seconds establishing a connection may take before
getting canceled, defaults to the value of the MOJO_CONNECT_TIMEOUT
environment variable or C<10>.

=head2 cookie_jar

  my $cookie_jar = $ua->cookie_jar;
  $ua            = $ua->cookie_jar(Mojo::UserAgent::CookieJar->new);

Cookie jar to use for this user agents requests, defaults to a
L<Mojo::UserAgent::CookieJar> object.

  # Disable cookie jar
  $ua->cookie_jar(0);

=head2 http_proxy

  my $proxy = $ua->http_proxy;
  $ua       = $ua->http_proxy('http://sri:secret@127.0.0.1:8080');

Proxy server to use for HTTP and WebSocket requests.

=head2 https_proxy

  my $proxy = $ua->https_proxy;
  $ua       = $ua->https_proxy('http://sri:secret@127.0.0.1:8080');

Proxy server to use for HTTPS and WebSocket requests.

=head2 inactivity_timeout

  my $timeout = $ua->inactivity_timeout;
  $ua         = $ua->inactivity_timeout(15);

Maximum amount of time in seconds a connection can be inactive before getting
closed, defaults to the value of the MOJO_INACTIVITY_TIMEOUT environment
variable or C<20>. Setting the value to C<0> will allow connections to be
inactive indefinitely.

=head2 ioloop

  my $loop = $ua->ioloop;
  $ua      = $ua->ioloop(Mojo::IOLoop->new);

Event loop object to use for blocking I/O operations, defaults to a
L<Mojo::IOLoop> object.

=head2 key

  my $key = $ua->key;
  $ua     = $ua->key('/etc/tls/client.crt');

Path to TLS key file, defaults to the value of the MOJO_KEY_FILE environment
variable.

=head2 local_address

  my $address = $ua->local_address;
  $ua         = $ua->local_address('127.0.0.1');

Local address to bind to.

=head2 max_connections

  my $max = $ua->max_connections;
  $ua     = $ua->max_connections(5);

Maximum number of keep-alive connections that the user agent will retain
before it starts closing the oldest cached ones, defaults to C<5>.

=head2 max_redirects

  my $max = $ua->max_redirects;
  $ua     = $ua->max_redirects(3);

Maximum number of redirects the user agent will follow before it fails,
defaults to the value of the MOJO_MAX_REDIRECTS environment variable or C<0>.

=head2 name

  my $name = $ua->name;
  $ua      = $ua->name('Mojolicious');

Value for C<User-Agent> request header, defaults to C<Mojolicious (Perl)>.

=head2 no_proxy

  my $no_proxy = $ua->no_proxy;
  $ua          = $ua->no_proxy([qw(localhost intranet.mojolicio.us)]);

Domains that don't require a proxy server to be used.

=head2 request_timeout

  my $timeout = $ua->request_timeout;
  $ua         = $ua->request_timeout(5);

Maximum amount of time in seconds establishing a connection, sending the
request and receiving a whole response may take before getting canceled,
defaults to the value of the MOJO_REQUEST_TIMEOUT environment variable or
C<0>. Setting the value to C<0> will allow the user agent to wait
indefinitely. The timeout will reset for every followed redirect.

  # Total limit of 5 seconds, of which 3 seconds may be spent connecting
  $ua->max_redirects(0)->connect_timeout(3)->request_timeout(5);

=head2 transactor

  my $t = $ua->transactor;
  $ua   = $ua->transactor(Mojo::UserAgent::Transactor->new);

Transaction builder, defaults to a L<Mojo::UserAgent::Transactor> object.

=head1 METHODS

L<Mojo::UserAgent> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 app

  my $app = Mojo::UserAgent->app;
            Mojo::UserAgent->app(MyApp->new);
  my $app = $ua->app;
  $ua     = $ua->app(MyApp->new);

Application relative URLs will be processed with, instance specific
applications override the global default.

  # Introspect
  say $ua->app->secret;

  # Change log level
  $ua->app->log->level('fatal');

  # Change application behavior
  $ua->app->defaults(testing => 'oh yea!');

=head2 app_url

  my $url = $ua->app_url;
  my $url = $ua->app_url('http');
  my $url = $ua->app_url('https');

Get absolute L<Mojo::URL> object for C<app> and switch protocol if necessary.

  # Port currently used for processing relative URLs
  say $ua->app_url->port;

=head2 build_tx

  my $tx = $ua->build_tx(GET => 'example.com');
  my $tx = $ua->build_tx(PUT => 'http://example.com' => {DNT => 1} => 'Hi!');
  my $tx = $ua->build_tx(
    PUT => 'http://example.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $ua->build_tx(
    PUT => 'http://example.com' => {DNT => 1} => json => {a => 'b'});

Generate L<Mojo::Transaction::HTTP> object with
L<Mojo::UserAgent::Transactor/"tx">.

  # Request with cookie
  my $tx = $ua->build_tx(GET => 'example.com');
  $tx->req->cookies({name => 'foo', value => 'bar'});
  $ua->start($tx);

=head2 build_websocket_tx

  my $tx = $ua->build_websocket_tx('ws://example.com');
  my $tx =
    $ua->build_websocket_tx('ws://example.com' => {DNT => 1} => ['v1.proto']);

Generate L<Mojo::Transaction::HTTP> object with
L<Mojo::UserAgent::Transactor/"websocket">.

=head2 delete

  my $tx = $ua->delete('example.com');
  my $tx = $ua->delete('http://example.com' => {DNT => 1} => 'Hi!');
  my $tx = $ua->delete(
    'http://example.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $ua->delete(
    'http://example.com' => {DNT => 1} => json => {a => 'b'});

Perform blocking HTTP C<DELETE> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->delete('http://example.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 detect_proxy

  $ua = $ua->detect_proxy;

Check environment variables HTTP_PROXY, http_proxy, HTTPS_PROXY, https_proxy,
NO_PROXY and no_proxy for proxy information. Automatic proxy detection can be
enabled with the MOJO_PROXY environment variable.

=head2 get

  my $tx = $ua->get('example.com');
  my $tx = $ua->get('http://example.com' => {DNT => 1} => 'Hi!');
  my $tx = $ua->get('http://example.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $ua->get('http://example.com' => {DNT => 1} => json => {a => 'b'});

Perform blocking HTTP C<GET> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->get('http://example.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 head

  my $tx = $ua->head('example.com');
  my $tx = $ua->head('http://example.com' => {DNT => 1} => 'Hi!');
  my $tx = $ua->head(
    'http://example.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $ua->head(
    'http://example.com' => {DNT => 1} => json => {a => 'b'});

Perform blocking HTTP C<HEAD> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->head('http://example.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 need_proxy

  my $success = $ua->need_proxy('intranet.example.com');

Check if request for domain would use a proxy server.

=head2 options

  my $tx = $ua->options('example.com');
  my $tx = $ua->options('http://example.com' => {DNT => 1} => 'Hi!');
  my $tx = $ua->options(
    'http://example.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $ua->options(
    'http://example.com' => {DNT => 1} => json => {a => 'b'});

Perform blocking HTTP C<OPTIONS> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->options('http://example.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 patch

  my $tx = $ua->patch('example.com');
  my $tx = $ua->patch('http://example.com' => {DNT => 1} => 'Hi!');
  my $tx = $ua->patch(
    'http://example.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $ua->patch(
    'http://example.com' => {DNT => 1} => json => {a => 'b'});

Perform blocking HTTP C<PATCH> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->patch('http://example.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 post

  my $tx = $ua->post('example.com');
  my $tx = $ua->post('http://example.com' => {DNT => 1} => 'Hi!');
  my $tx = $ua->post(
    'http://example.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $ua->post(
    'http://example.com' => {DNT => 1} => json => {a => 'b'});

Perform blocking HTTP C<POST> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->post('http://example.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 put

  my $tx = $ua->put('example.com');
  my $tx = $ua->put('http://example.com' => {DNT => 1} => 'Hi!');
  my $tx = $ua->put('http://example.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $ua->put('http://example.com' => {DNT => 1} => json => {a => 'b'});

Perform blocking HTTP C<PUT> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->put('http://example.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 start

  my $tx = $ua->start(Mojo::Transaction::HTTP->new);

Perform blocking request. You can also append a callback to perform requests
non-blocking.

  my $tx = $ua->build_tx(GET => 'http://example.com');
  $ua->start($tx => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 websocket

  $ua->websocket('ws://example.com' => sub {...});
  $ua->websocket(
    'ws://example.com' => {DNT => 1} => ['v1.proto'] => sub {...});

Open a non-blocking WebSocket connection with transparent handshake, takes the
same arguments as L<Mojo::UserAgent::Transactor/"websocket">. The callback
will receive either a L<Mojo::Transaction::WebSocket> or
L<Mojo::Transaction::HTTP> object.

  $ua->websocket('ws://example.com/echo' => sub {
    my ($ua, $tx) = @_;
    say 'WebSocket handshake failed!' and return unless $tx->is_websocket;
    $tx->on(finish => sub {
      my ($tx, $code, $reason) = @_;
      say "WebSocket closed with status $code.";
    });
    $tx->on(message => sub {
      my ($tx, $msg) = @_;
      say "WebSocket message: $msg";
      $tx->finish;
    });
    $tx->send('Hi!');
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head1 DEBUGGING

You can set the MOJO_USERAGENT_DEBUG environment variable to get some advanced
diagnostics information printed to C<STDERR>.

  MOJO_USERAGENT_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
