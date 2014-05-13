package Mojo::UserAgent;
use Mojo::Base 'Mojo::EventEmitter';

# "Fry: Since when is the Internet about robbing people of their privacy?
#  Bender: August 6, 1991."
use Carp 'croak';
use Mojo::IOLoop;
use Mojo::URL;
use Mojo::Util 'monkey_patch';
use Mojo::UserAgent::CookieJar;
use Mojo::UserAgent::Proxy;
use Mojo::UserAgent::Server;
use Mojo::UserAgent::Transactor;
use Scalar::Util 'weaken';

use constant DEBUG => $ENV{MOJO_USERAGENT_DEBUG} || 0;

has ca              => sub { $ENV{MOJO_CA_FILE} };
has cert            => sub { $ENV{MOJO_CERT_FILE} };
has connect_timeout => sub { $ENV{MOJO_CONNECT_TIMEOUT} || 10 };
has cookie_jar      => sub { Mojo::UserAgent::CookieJar->new };
has 'local_address';
has inactivity_timeout => sub { $ENV{MOJO_INACTIVITY_TIMEOUT} // 20 };
has ioloop             => sub { Mojo::IOLoop->new };
has key                => sub { $ENV{MOJO_KEY_FILE} };
has max_connections    => 5;
has max_redirects => sub { $ENV{MOJO_MAX_REDIRECTS} || 0 };
has proxy => sub { Mojo::UserAgent::Proxy->new };
has request_timeout => sub { $ENV{MOJO_REQUEST_TIMEOUT} // 0 };
has server => sub { Mojo::UserAgent::Server->new(ioloop => shift->ioloop) };
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

sub build_tx           { shift->transactor->tx(@_) }
sub build_websocket_tx { shift->transactor->websocket(@_) }

sub start {
  my ($self, $tx, $cb) = @_;

  # Fork safety
  $self->_cleanup->server->restart unless ($self->{pid} //= $$) eq $$;

  # Non-blocking
  if ($cb) {
    warn "-- Non-blocking request (@{[$tx->req->url->to_abs]})\n" if DEBUG;
    return $self->_start(1, $tx, $cb);
  }

  # Blocking
  warn "-- Blocking request (@{[$tx->req->url->to_abs]})\n" if DEBUG;
  $self->_start(0, $tx => sub { shift->ioloop->stop; $tx = shift });
  $self->ioloop->start;

  return $tx;
}

sub websocket {
  my $self = shift;
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
  $self->start($self->build_websocket_tx(@_), $cb);
}

sub _cleanup {
  my $self = shift;
  return unless my $loop = $self->_loop(0);

  # Clean up active connections (by closing them)
  delete $self->{pid};
  $self->_handle($_, 1) for keys %{$self->{connections} || {}};

  # Clean up keep-alive connections
  $loop->remove($_->[1]) for @{delete $self->{queue}[0] || []};
  $loop = Mojo::IOLoop->singleton;
  $loop->remove($_->[1]) for @{delete $self->{queue}[1] || []};

  return $self;
}

sub _connect {
  my ($self, $nb, $proto, $host, $port, $handle, $cb) = @_;

  weaken $self;
  my $id;
  return $id = $self->_loop($nb)->client(
    address       => $host,
    handle        => $handle,
    local_address => $self->local_address,
    port          => $port,
    timeout       => $self->connect_timeout,
    tls           => $proto eq 'https',
    tls_ca        => $self->ca,
    tls_cert      => $self->cert,
    tls_key       => $self->key,
    sub {
      my ($loop, $err, $stream) = @_;

      # Connection error
      return unless $self;
      return $self->_error($id, $err) if $err;

      # Connection established
      $stream->on(
        timeout => sub { $self->_error($id, 'Inactivity timeout', 1) });
      $stream->on(close => sub { $self->_handle($id, 1) });
      $stream->on(error => sub { $self && $self->_error($id, pop) });
      $stream->on(read => sub { $self->_read($id, pop) });
      $cb->();
    }
  );
}

sub _connect_proxy {
  my ($self, $nb, $old, $cb) = @_;

  # Start CONNECT request
  return undef unless my $new = $self->transactor->proxy_connect($old);
  return $self->_start(
    ($nb, $new) => sub {
      my ($self, $tx) = @_;

      # CONNECT failed (connection needs to be kept alive)
      unless ($tx->keep_alive && $tx->res->is_status_class(200)) {
        $old->req->error('Proxy connection failed');
        return $self->$cb($old);
      }

      # Prevent proxy reassignment and start real transaction
      $old->req->proxy(0);
      my $id = $tx->connection;
      return $self->_start($nb, $old->connection($id), $cb)
        unless $tx->req->url->protocol eq 'https';

      # TLS upgrade
      my $loop   = $self->_loop($nb);
      my $handle = $loop->stream($id)->steal_handle;
      my $c      = delete $self->{connections}{$id};
      $loop->remove($id);
      weaken $self;
      $id = $self->_connect($nb, $self->transactor->endpoint($old),
        $handle, sub { $self->_start($nb, $old->connection($id), $cb) });
      $self->{connections}{$id} = $c;
    }
  );
}

sub _connected {
  my ($self, $id) = @_;

  # Inactivity timeout
  my $c = $self->{connections}{$id};
  my $stream
    = $self->_loop($c->{nb})->stream($id)->timeout($self->inactivity_timeout);

  # Store connection information in transaction
  my $tx     = $c->{tx}->connection($id);
  my $handle = $stream->handle;
  $tx->local_address($handle->sockhost)->local_port($handle->sockport);
  $tx->remote_address($handle->peerhost)->remote_port($handle->peerport);

  # Start writing
  weaken $self;
  $tx->on(resume => sub { $self->_write($id) });
  $self->_write($id);
}

sub _connection {
  my ($self, $nb, $tx, $cb) = @_;

  # Reuse connection
  my $id = $tx->connection;
  my ($proto, $host, $port) = $self->transactor->endpoint($tx);
  $id ||= $self->_dequeue($nb, "$proto:$host:$port", 1);
  if ($id && !ref $id) {
    warn "-- Reusing connection ($proto:$host:$port)\n" if DEBUG;
    $self->{connections}{$id} = {cb => $cb, nb => $nb, tx => $tx};
    $tx->kept_alive(1) unless $tx->connection;
    $self->_connected($id);
    return $id;
  }

  # CONNECT request to proxy required
  if (my $id = $self->_connect_proxy($nb, $tx, $cb)) { return $id }

  # Connect
  warn "-- Connect ($proto:$host:$port)\n" if DEBUG;
  ($proto, $host, $port) = $self->transactor->peer($tx);
  weaken $self;
  $id = $self->_connect(
    ($nb, $proto, $host, $port, $id) => sub { $self->_connected($id) });
  $self->{connections}{$id} = {cb => $cb, nb => $nb, tx => $tx};

  return $id;
}

sub _dequeue {
  my ($self, $nb, $name, $test) = @_;

  my $found;
  my $loop = $self->_loop($nb);
  my $old  = $self->{queue}[$nb] || [];
  my $new  = $self->{queue}[$nb] = [];
  for my $queued (@$old) {
    push @$new, $queued and next if $found || !grep { $_ eq $name } @$queued;

    # Search for id/name and sort out corrupted connections if necessary
    next unless my $stream = $loop->stream($queued->[1]);
    $test && $stream->is_readable ? $stream->close : ($found = $queued->[1]);
  }

  return $found;
}

sub _enqueue {
  my ($self, $nb, $name, $id) = @_;

  # Enforce connection limit
  my $queue = $self->{queue}[$nb] ||= [];
  my $max = $self->max_connections;
  $self->_remove(shift(@$queue)->[1]) while @$queue > $max;
  push @$queue, [$name, $id] if $max;
}

sub _error {
  my ($self, $id, $err, $timeout) = @_;
  if (my $tx = $self->{connections}{$id}{tx}) { $tx->res->error($err) }
  elsif (!$timeout) { return $self->emit(error => $err) }
  $self->_handle($id, 1);
}

sub _handle {
  my ($self, $id, $close) = @_;

  # Remove request timeout
  my $c = $self->{connections}{$id};
  return unless my $loop = $self->_loop($c->{nb});
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
    $c->{cb}->($self, $new);
    $new->client_read($old->res->content->leftovers);
  }

  # Finish normal connection
  else {
    $self->_remove($id, $close);
    return unless $old;
    if (my $jar = $self->cookie_jar) { $jar->extract($old) }
    $old->client_close($close);

    # Handle redirects
    $c->{cb}->($self, $new || $old) unless $self->_redirect($c, $old);
  }
}

sub _loop { $_[1] ? Mojo::IOLoop->singleton : $_[0]->ioloop }

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
  my $c = delete $self->{connections}{$id} || {};
  my $tx = $c->{tx};
  if ($close || !$tx || !$tx->keep_alive || $tx->error) {
    $self->_dequeue($_, $id) for (1, 0);
    $self->_loop($_)->remove($id) for (1, 0);
    return;
  }

  # Keep connection alive (CONNECT requests get upgraded)
  $self->_enqueue($c->{nb}, join(':', $self->transactor->endpoint($tx)), $id)
    unless uc $tx->req->method eq 'CONNECT';
}

sub _redirect {
  my ($self, $c, $old) = @_;
  return undef unless my $new = $self->transactor->redirect($old);
  return undef unless @{$old->redirects} < $self->max_redirects;
  return $self->_start($c->{nb}, $new, delete $c->{cb});
}

sub _start {
  my ($self, $nb, $tx, $cb) = @_;

  # Application server
  my $url = $tx->req->url;
  unless ($url->is_abs) {
    my $base = $nb ? $self->server->nb_url : $self->server->url;
    $url->scheme($base->scheme)->authority($base->authority);
  }

  $self->proxy->inject($tx);
  if (my $jar = $self->cookie_jar) { $jar->inject($tx) }

  # Connect and add request timeout if necessary
  my $id = $self->emit(start => $tx)->_connection($nb, $tx, $cb);
  if (my $timeout = $self->request_timeout) {
    weaken $self;
    $self->{connections}{$id}{timeout} = $self->_loop($nb)
      ->timer($timeout => sub { $self->_error($id, 'Request timeout') });
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
  my $stream = $self->_loop($c->{nb})->stream($id)->write($chunk);
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

  # Say hello to the Unicode snowman with "Do Not Track" header
  my $ua = Mojo::UserAgent->new;
  say $ua->get('www.☃.net?hello=there' => {DNT => 1})->res->body;

  # Form POST with exception handling
  my $tx = $ua->post('https://metacpan.org/search' => form => {q => 'mojo'});
  if (my $res = $tx->success) { say $res->body }
  else {
    my ($err, $code) = $tx->error;
    say $code ? "$code response: $err" : "Connection error: $err";
  }

  # Quick JSON API request with Basic authentication
  say $ua->get('https://sri:s3cret@example.com/search.json?q=perl')
    ->res->json('/results/0/title');

  # Extract data from HTML and XML resources
  say $ua->get('www.perl.org')->res->dom->html->head->title->text;

  # Scrape the latest headlines from a news site with CSS selectors
  say $ua->get('perlnews.org')->res->dom('h2 > a')->text->shuffle;

  # IPv6 PUT request with content
  my $tx
    = $ua->put('[::1]:3000' => {'Content-Type' => 'text/plain'} => 'Hello!');

  # Follow redirects to grab the latest Mojolicious release :)
  $ua->max_redirects(5)->get('latest.mojolicio.us')
    ->res->content->asset->move_to('/Users/sri/mojo.tar.gz');

  # TLS certificate authentication and JSON POST
  my $tx = $ua->cert('tls.crt')->key('tls.key')
    ->post('https://example.com' => json => {top => 'secret'});

  # Blocking concurrent requests (does not work inside a running event loop)
  my $delay = Mojo::IOLoop->delay;
  for my $url ('mojolicio.us', 'cpan.org') {
    my $end = $delay->begin(0);
    $ua->get($url => sub {
      my ($ua, $tx) = @_;
      $end->($tx->res->dom->at('title')->text);
    });
  }
  my @titles = $delay->wait;

  # Non-blocking concurrent requests (does work inside a running event loop)
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
agent, with IPv6, TLS, SNI, IDNA, Comet (long polling), keep-alive, connection
pooling, timeout, cookie, multipart, proxy, gzip compression and multiple
event loop support.

All connections will be reset automatically if a new process has been forked,
this allows multiple processes to share the same L<Mojo::UserAgent> object
safely.

For better scalability (epoll, kqueue) and to provide IPv6 as well as TLS
support, the optional modules L<EV> (4.0+), L<IO::Socket::IP> (0.20+) and
L<IO::Socket::SSL> (1.84+) will be used automatically by L<Mojo::IOLoop> if
they are installed. Individual features can also be disabled with the
C<MOJO_NO_IPV6> and C<MOJO_NO_TLS> environment variables.

See L<Mojolicious::Guides::Cookbook/"USER AGENT"> for more.

=head1 EVENTS

L<Mojo::UserAgent> inherits all events from L<Mojo::EventEmitter> and can emit
the following new ones.

=head2 error

  $ua->on(error => sub {
    my ($ua, $err) = @_;
    ...
  });

Emitted if an error occurs that can't be associated with a transaction, fatal
if unhandled.

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
C<MOJO_CA_FILE> environment variable. Also activates hostname verification.

  # Show certificate authorities for debugging
  IO::Socket::SSL::set_defaults(
    SSL_verify_callback => sub { say "Authority: $_[2]" and return $_[0] });

=head2 cert

  my $cert = $ua->cert;
  $ua      = $ua->cert('/etc/tls/client.crt');

Path to TLS certificate file, defaults to the value of the C<MOJO_CERT_FILE>
environment variable.

=head2 connect_timeout

  my $timeout = $ua->connect_timeout;
  $ua         = $ua->connect_timeout(5);

Maximum amount of time in seconds establishing a connection may take before
getting canceled, defaults to the value of the C<MOJO_CONNECT_TIMEOUT>
environment variable or C<10>.

=head2 cookie_jar

  my $cookie_jar = $ua->cookie_jar;
  $ua            = $ua->cookie_jar(Mojo::UserAgent::CookieJar->new);

Cookie jar to use for this user agents requests, defaults to a
L<Mojo::UserAgent::CookieJar> object.

  # Disable cookie jar
  $ua->cookie_jar(0);

=head2 inactivity_timeout

  my $timeout = $ua->inactivity_timeout;
  $ua         = $ua->inactivity_timeout(15);

Maximum amount of time in seconds a connection can be inactive before getting
closed, defaults to the value of the C<MOJO_INACTIVITY_TIMEOUT> environment
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

Path to TLS key file, defaults to the value of the C<MOJO_KEY_FILE>
environment variable.

=head2 local_address

  my $address = $ua->local_address;
  $ua         = $ua->local_address('127.0.0.1');

Local address to bind to.

=head2 max_connections

  my $max = $ua->max_connections;
  $ua     = $ua->max_connections(5);

Maximum number of keep-alive connections that the user agent will retain
before it starts closing the oldest ones, defaults to C<5>.

=head2 max_redirects

  my $max = $ua->max_redirects;
  $ua     = $ua->max_redirects(3);

Maximum number of redirects the user agent will follow before it fails,
defaults to the value of the C<MOJO_MAX_REDIRECTS> environment variable or
C<0>.

=head2 proxy

  my $proxy = $ua->proxy;
  $ua       = $ua->proxy(Mojo::UserAgent::Proxy->new);

Proxy manager, defaults to a L<Mojo::UserAgent::Proxy> object.

  # Detect proxy servers from environment
  $ua->proxy->detect;

=head2 request_timeout

  my $timeout = $ua->request_timeout;
  $ua         = $ua->request_timeout(5);

Maximum amount of time in seconds establishing a connection, sending the
request and receiving a whole response may take before getting canceled,
defaults to the value of the C<MOJO_REQUEST_TIMEOUT> environment variable or
C<0>. Setting the value to C<0> will allow the user agent to wait
indefinitely. The timeout will reset for every followed redirect.

  # Total limit of 5 seconds, of which 3 seconds may be spent connecting
  $ua->max_redirects(0)->connect_timeout(3)->request_timeout(5);

=head2 server

  my $server = $ua->server;
  $ua        = $ua->server(Mojo::UserAgent::Server->new);

Application server relative URLs will be processed with, defaults to a
L<Mojo::UserAgent::Server> object.

  # Introspect
  say for @{$ua->server->app->secrets};

  # Change log level
  $ua->server->app->log->level('fatal');

  # Port currently used for processing relative URLs blocking
  say $ua->server->url->port;

  # Port currently used for processing relative URLs non-blocking
  say $ua->server->nb_url->port;

=head2 transactor

  my $t = $ua->transactor;
  $ua   = $ua->transactor(Mojo::UserAgent::Transactor->new);

Transaction builder, defaults to a L<Mojo::UserAgent::Transactor> object.

  # Change name of user agent
  $ua->transactor->name('MyUA 1.0');

=head1 METHODS

L<Mojo::UserAgent> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 build_tx

  my $tx = $ua->build_tx(GET => 'example.com');
  my $tx = $ua->build_tx(PUT => 'http://example.com' => {DNT => 1} => 'Hi!');
  my $tx = $ua->build_tx(
    PUT => 'http://example.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $ua->build_tx(
    PUT => 'http://example.com' => {DNT => 1} => json => {a => 'b'});

Generate L<Mojo::Transaction::HTTP> object with
L<Mojo::UserAgent::Transactor/"tx">.

  # Request with custom cookie
  my $tx = $ua->build_tx(GET => 'example.com');
  $tx->req->cookies({name => 'foo', value => 'bar'});
  $tx = $ua->start($tx);

  # Deactivate gzip compression
  my $tx = $ua->build_tx(GET => 'example.com');
  $tx->req->headers->remove('Accept-Encoding');
  $tx = $ua->start($tx);

  # Interrupt response by raising an error
  my $tx = $ua->build_tx(GET => 'example.com');
  $tx->res->on(progress => sub {
    my $res = shift;
    return unless my $server = $res->headers->server;
    $res->error('Oh noes, it is IIS!') if $server =~ /IIS/;
  });
  $tx = $ua->start($tx);

=head2 build_websocket_tx

  my $tx = $ua->build_websocket_tx('ws://example.com');
  my $tx = $ua->build_websocket_tx(
    'ws://example.com' => {DNT => 1} => ['v1.proto']);

Generate L<Mojo::Transaction::HTTP> object with
L<Mojo::UserAgent::Transactor/"websocket">.

=head2 delete

  my $tx = $ua->delete('example.com');
  my $tx = $ua->delete('http://example.com' => {DNT => 1} => 'Hi!');
  my $tx = $ua->delete(
    'http://example.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $ua->delete(
    'http://example.com' => {DNT => 1} => json => {a => 'b'});

Perform blocking C<DELETE> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->delete('http://example.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 get

  my $tx = $ua->get('example.com');
  my $tx = $ua->get('http://example.com' => {DNT => 1} => 'Hi!');
  my $tx = $ua->get('http://example.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $ua->get('http://example.com' => {DNT => 1} => json => {a => 'b'});

Perform blocking C<GET> request and return resulting
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

Perform blocking C<HEAD> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->head('http://example.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 options

  my $tx = $ua->options('example.com');
  my $tx = $ua->options('http://example.com' => {DNT => 1} => 'Hi!');
  my $tx = $ua->options(
    'http://example.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $ua->options(
    'http://example.com' => {DNT => 1} => json => {a => 'b'});

Perform blocking C<OPTIONS> request and return resulting
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

Perform blocking C<PATCH> request and return resulting
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

Perform blocking C<POST> request and return resulting
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

Perform blocking C<PUT> request and return resulting
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

You can activate C<permessage-deflate> compression by setting the
C<Sec-WebSocket-Extensions> header.

  my $headers = {'Sec-WebSocket-Extensions' => 'permessage-deflate'};
  $ua->websocket('ws://example.com/foo' => $headers => sub {...});

=head1 DEBUGGING

You can set the C<MOJO_USERAGENT_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_USERAGENT_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
