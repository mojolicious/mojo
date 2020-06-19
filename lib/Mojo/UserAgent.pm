package Mojo::UserAgent;
use Mojo::Base 'Mojo::EventEmitter';

# "Fry: Since when is the Internet about robbing people of their privacy?
#  Bender: August 6, 1991."
use Mojo::IOLoop;
use Mojo::Promise;
use Mojo::Util qw(monkey_patch term_escape);
use Mojo::UserAgent::CookieJar;
use Mojo::UserAgent::Proxy;
use Mojo::UserAgent::Server;
use Mojo::UserAgent::Transactor;
use Scalar::Util qw(weaken);

use constant DEBUG => $ENV{MOJO_CLIENT_DEBUG} || 0;

has ca                 => sub { $ENV{MOJO_CA_FILE} };
has cert               => sub { $ENV{MOJO_CERT_FILE} };
has connect_timeout    => sub { $ENV{MOJO_CONNECT_TIMEOUT} || 10 };
has cookie_jar         => sub { Mojo::UserAgent::CookieJar->new };
has inactivity_timeout => sub { $ENV{MOJO_INACTIVITY_TIMEOUT} // 40 };
has insecure           => sub { $ENV{MOJO_INSECURE} };
has [qw(local_address max_response_size)];
has ioloop          => sub { Mojo::IOLoop->new };
has key             => sub { $ENV{MOJO_KEY_FILE} };
has max_connections => 5;
has max_redirects   => sub { $ENV{MOJO_MAX_REDIRECTS} || 0 };
has proxy           => sub { Mojo::UserAgent::Proxy->new };
has request_timeout => sub { $ENV{MOJO_REQUEST_TIMEOUT} // 0 };
has server          => sub { Mojo::UserAgent::Server->new(ioloop => shift->ioloop) };
has transactor      => sub { Mojo::UserAgent::Transactor->new };

# Common HTTP methods
for my $name (qw(DELETE GET HEAD OPTIONS PATCH POST PUT)) {
  monkey_patch __PACKAGE__, lc $name, sub {
    my ($self, $cb) = (shift, ref $_[-1] eq 'CODE' ? pop : undef);
    return $self->start($self->build_tx($name, @_), $cb);
  };
  monkey_patch __PACKAGE__, lc($name) . '_p', sub {
    my $self = shift;
    return $self->start_p($self->build_tx($name, @_));
  };
}

sub DESTROY { Mojo::Util::_global_destruction() or shift->_cleanup }

sub build_tx           { shift->transactor->tx(@_) }
sub build_websocket_tx { shift->transactor->websocket(@_) }

sub start {
  my ($self, $tx, $cb) = @_;

  # Fork-safety
  $self->_cleanup->server->restart unless ($self->{pid} //= $$) eq $$;

  # Non-blocking
  if ($cb) {
    warn "-- Non-blocking request (@{[_url($tx)]})\n" if DEBUG;
    return $self->_start(Mojo::IOLoop->singleton, $tx, $cb);
  }

  # Blocking
  warn "-- Blocking request (@{[_url($tx)]})\n" if DEBUG;
  $self->_start($self->ioloop, $tx => sub { shift->ioloop->stop; $tx = shift });
  $self->ioloop->start;

  return $tx;
}

sub start_p {
  my ($self, $tx) = @_;
  my $promise = Mojo::Promise->new;
  $self->start($tx => sub { shift->transactor->promisify($promise, shift) });
  return $promise;
}

sub websocket {
  my ($self, $cb) = (shift, pop);
  $self->start($self->build_websocket_tx(@_), $cb);
}

sub websocket_p {
  my $self = shift;
  return $self->start_p($self->build_websocket_tx(@_));
}

sub _cleanup {
  my $self = shift;
  delete $self->{pid};
  $self->_finish($_, 1) for keys %{$self->{connections} || {}};
  return $self;
}

sub _connect {
  my ($self, $loop, $tx, $handle) = @_;

  my $t = $self->transactor;
  my ($proto, $host, $port) = $handle ? $t->endpoint($tx) : $t->peer($tx);

  my %options = (timeout => $self->connect_timeout);
  if   ($proto eq 'http+unix') { $options{path}             = $host }
  else                         { @options{qw(address port)} = ($host, $port) }
  if (my $local = $self->local_address) { $options{local_address} = $local }
  $options{handle} = $handle if $handle;

  # SOCKS
  if ($proto eq 'socks') {
    @options{qw(socks_address socks_port)} = @options{qw(address port)};
    ($proto, @options{qw(address port)}) = $t->endpoint($tx);
    my $userinfo = $tx->req->via_proxy(0)->proxy->userinfo;
    @options{qw(socks_user socks_pass)} = split ':', $userinfo if $userinfo;
  }

  # TLS
  if ($options{tls} = $proto eq 'https') {
    map { $options{"tls_$_"} = $self->$_ } qw(ca cert key);
    $options{tls_verify} = 0x00 if $self->insecure;
  }

  weaken $self;
  my $id;
  return $id = $loop->client(
    %options => sub {
      my ($loop, $err, $stream) = @_;

      # Connection error
      return unless $self;
      return $self->_error($id, $err) if $err;

      # Connection established
      $stream->on(timeout => sub { $self->_error($id, 'Inactivity timeout') });
      $stream->on(close => sub { $self && $self->_finish($id, 1) });
      $stream->on(error => sub { $self && $self->_error($id, pop) });
      $stream->on(read => sub { $self->_read($id, pop) });
      $self->_process($id);
    }
  );
}

sub _connect_proxy {
  my ($self, $loop, $old, $cb) = @_;

  # Start CONNECT request
  return undef unless my $new = $self->transactor->proxy_connect($old);
  my $id;
  return $id = $self->_start(
    ($loop, $new) => sub {
      my ($self, $tx) = @_;

      # Real transaction
      $old->previous($tx)->req->via_proxy(0);
      my $c = $self->{connections}{$id} = {cb => $cb, ioloop => $loop, tx => $old};

      # CONNECT failed
      return $self->_error($id, 'Proxy connection failed') if $tx->error || !$tx->res->is_success || !$tx->keep_alive;

      # Start real transaction without TLS upgrade
      return $self->_process($id) unless $tx->req->url->protocol eq 'https';

      # TLS upgrade before starting the real transaction
      my $handle = $loop->stream($id)->steal_handle;
      $self->_remove($id);
      $id = $self->_connect($loop, $old, $handle);
      $self->{connections}{$id} = $c;
    }
  );
}

sub _connection {
  my ($self, $loop, $tx, $cb) = @_;

  # Reuse connection
  my ($proto, $host, $port) = $self->transactor->endpoint($tx);
  my $id;
  if ($id = $self->_dequeue($loop, "$proto:$host:$port", 1)) {
    warn "-- Reusing connection $id ($proto://$host:$port)\n" if DEBUG;
    @{$self->{connections}{$id}}{qw(cb tx)} = ($cb, $tx);
    $tx->kept_alive(1) unless $tx->connection;
    $self->_process($id);
    return $id;
  }

  # CONNECT request to proxy required
  if (my $id = $self->_connect_proxy($loop, $tx, $cb)) { return $id }

  # New connection
  $tx->res->error({message => "Unsupported protocol: $proto"}) and return $loop->next_tick(sub { $self->$cb($tx) })
    unless $proto eq 'http' || $proto eq 'https' || $proto eq 'http+unix';
  $id = $self->_connect($loop, $tx);
  warn "-- Connect $id ($proto://$host:$port)\n" if DEBUG;
  $self->{connections}{$id} = {cb => $cb, ioloop => $loop, tx => $tx};

  return $id;
}

sub _dequeue {
  my ($self, $loop, $name, $test) = @_;

  my $old = $self->{queue}{$loop} ||= [];
  my ($found, @new);
  for my $queued (@$old) {
    push @new, $queued and next if $found || !grep { $_ eq $name } @$queued;

    # Search for id/name and sort out corrupted connections if necessary
    next unless my $stream = $loop->stream($queued->[1]);
    $test && $stream->is_readable ? $stream->close : ($found = $queued->[1]);
  }
  @$old = @new;

  return $found;
}

sub _error {
  my ($self, $id, $err) = @_;
  my $tx = $self->{connections}{$id}{tx};
  $tx->res->error({message => $err}) if $tx;
  $self->_finish($id, 1);
}

sub _finish {
  my ($self, $id, $close) = @_;

  # Remove request timeout and finish transaction
  return undef unless my $c = $self->{connections}{$id};
  $c->{ioloop}->remove(delete $c->{timeout}) if $c->{timeout};
  return $self->_reuse($id, $close) unless my $old = $c->{tx};

  # Premature connection close
  my $res = $old->closed->res->finish;
  $res->error({message => 'Premature connection close'}) if $close && !$res->code && !$res->error;

  # Always remove connection for WebSockets
  return $self->_remove($id) if $old->is_websocket;
  $self->cookie_jar->collect($old);

  # Upgrade connection to WebSocket
  if (my $new = $self->transactor->upgrade($old)) {
    weaken $self;
    $new->on(resume => sub { $self->_write($id) });
    $c->{cb}($self, $c->{tx} = $new);
    return $new->client_read($old->res->content->leftovers);
  }

  # CONNECT requests always have a follow-up request
  $self->_reuse($id, $close) unless uc $old->req->method eq 'CONNECT';
  $res->error({message => $res->message, code => $res->code}) if $res->is_error;
  $c->{cb}($self, $old) unless $self->_redirect($c, $old);
}

sub _process {
  my ($self, $id) = @_;

  my $c      = $self->{connections}{$id};
  my $stream = $c->{ioloop}->stream($id)->timeout($self->inactivity_timeout);
  my $tx     = $c->{tx}->connection($id);
  my $handle = $stream->handle;
  unless ($handle->isa('IO::Socket::UNIX')) {
    $tx->local_address($handle->sockhost)->local_port($handle->sockport);
    $tx->remote_address($handle->peerhost)->remote_port($handle->peerport);
  }

  weaken $self;
  $tx->on(resume => sub { $self->_write($id) });
  $self->_write($id);
}

sub _read {
  my ($self, $id, $chunk) = @_;

  # Corrupted connection
  return $self->_remove($id) unless my $tx = $self->{connections}{$id}{tx};
  warn term_escape "-- Client <<< Server (@{[_url($tx)]})\n$chunk\n" if DEBUG;
  $tx->client_read($chunk);
  $self->_finish($id) if $tx->is_finished;
}

sub _redirect {
  my ($self, $c, $old) = @_;
  return undef unless my $new = $self->transactor->redirect($old);
  return undef unless @{$old->redirects} < $self->max_redirects;
  return $self->_start($c->{ioloop}, $new, delete $c->{cb});
}

sub _remove {
  my ($self, $id) = @_;
  my $c = delete $self->{connections}{$id};
  $self->_dequeue($c->{ioloop}, $id);
  $c->{ioloop}->remove($id);
}

sub _reuse {
  my ($self, $id, $close) = @_;

  # Connection close
  my $c   = $self->{connections}{$id};
  my $tx  = delete $c->{tx};
  my $max = $self->max_connections;
  return $self->_remove($id) if $close || !$tx || !$max || !$tx->keep_alive || $tx->error;

  # Keep connection alive
  my $queue = $self->{queue}{$c->{ioloop}} ||= [];
  $self->_remove(shift(@$queue)->[1]) while @$queue && @$queue >= $max;
  push @$queue, [join(':', $self->transactor->endpoint($tx)), $id];
}

sub _start {
  my ($self, $loop, $tx, $cb) = @_;

  # Application server
  $self->emit(prepare => $tx);
  my $url = $tx->req->url;
  if (!$url->is_abs && (my $server = $self->server)) {
    my $base = $loop == $self->ioloop ? $server->url : $server->nb_url;
    $url->scheme($base->scheme)->host($base->host)->port($base->port);
  }

  $_->prepare($tx) for $self->proxy, $self->cookie_jar;
  my $max = $self->max_response_size;
  $tx->res->max_message_size($max) if defined $max;
  $self->emit(start => $tx);

  # Allow test servers sharing the same event loop to clean up connections
  !$loop->next_tick(sub { }) and $loop->one_tick unless $loop->is_running;
  return undef unless my $id = $self->_connection($loop, $tx, $cb);

  if (my $t = $self->request_timeout) {
    weaken $self;
    $self->{connections}{$id}{timeout} ||= $loop->timer($t => sub { $self->_error($id, 'Request timeout') });
  }

  return $id;
}

sub _url { shift->req->url->to_abs }

sub _write {
  my ($self, $id) = @_;

  # Protect from resume event recursion
  my $c = $self->{connections}{$id};
  return if !(my $tx = $c->{tx}) || $c->{writing};
  local $c->{writing} = 1;
  my $chunk = $tx->client_write;
  warn term_escape "-- Client >>> Server (@{[_url($tx)]})\n$chunk\n" if DEBUG;
  return unless length $chunk;

  weaken $self;
  $c->{ioloop}->stream($id)->write($chunk => sub { $self->_write($id) });
}

1;

=encoding utf8

=head1 NAME

Mojo::UserAgent - Non-blocking I/O HTTP and WebSocket user agent

=head1 SYNOPSIS

  use Mojo::UserAgent;

  # Fine grained response handling (dies on connection errors)
  my $ua  = Mojo::UserAgent->new;
  my $res = $ua->get('mojolicious.org/perldoc')->result;
  if    ($res->is_success)  { say $res->body }
  elsif ($res->is_error)    { say $res->message }
  elsif ($res->code == 301) { say $res->headers->location }
  else                      { say 'Whatever...' }

  # Say hello to the Unicode snowman and include an Accept header
  say $ua->get('www.☃.net?hello=there' => {Accept => '*/*'})->result->body;

  # Extract data from HTML and XML resources with CSS selectors
  say $ua->get('www.perl.org')->result->dom->at('title')->text;

  # Scrape the latest headlines from a news site
  say $ua->get('blogs.perl.org')->result->dom->find('h2 > a')->map('text')->join("\n");

  # IPv6 PUT request with Content-Type header and content
  my $tx = $ua->put('[::1]:3000' => {'Content-Type' => 'text/plain'} => 'Hi!');

  # Quick JSON API request with Basic authentication
  my $url = Mojo::URL->new('https://example.com/test.json')->userinfo('sri:☃');
  my $value = $ua->get($url)->result->json;

  # JSON POST (application/json) with TLS certificate authentication
  my $tx = $ua->cert('tls.crt')->key('tls.key')->post('https://example.com' => json => {top => 'secret'});

  # Form POST (application/x-www-form-urlencoded)
  my $tx = $ua->post('https://metacpan.org/search' => form => {q => 'mojo'});

  # Search DuckDuckGo anonymously through Tor
  $ua->proxy->http('socks://127.0.0.1:9050');
  say $ua->get('api.3g2upl4pq6kufc4m.onion/?q=mojolicious&format=json')->result->json('/Abstract');

  # GET request via UNIX domain socket "/tmp/myapp.sock" (percent encoded slash)
  say $ua->get('http+unix://%2Ftmp%2Fmyapp.sock/perldoc')->result->body;

  # Follow redirects to download Mojolicious from GitHub
  $ua->max_redirects(5)
    ->get('https://www.github.com/mojolicious/mojo/tarball/master')
    ->result->save_to('/home/sri/mojo.tar.gz');

  # Non-blocking request
  $ua->get('mojolicious.org' => sub {
    my ($ua, $tx) = @_;
    say $tx->result->dom->at('title')->text;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

  # Concurrent non-blocking requests (synchronized with promises)
  my $mojo = $ua->get_p('mojolicious.org');
  my $cpan = $ua->get_p('cpan.org');
  Mojo::Promise->all($mojo, $cpan)->then(sub {
    my ($mojo, $cpan) = @_;
    say $mojo->[0]->result->dom->at('title')->text;
    say $cpan->[0]->result->dom->at('title')->text;
  })->wait;

  # WebSocket connection sending and receiving JSON via UNIX domain socket
  $ua->websocket('ws+unix://%2Ftmp%2Fmyapp.sock/echo.json' => sub {
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

L<Mojo::UserAgent> is a full featured non-blocking I/O HTTP and WebSocket user agent, with IPv6, TLS, SNI, IDNA,
HTTP/SOCKS5 proxy, UNIX domain socket, Comet (long polling), Promises/A+, keep-alive, connection pooling, timeout,
cookie, multipart, gzip compression and multiple event loop support.

All connections will be reset automatically if a new process has been forked, this allows multiple processes to share
the same L<Mojo::UserAgent> object safely.

For better scalability (epoll, kqueue) and to provide non-blocking name resolution, SOCKS5 as well as TLS support, the
optional modules L<EV> (4.32+), L<Net::DNS::Native> (0.15+), L<IO::Socket::Socks> (0.64+) and L<IO::Socket::SSL>
(2.009+) will be used automatically if possible. Individual features can also be disabled with the C<MOJO_NO_NNR>,
C<MOJO_NO_SOCKS> and C<MOJO_NO_TLS> environment variables.

See L<Mojolicious::Guides::Cookbook/"USER AGENT"> for more.

=head1 EVENTS

L<Mojo::UserAgent> inherits all events from L<Mojo::EventEmitter> and can emit the following new ones.

=head2 prepare

  $ua->on(prepare => sub {
    my ($ua, $tx) = @_;
    ...
  });

Emitted whenever a new transaction is being prepared, before relative URLs are rewritten and cookies added. This
includes automatically prepared proxy C<CONNECT> requests and followed redirects.

  $ua->on(prepare => sub {
    my ($ua, $tx) = @_;
    $tx->req->url(Mojo::URL->new('/mock-mojolicious')) if $tx->req->url->host eq 'mojolicious.org';
  });

=head2 start

  $ua->on(start => sub {
    my ($ua, $tx) = @_;
    ...
  });

Emitted whenever a new transaction is about to start. This includes automatically prepared proxy C<CONNECT> requests
and followed redirects.

  $ua->on(start => sub {
    my ($ua, $tx) = @_;
    $tx->req->headers->header('X-Bender' => 'Bite my shiny metal ass!');
  });

=head1 ATTRIBUTES

L<Mojo::UserAgent> implements the following attributes.

=head2 ca

  my $ca = $ua->ca;
  $ua    = $ua->ca('/etc/tls/ca.crt');

Path to TLS certificate authority file used to verify the peer certificate, defaults to the value of the
C<MOJO_CA_FILE> environment variable.

  # Show certificate authorities for debugging
  IO::Socket::SSL::set_defaults(SSL_verify_callback => sub { say "Authority: $_[2]" and return $_[0] });

=head2 cert

  my $cert = $ua->cert;
  $ua      = $ua->cert('/etc/tls/client.crt');

Path to TLS certificate file, defaults to the value of the C<MOJO_CERT_FILE> environment variable.

=head2 connect_timeout

  my $timeout = $ua->connect_timeout;
  $ua         = $ua->connect_timeout(5);

Maximum amount of time in seconds establishing a connection may take before getting canceled, defaults to the value of
the C<MOJO_CONNECT_TIMEOUT> environment variable or C<10>.

=head2 cookie_jar

  my $cookie_jar = $ua->cookie_jar;
  $ua            = $ua->cookie_jar(Mojo::UserAgent::CookieJar->new);

Cookie jar to use for requests performed by this user agent, defaults to a L<Mojo::UserAgent::CookieJar> object.

  # Ignore all cookies
  $ua->cookie_jar->ignore(sub { 1 });

  # Ignore cookies for public suffixes
  my $ps = IO::Socket::SSL::PublicSuffix->default;
  $ua->cookie_jar->ignore(sub {
    my $cookie = shift;
    return undef unless my $domain = $cookie->domain;
    return ($ps->public_suffix($domain))[0] eq '';
  });

  # Add custom cookie to the jar
  $ua->cookie_jar->add(
    Mojo::Cookie::Response->new(
      name   => 'foo',
      value  => 'bar',
      domain => 'mojolicious.org',
      path   => '/perldoc'
    )
  );

=head2 inactivity_timeout

  my $timeout = $ua->inactivity_timeout;
  $ua         = $ua->inactivity_timeout(15);

Maximum amount of time in seconds a connection can be inactive before getting closed, defaults to the value of the
C<MOJO_INACTIVITY_TIMEOUT> environment variable or C<40>. Setting the value to C<0> will allow connections to be
inactive indefinitely.

=head2 insecure

  my $bool = $ua->insecure;
  $ua      = $ua->insecure($bool);

Do not require a valid TLS certificate to access HTTPS/WSS sites, defaults to the value of the C<MOJO_INSECURE>
environment variable.

  # Disable TLS certificate verification for testing
  say $ua->insecure(1)->get('https://127.0.0.1:3000')->result->code;

=head2 ioloop

  my $loop = $ua->ioloop;
  $ua      = $ua->ioloop(Mojo::IOLoop->new);

Event loop object to use for blocking I/O operations, defaults to a L<Mojo::IOLoop> object.

=head2 key

  my $key = $ua->key;
  $ua     = $ua->key('/etc/tls/client.crt');

Path to TLS key file, defaults to the value of the C<MOJO_KEY_FILE> environment variable.

=head2 local_address

  my $address = $ua->local_address;
  $ua         = $ua->local_address('127.0.0.1');

Local address to bind to.

=head2 max_connections

  my $max = $ua->max_connections;
  $ua     = $ua->max_connections(5);

Maximum number of keep-alive connections that the user agent will retain before it starts closing the oldest ones,
defaults to C<5>. Setting the value to C<0> will prevent any connections from being kept alive.

=head2 max_redirects

  my $max = $ua->max_redirects;
  $ua     = $ua->max_redirects(3);

Maximum number of redirects the user agent will follow before it fails, defaults to the value of the
C<MOJO_MAX_REDIRECTS> environment variable or C<0>.

=head2 max_response_size

  my $max = $ua->max_response_size;
  $ua     = $ua->max_response_size(16777216);

Maximum response size in bytes, defaults to the value of L<Mojo::Message::Response/"max_message_size">. Setting the
value to C<0> will allow responses of indefinite size. Note that increasing this value can also drastically increase
memory usage, should you for example attempt to parse an excessively large response body with the methods
L<Mojo::Message/"dom"> or L<Mojo::Message/"json">.

=head2 proxy

  my $proxy = $ua->proxy;
  $ua       = $ua->proxy(Mojo::UserAgent::Proxy->new);

Proxy manager, defaults to a L<Mojo::UserAgent::Proxy> object.

  # Detect proxy servers from environment
  $ua->proxy->detect;

  # Manually configure HTTP proxy (using CONNECT for HTTPS/WebSockets)
  $ua->proxy->http('http://127.0.0.1:8080')->https('http://127.0.0.1:8080');

  # Manually configure Tor (SOCKS5)
  $ua->proxy->http('socks://127.0.0.1:9050')->https('socks://127.0.0.1:9050');

  # Manually configure UNIX domain socket (using CONNECT for HTTPS/WebSockets)
  $ua->proxy->http('http+unix://%2Ftmp%2Fproxy.sock') ->https('http+unix://%2Ftmp%2Fproxy.sock');

=head2 request_timeout

  my $timeout = $ua->request_timeout;
  $ua         = $ua->request_timeout(5);

Maximum amount of time in seconds establishing a connection, sending the request and receiving a whole response may
take before getting canceled, defaults to the value of the C<MOJO_REQUEST_TIMEOUT> environment variable or C<0>.
Setting the value to C<0> will allow the user agent to wait indefinitely. The timeout will reset for every followed
redirect.

  # Total limit of 5 seconds, of which 3 seconds may be spent connecting
  $ua->max_redirects(0)->connect_timeout(3)->request_timeout(5);

=head2 server

  my $server = $ua->server;
  $ua        = $ua->server(Mojo::UserAgent::Server->new);

Application server relative URLs will be processed with, defaults to a L<Mojo::UserAgent::Server> object.

  # Mock web service
  $ua->server->app(Mojolicious->new);
  $ua->server->app->routes->get('/time' => sub {
    my $c = shift;
    $c->render(json => {now => time});
  });
  my $time = $ua->get('/time')->result->json->{now};

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

  # Disable compression
  $ua->transactor->compressed(0);

=head1 METHODS

L<Mojo::UserAgent> inherits all methods from L<Mojo::EventEmitter> and implements the following new ones.

=head2 build_tx

  my $tx = $ua->build_tx(GET => 'example.com');
  my $tx = $ua->build_tx(PUT => 'http://example.com' => {Accept => '*/*'} => 'Content!');
  my $tx = $ua->build_tx(PUT => 'http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $tx = $ua->build_tx(PUT => 'http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Generate L<Mojo::Transaction::HTTP> object with L<Mojo::UserAgent::Transactor/"tx">.

  # Request with custom cookie
  my $tx = $ua->build_tx(GET => 'https://example.com/account');
  $tx->req->cookies({name => 'user', value => 'sri'});
  $tx = $ua->start($tx);

  # Deactivate gzip compression
  my $tx = $ua->build_tx(GET => 'example.com');
  $tx->req->headers->remove('Accept-Encoding');
  $tx = $ua->start($tx);

  # Interrupt response by raising an error
  my $tx = $ua->build_tx(GET => 'http://example.com');
  $tx->res->on(progress => sub {
    my $res = shift;
    return unless my $server = $res->headers->server;
    $res->error({message => 'Oh noes, it is IIS!'}) if $server =~ /IIS/;
  });
  $tx = $ua->start($tx);

=head2 build_websocket_tx

  my $tx = $ua->build_websocket_tx('ws://example.com');
  my $tx = $ua->build_websocket_tx( 'ws://example.com' => {DNT => 1} => ['v1.proto']);

Generate L<Mojo::Transaction::HTTP> object with L<Mojo::UserAgent::Transactor/"websocket">.

  # Custom WebSocket handshake with cookie
  my $tx = $ua->build_websocket_tx('wss://example.com/echo');
  $tx->req->cookies({name => 'user', value => 'sri'});
  $ua->start($tx => sub {
    my ($ua, $tx) = @_;
    say 'WebSocket handshake failed!' and return unless $tx->is_websocket;
    $tx->on(message => sub {
      my ($tx, $msg) = @_;
      say "WebSocket message: $msg";
      $tx->finish;
    });
    $tx->send('Hi!');
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 delete

  my $tx = $ua->delete('example.com');
  my $tx = $ua->delete('http://example.com' => {Accept => '*/*'} => 'Content!');
  my $tx = $ua->delete('http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $tx = $ua->delete('http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform blocking C<DELETE> request and return resulting L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the C<DELETE> method, which is implied). You can also append a callback
to perform requests non-blocking.

  $ua->delete('http://example.com' => json => {a => 'b'} => sub {
    my ($ua, $tx) = @_;
    say $tx->result->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 delete_p

  my $promise = $ua->delete_p('http://example.com');

Same as L</"delete">, but performs all requests non-blocking and returns a L<Mojo::Promise> object instead of accepting
a callback.

  $ua->delete_p('http://example.com' => json => {a => 'b'})->then(sub {
    my $tx = shift;
    say $tx->result->body;
  })->catch(sub {
    my $err = shift;
    warn "Connection error: $err";
  })->wait;

=head2 get

  my $tx = $ua->get('example.com');
  my $tx = $ua->get('http://example.com' => {Accept => '*/*'} => 'Content!');
  my $tx = $ua->get(
    'http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $tx = $ua->get(
    'http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform blocking C<GET> request and return resulting L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the C<GET> method, which is implied). You can also append a callback to
perform requests non-blocking.

  $ua->get('http://example.com' => json => {a => 'b'} => sub {
    my ($ua, $tx) = @_;
    say $tx->result->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 get_p

  my $promise = $ua->get_p('http://example.com');

Same as L</"get">, but performs all requests non-blocking and returns a L<Mojo::Promise> object instead of accepting a
callback.

  $ua->get_p('http://example.com' => json => {a => 'b'})->then(sub {
    my $tx = shift;
    say $tx->result->body;
  })->catch(sub {
    my $err = shift;
    warn "Connection error: $err";
  })->wait;

=head2 head

  my $tx = $ua->head('example.com');
  my $tx = $ua->head('http://example.com' => {Accept => '*/*'} => 'Content!');
  my $tx = $ua->head('http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $tx = $ua->head('http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform blocking C<HEAD> request and return resulting L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the C<HEAD> method, which is implied). You can also append a callback
to perform requests non-blocking.

  $ua->head('http://example.com' => json => {a => 'b'} => sub {
    my ($ua, $tx) = @_;
    say $tx->result->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 head_p

  my $promise = $ua->head_p('http://example.com');

Same as L</"head">, but performs all requests non-blocking and returns a L<Mojo::Promise> object instead of accepting a
callback.

  $ua->head_p('http://example.com' => json => {a => 'b'})->then(sub {
    my $tx = shift;
    say $tx->result->body;
  })->catch(sub {
    my $err = shift;
    warn "Connection error: $err";
  })->wait;

=head2 options

  my $tx = $ua->options('example.com');
  my $tx = $ua->options('http://example.com' => {Accept => '*/*'} => 'Content!');
  my $tx = $ua->options('http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $tx = $ua->options('http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform blocking C<OPTIONS> request and return resulting L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the C<OPTIONS> method, which is implied). You can also append a
callback to perform requests non-blocking.

  $ua->options('http://example.com' => json => {a => 'b'} => sub {
    my ($ua, $tx) = @_;
    say $tx->result->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 options_p

  my $promise = $ua->options_p('http://example.com');

Same as L</"options">, but performs all requests non-blocking and returns a L<Mojo::Promise> object instead of
accepting a callback.

  $ua->options_p('http://example.com' => json => {a => 'b'})->then(sub {
    my $tx = shift;
    say $tx->result->body;
  })->catch(sub {
    my $err = shift;
    warn "Connection error: $err";
  })->wait;

=head2 patch

  my $tx = $ua->patch('example.com');
  my $tx = $ua->patch('http://example.com' => {Accept => '*/*'} => 'Content!');
  my $tx = $ua->patch('http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $tx = $ua->patch('http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform blocking C<PATCH> request and return resulting L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the C<PATCH> method, which is implied). You can also append a callback
to perform requests non-blocking.

  $ua->patch('http://example.com' => json => {a => 'b'} => sub {
    my ($ua, $tx) = @_;
    say $tx->result->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 patch_p

  my $promise = $ua->patch_p('http://example.com');

Same as L</"patch">, but performs all requests non-blocking and returns a L<Mojo::Promise> object instead of accepting
a callback.

  $ua->patch_p('http://example.com' => json => {a => 'b'})->then(sub {
    my $tx = shift;
    say $tx->result->body;
  })->catch(sub {
    my $err = shift;
    warn "Connection error: $err";
  })->wait;

=head2 post

  my $tx = $ua->post('example.com');
  my $tx = $ua->post('http://example.com' => {Accept => '*/*'} => 'Content!');
  my $tx = $ua->post('http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $tx = $ua->post('http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform blocking C<POST> request and return resulting L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the C<POST> method, which is implied). You can also append a callback
to perform requests non-blocking.

  $ua->post('http://example.com' => json => {a => 'b'} => sub {
    my ($ua, $tx) = @_;
    say $tx->result->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 post_p

  my $promise = $ua->post_p('http://example.com');

Same as L</"post">, but performs all requests non-blocking and returns a L<Mojo::Promise> object instead of accepting a
callback.

  $ua->post_p('http://example.com' => json => {a => 'b'})->then(sub {
    my $tx = shift;
    say $tx->result->body;
  })->catch(sub {
    my $err = shift;
    warn "Connection error: $err";
  })->wait;

=head2 put

  my $tx = $ua->put('example.com');
  my $tx = $ua->put('http://example.com' => {Accept => '*/*'} => 'Content!');
  my $tx = $ua->put('http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $tx = $ua->put('http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform blocking C<PUT> request and return resulting L<Mojo::Transaction::HTTP> object, takes the same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the C<PUT> method, which is implied). You can also append a callback to
perform requests non-blocking.

  $ua->put('http://example.com' => json => {a => 'b'} => sub {
    my ($ua, $tx) = @_;
    say $tx->result->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 put_p

  my $promise = $ua->put_p('http://example.com');

Same as L</"put">, but performs all requests non-blocking and returns a L<Mojo::Promise> object instead of accepting a
callback.

  $ua->put_p('http://example.com' => json => {a => 'b'})->then(sub {
    my $tx = shift;
    say $tx->result->body;
  })->catch(sub {
    my $err = shift;
    warn "Connection error: $err";
  })->wait;

=head2 start

  my $tx = $ua->start(Mojo::Transaction::HTTP->new);

Perform blocking request for a custom L<Mojo::Transaction::HTTP> object, which can be prepared manually or with
L</"build_tx">. You can also append a callback to perform requests non-blocking.

  my $tx = $ua->build_tx(GET => 'http://example.com');
  $ua->start($tx => sub {
    my ($ua, $tx) = @_;
    say $tx->result->body;
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 start_p

  my $promise = $ua->start_p(Mojo::Transaction::HTTP->new);

Same as L</"start">, but performs all requests non-blocking and returns a L<Mojo::Promise> object instead of accepting
a callback.

  my $tx = $ua->build_tx(GET => 'http://example.com');
  $ua->start_p($tx)->then(sub {
    my $tx = shift;
    say $tx->result->body;
  })->catch(sub {
    my $err = shift;
    warn "Connection error: $err";
  })->wait;

=head2 websocket

  $ua->websocket('ws://example.com' => sub {...});
  $ua->websocket('ws://example.com' => {DNT => 1} => ['v1.proto'] => sub {...});

Open a non-blocking WebSocket connection with transparent handshake, takes the same arguments as
L<Mojo::UserAgent::Transactor/"websocket">. The callback will receive either a L<Mojo::Transaction::WebSocket> or
L<Mojo::Transaction::HTTP> object, depending on if the handshake was successful.

  $ua->websocket('wss://example.com/echo' => ['v1.proto'] => sub {
    my ($ua, $tx) = @_;
    say 'WebSocket handshake failed!' and return unless $tx->is_websocket;
    say 'Subprotocol negotiation failed!' and return unless $tx->protocol;
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

You can activate C<permessage-deflate> compression by setting the C<Sec-WebSocket-Extensions> header, this can result
in much better performance, but also increases memory usage by up to 300KiB per connection.

  $ua->websocket('ws://example.com/foo' => {
    'Sec-WebSocket-Extensions' => 'permessage-deflate'
  } => sub {...});

=head2 websocket_p

  my $promise = $ua->websocket_p('ws://example.com');

Same as L</"websocket">, but returns a L<Mojo::Promise> object instead of accepting a callback.

  $ua->websocket_p('wss://example.com/echo')->then(sub {
    my $tx = shift;
    my $promise = Mojo::Promise->new;
    $tx->on(finish => sub { $promise->resolve });
    $tx->on(message => sub {
      my ($tx, $msg) = @_;
      say "WebSocket message: $msg";
      $tx->finish;
    });
    $tx->send('Hi!');
    return $promise;
  })->catch(sub {
    my $err = shift;
    warn "WebSocket error: $err";
  })->wait;

=head1 DEBUGGING

You can set the C<MOJO_CLIENT_DEBUG> environment variable to get some advanced diagnostics information printed to
C<STDERR>.

  MOJO_CLIENT_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
