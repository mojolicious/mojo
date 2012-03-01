package Mojo::UserAgent;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Mojo::CookieJar;
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::Transaction::WebSocket;
use Mojo::URL;
use Mojo::UserAgent::Transactor;
use Scalar::Util 'weaken';

use constant DEBUG => $ENV{MOJO_USERAGENT_DEBUG} || 0;

# "You can't let a single bad experience scare you away from drugs."
has ca              => sub { $ENV{MOJO_CA_FILE} };
has cert            => sub { $ENV{MOJO_CERT_FILE} };
has connect_timeout => sub { $ENV{MOJO_CONNECT_TIMEOUT} || 10 };
has cookie_jar      => sub { Mojo::CookieJar->new };
has [qw/http_proxy https_proxy local_address no_proxy/];
has inactivity_timeout => sub { $ENV{MOJO_INACTIVITY_TIMEOUT} // 20 };
has ioloop             => sub { Mojo::IOLoop->new };
has key                => sub { $ENV{MOJO_KEY_FILE} };
has max_connections    => 5;
has max_redirects => sub { $ENV{MOJO_MAX_REDIRECTS} || 0 };
has name => 'Mojolicious (Perl)';
has request_timeout => sub { $ENV{MOJO_REQUEST_TIMEOUT} // 0 };
has transactor => sub { Mojo::UserAgent::Transactor->new };

# Common HTTP methods
{
  no strict 'refs';
  for my $name (qw/DELETE GET HEAD PATCH POST PUT/) {
    *{__PACKAGE__ . '::' . lc($name)} = sub {
      my $self = shift;
      $self->start($self->build_tx($name, @_));
    };
  }
}

sub DESTROY { shift->_cleanup }

sub app {
  my ($self, $app) = @_;

  # Try to detect application
  $self->{app} ||= $ENV{MOJO_APP} if ref $ENV{MOJO_APP};
  if ($app) {
    $self->{app} = ref $app ? $app : $self->_server->app_class($app)->app;
    return $self;
  }

  return $self->{app};
}

sub app_url {
  my $self = shift;

  # Prepare application for testing
  my $server = $self->_server(@_);
  delete $server->{app};
  $server->app($self->app);

  # Build absolute URL for test server
  return Mojo::URL->new("$self->{scheme}://localhost:$self->{port}/");
}

sub build_form_tx      { shift->transactor->form(@_) }
sub build_tx           { shift->transactor->tx(@_) }
sub build_websocket_tx { shift->transactor->websocket(@_) }

sub detect_proxy {
  my $self = shift;

  # Upper case gets priority
  $self->http_proxy($ENV{HTTP_PROXY}   || $ENV{http_proxy});
  $self->https_proxy($ENV{HTTPS_PROXY} || $ENV{https_proxy});
  if (my $no = $ENV{NO_PROXY} || $ENV{no_proxy}) {
    $self->no_proxy([split /,/, $no]);
  }

  return $self;
}

# DEPRECATED in Leaf Fluttering In Wind!
sub keep_alive_timeout {
  warn <<EOF;
Mojo::UserAgent->keep_alive_timeout is DEPRECATED in favor of
Mojo::UserAgent->inactivity_timeout!
EOF
  shift->inactivity_timeout(@_);
}

sub need_proxy {
  my ($self, $host) = @_;
  return 1 unless my $no = $self->no_proxy;
  $host =~ /\Q$_\E$/ and return for @$no;
  return 1;
}

sub post_form {
  my $self = shift;
  $self->start($self->build_form_tx(@_));
}

sub start {
  my ($self, $tx, $cb) = @_;

  # Non-blocking
  if ($cb) {

    # Start non-blocking
    warn "NEW NON-BLOCKING REQUEST\n" if DEBUG;
    unless ($self->{nb}) {
      croak 'Blocking request in progress' if $self->{processing};
      warn "SWITCHING TO NON-BLOCKING MODE\n" if DEBUG;
      $self->_cleanup;
      $self->{nb} = 1;
    }
    return $self->_start($tx, $cb);
  }

  # Start blocking
  warn "NEW BLOCKING REQUEST\n" if DEBUG;
  if (delete $self->{nb}) {
    croak 'Non-blocking requests in progress' if $self->{processing};
    warn "SWITCHING TO BLOCKING MODE\n" if DEBUG;
    $self->_cleanup;
  }
  $self->_start($tx, sub { $tx = $_[1] });

  # Start loop
  $self->ioloop->start;

  return $tx;
}

sub websocket {
  my $self = shift;
  $self->start($self->build_websocket_tx(@_));
}

sub _cache {
  my ($self, $name, $id) = @_;

  # Enqueue
  my $cache = $self->{cache} ||= [];
  if ($id) {
    my $max = $self->max_connections;
    $self->_drop(shift(@$cache)->[1]) while @$cache > $max;
    push @$cache, [$name, $id] if $max;
    return;
  }

  # Dequeue
  my $loop = $self->_loop;
  my ($result, @cache);
  for my $cached (@$cache) {

    # Search for id/name and drop corrupted connections
    if (!$result && ($cached->[1] eq $name || $cached->[0] eq $name)) {
      my $stream = $loop->stream($cached->[1]);
      if ($stream && !$stream->is_readable) { $result = $cached->[1] }
      else                                  { $loop->drop($cached->[1]) }
    }

    # Requeue
    else { push @cache, $cached }
  }
  $self->{cache} = \@cache;

  return $result;
}

sub _cleanup {
  my $self = shift;
  return unless my $loop = $self->_loop;

  # Stop server
  delete $self->{port};
  delete $self->{server};

  # Clean up active connections
  warn "DROPPING ALL CONNECTIONS\n" if DEBUG;
  $loop->drop($_) for keys %{$self->{connections} || {}};

  # Clean up keep alive connections
  $loop->drop($_->[1]) for @{$self->{cache} || []};
}

sub _connect {
  my ($self, $tx, $cb) = @_;

  # Keep alive connection
  my $id = $tx->connection;
  my ($scheme, $host, $port) = $self->transactor->peer($tx);
  $id ||= $self->_cache("$scheme:$host:$port");
  if ($id && !ref $id) {
    warn "KEEP ALIVE CONNECTION ($scheme:$host:$port)\n" if DEBUG;
    $self->{connections}->{$id} = {cb => $cb, tx => $tx};
    $tx->kept_alive(1);
    $self->_connected($id);
    return $id;
  }

  # CONNECT request to proxy required
  return
    if ($tx->req->method || '') ne 'CONNECT'
    && $self->_connect_proxy($tx, $cb);

  # Connect
  warn "NEW CONNECTION ($scheme:$host:$port)\n" if DEBUG;
  weaken $self;
  $id = $self->_loop->client(
    address       => $host,
    port          => $port,
    handle        => $id,
    local_address => $self->local_address,
    timeout       => $self->connect_timeout,
    tls           => $scheme eq 'https' ? 1 : 0,
    tls_ca        => $self->ca,
    tls_cert      => $self->cert,
    tls_key       => $self->key,
    sub {
      my ($loop, $err, $stream) = @_;

      # Events
      return $self->_error($id, $err) if $err;
      $self->_events($stream, $id);
      $self->_connected($id);
    }
  );
  $self->{connections}->{$id} = {cb => $cb, tx => $tx};

  return $id;
}

sub _connect_proxy {
  my ($self, $old, $cb) = @_;

  # Start CONNECT request
  return unless my $new = $self->transactor->proxy_connect($old);
  $self->_start(
    $new => sub {
      my ($self, $tx) = @_;

      # CONNECT failed
      unless (($tx->res->code || '') eq '200') {
        $old->req->error('Proxy connection failed.');
        return $self->_finish($old, $cb);
      }

      # TLS upgrade
      if ($tx->req->url->scheme eq 'https') {
        return unless my $id = $tx->connection;
        $old->req->proxy(undef);
        my $loop   = $self->_loop;
        my $handle = $loop->stream($id)->steal_handle;
        weaken $self;
        return $loop->client(
          handle   => $handle,
          id       => $id,
          timeout  => $self->connect_timeout,
          tls      => 1,
          tls_ca   => $self->ca,
          tls_cert => $self->cert,
          tls_key  => $self->key,
          sub {
            my ($loop, $err, $stream) = @_;

            # Events
            return $self->_error($id, $err) if $err;
            $self->_events($stream, $id);

            # Start real transaction
            $old->connection($tx->connection);
            $self->_start($old, $cb);
          }
        );
      }

      # Start real transaction
      $old->connection($tx->connection);
      $self->_start($old, $cb);
    }
  );

  return 1;
}

sub _connected {
  my ($self, $id) = @_;

  # Inactivity timeout
  my $loop = $self->_loop;
  $loop->stream($id)->timeout($self->inactivity_timeout);

  # Store connection information in transaction
  my $tx = $self->{connections}->{$id}->{tx};
  $tx->connection($id);
  my $handle = $loop->stream($id)->handle;
  $tx->local_address($handle->sockhost)->local_port($handle->sockport);
  $tx->remote_address($handle->peerhost)->remote_port($handle->peerport);

  # Start writing
  weaken $self;
  $tx->on(resume => sub { $self->_write($id) });
  $self->_write($id);
}

sub _drop {
  my ($self, $id, $close) = @_;

  # Close connection
  my $tx = (delete($self->{connections}->{$id}) || {})->{tx};
  unless (!$close && $tx && $tx->keep_alive && !$tx->error) {
    $self->_cache($id);
    return $self->_loop->drop($id);
  }

  # Keep connection alive
  $self->_cache(join(':', $self->transactor->peer($tx)), $id)
    unless (($tx->req->method || '') eq 'CONNECT'
    && ($tx->res->code || '') eq '200');
}

sub _error {
  my ($self, $id, $err, $emit) = @_;
  if (my $tx = $self->{connections}->{$id}->{tx}) { $tx->res->error($err) }
  $self->emit(error => $err) if $emit;
  $self->_handle($id, $err);
}

sub _events {
  my ($self, $stream, $id) = @_;
  weaken $self;
  $stream->on(timeout => sub { $self->_error($id, 'Inactivity timeout.') });
  $stream->on(close => sub { $self->_handle($id, 1) });
  $stream->on(error => sub { $self->_error($id, pop, 1) });
  $stream->on(read => sub { $self->_read($id, pop) });
}

sub _finish {
  my ($self, $tx, $cb, $close) = @_;

  # Common errors
  my $res = $tx->res;
  unless ($res->error) {

    # Premature connection close
    if ($close && !$res->code) { $res->error('Premature connection close.') }

    # 400/500
    elsif ($res->is_status_class(400) || $res->is_status_class(500)) {
      $res->error($res->message, $res->code);
    }
  }

  # Callback
  $self->$cb($tx) if $cb;
}

sub _handle {
  my ($self, $id, $close) = @_;

  # Request timeout
  my $c = $self->{connections}->{$id};
  $self->_loop->drop($c->{timeout}) if $c->{timeout};

  # Finish WebSocket
  my $old = $c->{tx};
  if ($old && $old->is_websocket) {
    $self->{processing} -= 1;
    delete $self->{connections}->{$id};
    $self->_drop($id, $close);
    $old->client_close;
  }

  # Upgrade connection to WebSocket
  elsif ($old && (my $new = $self->_upgrade($id))) {
    $old->client_close;
    $self->_finish($new, $c->{cb});
    $new->client_read($old->res->leftovers);
  }

  # Finish normal connection
  else {
    $self->_drop($id, $close);
    return unless $old;
    if (my $jar = $self->cookie_jar) { $jar->extract($old) }
    $self->{processing} -= 1;
    $old->client_close;

    # Handle redirects
    $self->_finish($new || $old, $c->{cb}, $close)
      unless $self->_redirect($c, $old);
  }

  # Stop loop
  $self->ioloop->stop if !$self->{nb} && !$self->{processing};
}

sub _loop {
  my $self = shift;
  return $self->{nb} ? Mojo::IOLoop->singleton : $self->ioloop;
}

sub _read {
  my ($self, $id, $chunk) = @_;
  warn "< $chunk\n" if DEBUG;

  # Corrupted connection
  return                   unless my $c  = $self->{connections}->{$id};
  return $self->_drop($id) unless my $tx = $c->{tx};

  # Process incoming data
  $tx->client_read($chunk);
  if    ($tx->is_finished)     { $self->_handle($id) }
  elsif ($c->{tx}->is_writing) { $self->_write($id) }
}

sub _redirect {
  my ($self, $c, $old) = @_;

  # Build followup transaction
  return unless my $new = $self->transactor->redirect($old);

  # Max redirects
  my $redirects = delete $c->{redirects} || 0;
  return unless $redirects < $self->max_redirects;

  # Follow redirect
  return 1 unless my $id = $self->_start($new, delete $c->{cb});
  $self->{connections}->{$id}->{redirects} = $redirects + 1;
  return 1;
}

sub _server {
  my ($self, $scheme) = @_;

  # Restart with different scheme
  delete $self->{port}   if $scheme;
  return $self->{server} if $self->{port};

  # Start test server
  my $loop   = $self->_loop;
  my $server = $self->{server} =
    Mojo::Server::Daemon->new(ioloop => $loop, silent => 1);
  my $port = $self->{port} = $loop->generate_port;
  die "Couldn't find a free TCP port for testing.\n" unless $port;
  $self->{scheme} = $scheme ||= 'http';
  $server->listen(["$scheme://*:$port"])->start;
  warn "TEST SERVER STARTED ($scheme://*:$port)\n" if DEBUG;

  return $server;
}

sub _start {
  my ($self, $tx, $cb) = @_;

  # Embedded server
  if ($self->app) {
    my $req = $tx->req;
    my $url = $req->url->to_abs;
    $req->url($url->base($self->app_url)->to_abs) unless $url->host;
  }

  # Proxy
  $self->detect_proxy if $ENV{MOJO_PROXY};
  my $req    = $tx->req;
  my $url    = $req->url;
  my $scheme = $url->scheme || '';
  if ($self->need_proxy($url->host)) {

    # HTTP proxy
    if (my $proxy = $self->http_proxy) {
      $req->proxy($proxy) if !$req->proxy && $scheme eq 'http';
    }

    # HTTPS proxy
    if (my $proxy = $self->https_proxy) {
      $req->proxy($proxy) if !$req->proxy && $scheme eq 'https';
    }
  }

  # We identify ourselves
  my $headers = $req->headers;
  $headers->user_agent($self->name) unless $headers->user_agent;

  # Inject cookies
  if (my $jar = $self->cookie_jar) { $jar->inject($tx) }

  # Connect
  $self->emit(start => $tx);
  return unless my $id = $self->_connect($tx, $cb);
  $self->{processing} += 1;

  # Request timeout
  if (my $t = $self->request_timeout) {
    weaken $self;
    my $loop = $self->_loop;
    $self->{connections}->{$id}->{timeout} =
      $loop->timer($t => sub { $self->_error($id, 'Request timeout.') });
  }

  return $id;
}

sub _upgrade {
  my ($self, $id) = @_;

  # No upgrade request
  my $c   = $self->{connections}->{$id};
  my $old = $c->{tx};
  return unless $old->req->headers->upgrade;

  # Handshake failed
  my $res = $old->res;
  return unless ($res->code || '') eq '101';

  # Upgrade to WebSocket transaction
  my $new = Mojo::Transaction::WebSocket->new(handshake => $old, masked => 1);
  $new->kept_alive($old->kept_alive);
  $res->error('WebSocket challenge failed.') and return
    unless $new->client_challenge;
  $c->{tx} = $new;
  weaken $self;
  $new->on(resume => sub { $self->_write($id) });

  return $new;
}

sub _write {
  my ($self, $id) = @_;

  # Prepare outgoing data
  return unless my $c  = $self->{connections}->{$id};
  return unless my $tx = $c->{tx};
  return unless $tx->is_writing;
  return if $self->{writing}++;
  my $chunk = $tx->client_write;
  delete $self->{writing};
  warn "> $chunk\n" if DEBUG;

  # More data to follow
  my $cb;
  if ($tx->is_writing) {
    weaken $self;
    $cb = sub { $self->_write($id) };
  }

  # Write data
  $self->_loop->stream($id)->write($chunk, $cb);
  $self->_handle($id) if $tx->is_finished;
}

1;
__END__

=encoding utf8

=head1 NAME

Mojo::UserAgent - Non-blocking I/O HTTP 1.1 and WebSocket user agent

=head1 SYNOPSIS

  use Mojo::UserAgent;
  my $ua = Mojo::UserAgent->new;

  # Say hello to the unicode snowman
  say $ua->get('www.☃.net?hello=there')->res->body;

  # Quick JSON API request with Basic authentication
  say $ua->get('https://sri:s3cret@search.twitter.com/search.json?q=perl')
    ->res->json('/results/0/text');

  # Extract data from HTML and XML resources
  say $ua->get('mojolicio.us')->res->dom->html->head->title->text;

  # Scrape the latest headlines from a news site
  $ua->max_redirects(5)->get('www.reddit.com/r/perl/')
    ->res->dom('p.title > a.title')->each(sub { say $_->text });

  # Form POST with exception handling
  my $tx = $ua->post_form('search.cpan.org/search' => {q => 'mojo'});
  if (my $res = $tx->success) { say $res->body }
  else {
    my ($message, $code) = $tx->error;
    say "Error: $message";
  }

  # PUT request with content
  my $tx = $ua->put(
    'mojolicio.us' => {'Content-Type' => 'text/plain'} => 'Hello World!');

  # Grab the latest Mojolicious release :)
  $ua->max_redirects(5)->get('latest.mojolicio.us')
    ->res->content->asset->move_to('/Users/sri/mojo.tar.gz');

  # Parallel requests
  my $delay = Mojo::IOLoop->delay;
  for my $url ('mojolicio.us', 'cpan.org') {
    $delay->begin;
    $ua->get($url => sub {
      my ($ua, $tx) = @_;
      $delay->end($tx->res->dom->at('title')->text);
    });
  }
  my @titles = $delay->wait;

  # TLS certificate authentication
  my $tx = $ua->cert('tls.crt')->key('tls.key')->get('https://mojolicio.us');

  # WebSocket request
  $ua->websocket('ws://websockets.org:8787' => sub {
    my ($ua, $tx) = @_;
    $tx->on(finish  => sub { Mojo::IOLoop->stop });
    $tx->on(message => sub {
      my ($tx, $message) = @_;
      say $message;
      $tx->finish;
    });
    $tx->send('hi there!');
  });
  Mojo::IOLoop->start;

=head1 DESCRIPTION

L<Mojo::UserAgent> is a full featured non-blocking I/O HTTP 1.1 and WebSocket
user agent with C<IPv6>, C<TLS> and C<libev> support.

Optional modules L<EV>, L<IO::Socket::IP> and L<IO::Socket::SSL> are
supported transparently and used if installed. Individual features can also
be disabled with the C<MOJO_NO_IPV6> and C<MOJO_NO_TLS> environment
variables.

=head1 EVENTS

L<Mojo::UserAgent> can emit the following events.

=head2 C<error>

  $ua->on(error => sub {
    my ($ua, $err) = @_;
    ...
  });

Emitted if an error happens that can't be associated with a transaction.

  $ua->on(error => sub {
    my ($ua, $err) = @_;
    say "This looks bad: $err";
  });

=head2 C<start>

  $ua->on(start => sub {
    my ($ua, $tx) = @_;
    ...
  });

Emitted whenever a new transaction is about to start, this includes
automatically prepared proxy C<CONNECT> requests and followed redirects.

  $ua->on(start => sub {
    my ($ua, $tx) = @_;
    $tx->req->headers->header('X-Bender', 'Bite my shiny metal ass!');
  });

=head1 ATTRIBUTES

L<Mojo::UserAgent> implements the following attributes.

=head2 C<ca>

  my $ca = $ua->ca;
  $ua    = $ua->ca('/etc/tls/ca.crt');

Path to TLS certificate authority file, defaults to the value of the
C<MOJO_CA_FILE> environment variable. Note that this attribute is
EXPERIMENTAL and might change without warning!

  # Show certificate authorities for debugging
  IO::Socket::SSL::set_ctx_defaults(
    SSL_verify_callback => sub { say "Authority: $_[2]" and return $_[0] });

=head2 C<cert>

  my $cert = $ua->cert;
  $ua      = $ua->cert('/etc/tls/client.crt');

Path to TLS certificate file, defaults to the value of the C<MOJO_CERT_FILE>
environment variable.

=head2 C<connect_timeout>

  my $timeout = $ua->connect_timeout;
  $ua         = $ua->connect_timeout(5);

Maximum amount of time in seconds establishing a connection may take before
getting canceled, defaults to the value of the C<MOJO_CONNECT_TIMEOUT>
environment variable or C<10>.

=head2 C<cookie_jar>

  my $cookie_jar = $ua->cookie_jar;
  $ua            = $ua->cookie_jar(Mojo::CookieJar->new);

Cookie jar to use for this user agents requests, defaults to a
L<Mojo::CookieJar> object.

=head2 C<http_proxy>

  my $proxy = $ua->http_proxy;
  $ua       = $ua->http_proxy('http://sri:secret@127.0.0.1:8080');

Proxy server to use for HTTP and WebSocket requests.

=head2 C<https_proxy>

  my $proxy = $ua->https_proxy;
  $ua       = $ua->https_proxy('http://sri:secret@127.0.0.1:8080');

Proxy server to use for HTTPS and WebSocket requests.

=head2 C<inactivity_timeout>

  my $timeout = $ua->inactivity_timeout;
  $ua         = $ua->inactivity_timeout(15);

Maximum amount of time in seconds a connection can be inactive before getting
dropped, defaults to the value of the C<MOJO_INACTIVITY_TIMEOUT> environment
variable or C<20>. Setting the value to C<0> will allow connections to be
inactive indefinitely.

=head2 C<ioloop>

  my $loop = $ua->ioloop;
  $ua      = $ua->ioloop(Mojo::IOLoop->new);

Loop object to use for blocking I/O operations, defaults to a L<Mojo::IOLoop>
object.

=head2 C<key>

  my $key = $ua->key;
  $ua     = $ua->key('/etc/tls/client.crt');

Path to TLS key file, defaults to the value of the C<MOJO_KEY_FILE>
environment variable.

=head2 C<local_address>

  my $address = $ua->local_address;
  $ua         = $ua->local_address('127.0.0.1');

Local address to bind to. Note that this attribute is EXPERIMENTAL and might
change without warning!

=head2 C<max_connections>

  my $max_connections = $ua->max_connections;
  $ua                 = $ua->max_connections(5);

Maximum number of keep alive connections that the user agent will retain
before it starts closing the oldest cached ones, defaults to C<5>.

=head2 C<max_redirects>

  my $max_redirects = $ua->max_redirects;
  $ua               = $ua->max_redirects(3);

Maximum number of redirects the user agent will follow before it fails,
defaults to the value of the C<MOJO_MAX_REDIRECTS> environment variable or
C<0>.

=head2 C<name>

  my $name = $ua->name;
  $ua      = $ua->name('Mojolicious');

Value for C<User-Agent> request header, defaults to C<Mojolicious (Perl)>.

=head2 C<no_proxy>

  my $no_proxy = $ua->no_proxy;
  $ua          = $ua->no_proxy(['localhost', 'intranet.mojolicio.us']);

Domains that don't require a proxy server to be used.

=head2 C<request_timeout>

  my $timeout = $ua->request_timeout;
  $ua         = $ua->request_timeout(5);

Maximum amount of time in seconds establishing a connection, sending the
request and receiving a whole response may take before getting canceled,
defaults to the value of the C<MOJO_REQUEST_TIMEOUT> environment variable or
C<0>. Setting the value to C<0> will allow the user agent to wait
indefinitely. The timeout will reset for every followed redirect. Note that
this attribute is EXPERIMENTAL and might change without warning!

  # Total limit of 5 seconds, of which 3 seconds may be spent connecting
  $ua->max_redirects(0)->connect_timeout(3)->request_timeout(5);

=head2 C<transactor>

  my $t = $ua->transactor;
  $ua   = $ua->transactor(Mojo::UserAgent::Transactor->new);

Transaction builder, defaults to a L<Mojo::UserAgent::Transactor> object.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojo::UserAgent> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 C<app>

  my $app = $ua->app;
  $ua     = $ua->app('MyApp');
  $ua     = $ua->app(MyApp->new);

Application relative URLs will be processed with, defaults to the value of
the C<MOJO_APP> environment variable, which is usually a L<Mojo> or
L<Mojolicious> object.

  say $ua->app->secret;
  $ua->app->log->level('fatal');
  $ua->app->defaults(testing => 'oh yea!');

=head2 C<app_url>

  my $url = $ua->app_url;
  my $url = $ua->app_url('http');
  my $url = $ua->app_url('https');

Get absolute L<Mojo::URL> object for C<app> and switch protocol if necessary.
Note that this method is EXPERIMENTAL and might change without warning!

  say $ua->app_url->port;

=head2 C<build_form_tx>

  my $tx = $ua->build_form_tx('http://kraih.com/foo' => {test => 123});

Alias for L<Mojo::UserAgent::Transactor/"form">.

=head2 C<build_tx>

  my $tx = $ua->build_tx(GET => 'mojolicio.us');

Alias for L<Mojo::UserAgent::Transactor/"tx">.

=head2 C<build_websocket_tx>

  my $tx = $ua->build_websocket_tx('ws://localhost:3000');

Alias for L<Mojo::UserAgent::Transactor/"websocket">. Note that this method
is EXPERIMENTAL and might change without warning!

=head2 C<delete>

  my $tx = $ua->delete('http://kraih.com');

Perform blocking HTTP C<DELETE> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the exact same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->delete('http://kraih.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<detect_proxy>

  $ua = $ua->detect_proxy;

Check environment variables C<HTTP_PROXY>, C<http_proxy>, C<HTTPS_PROXY>,
C<https_proxy>, C<NO_PROXY> and C<no_proxy> for proxy information. Automatic
proxy detection can be enabled with the C<MOJO_PROXY> environment variable.

=head2 C<get>

  my $tx = $ua->get('http://kraih.com');

Perform blocking HTTP C<GET> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the exact same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->get('http://kraih.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<head>

  my $tx = $ua->head('http://kraih.com');

Perform blocking HTTP C<HEAD> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the exact same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->head('http://kraih.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<need_proxy>

  my $success = $ua->need_proxy('intranet.mojolicio.us');

Check if request for domain would use a proxy server.

=head2 C<patch>

  my $tx = $ua->patch('http://kraih.com');

Perform blocking HTTP C<PATCH> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the exact same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->patch('http://kraih.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<post>

  my $tx = $ua->post('http://kraih.com');

Perform blocking HTTP C<POST> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the exact same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->post('http://kraih.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<post_form>

  my $tx = $ua->post_form('http://kraih.com/foo' => {test => 123});

Perform blocking HTTP C<POST> request with form data and return resulting
L<Mojo::Transaction::HTTP> object, takes the exact same arguments as
L<Mojo::UserAgent::Transactor/"form">. You can also append a callback to
perform requests non-blocking.

  $ua->post_form('http://kraih.com' => {q => 'test'} => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<put>

  my $tx = $ua->put('http://kraih.com');

Perform blocking HTTP C<PUT> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the exact same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method). You can also
append a callback to perform requests non-blocking.

  $ua->put('http://kraih.com' => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<start>

  $ua = $ua->start($tx);

Process blocking transaction. You can also append a callback to perform
transactions non-blocking.

  $ua->start($tx => sub {
    my ($ua, $tx) = @_;
    say $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<websocket>

  $ua->websocket('ws://localhost:3000' => sub {...});

Open a non-blocking WebSocket connection with transparent handshake, takes
the exact same arguments as L<Mojo::UserAgent::Transactor/"websocket">. Note
that this method is EXPERIMENTAL and might change without warning!

  $ua->websocket('ws://localhost:3000/echo' => sub {
    my ($ua, $tx) = @_;
    $tx->on(finish  => sub { Mojo::IOLoop->stop });
    $tx->on(message => sub {
      my ($tx, $message) = @_;
      say "$message\n";
    });
    $tx->send('Hi!');
  });
  Mojo::IOLoop->start;

=head1 DEBUGGING

You can set the C<MOJO_USERAGENT_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_USERAGENT_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
