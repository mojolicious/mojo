package Mojo::UserAgent;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::CookieJar;
use Mojo::IOLoop;
use Mojo::Log;
use Mojo::Server::Daemon;
use Mojo::Transaction::WebSocket;
use Mojo::URL;
use Mojo::UserAgent::Transactor;
use Scalar::Util 'weaken';

use constant DEBUG => $ENV{MOJO_USERAGENT_DEBUG} || 0;

# "You can't let a single bad experience scare you away from drugs."
has cert       => sub { $ENV{MOJO_CERT_FILE} };
has cookie_jar => sub { Mojo::CookieJar->new };
has [qw/http_proxy https_proxy no_proxy on_start/];
has ioloop => sub { Mojo::IOLoop->new };
has keep_alive_timeout => 15;
has key                => sub { $ENV{MOJO_KEY_FILE} };
has log                => sub { Mojo::Log->new };
has max_connections    => 5;
has max_redirects      => sub { $ENV{MOJO_MAX_REDIRECTS} || 0 };
has name               => 'Mojolicious (Perl)';
has transactor => sub { Mojo::UserAgent::Transactor->new };
has websocket_timeout => 300;

sub DESTROY { shift->_cleanup }

sub app {
  my ($self, $app) = @_;

  # Try to detect application
  $self->{app} ||= $ENV{MOJO_APP} if ref $ENV{MOJO_APP};
  if ($app) {
    $self->{app} =
      ref $app ? $app : $self->_test_server->app_class($app)->app;
    return $self;
  }

  return $self->{app};
}

sub build_form_tx      { shift->transactor->form(@_) }
sub build_tx           { shift->transactor->tx(@_) }
sub build_websocket_tx { shift->transactor->websocket(@_) }

sub delete {
  my $self = shift;
  $self->start($self->build_tx('DELETE', @_));
}

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

sub get {
  my $self = shift;
  $self->start($self->build_tx('GET', @_));
}

sub head {
  my $self = shift;
  $self->start($self->build_tx('HEAD', @_));
}

sub need_proxy {
  my ($self, $host) = @_;
  return 1 unless my $no = $self->no_proxy;
  $host =~ /\Q$_\E$/ and return for @$no;
  return 1;
}

sub post {
  my $self = shift;
  $self->start($self->build_tx('POST', @_));
}

sub post_form {
  my $self = shift;
  $self->start($self->build_form_tx(@_));
}

sub put {
  my $self = shift;
  $self->start($self->build_tx('PUT', @_));
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
  if ($self->{nb}) {
    croak 'Non-blocking requests in progress' if $self->{processing};
    warn "SWITCHING TO BLOCKING MODE\n" if DEBUG;
    $self->_cleanup;
    $self->{nb} = 0;
  }
  $self->_start($tx, sub { $tx = $_[1] });

  # Start loop
  my $loop = $self->ioloop;
  $loop->start;
  $loop->one_tick(0);

  return $tx;
}

sub test_server {
  my $self = shift;

  # Prepare application for testing
  my $server = $self->_test_server(@_);
  delete $server->{app};
  $server->app($self->app);
  $self->log($server->app->log);

  # Build absolute URL for test server
  return Mojo::URL->new->scheme($self->{scheme})->host('localhost')
    ->port($self->{port})->path('/');
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

    # Limit keep alive connections
    my $max = $self->max_connections;
    while (@$cache > $max) {
      my $cached = shift @$cache;
      $self->_drop($cached->[1]);
    }

    push @$cache, [$name, $id] if $max;
    return $self;
  }

  # Dequeue
  my $loop = $self->_loop;
  my $result;
  my @cache;
  for my $cached (@$cache) {

    # Search for name or id
    if (!$result && ($cached->[1] eq $name || $cached->[0] eq $name)) {
      my $id = $cached->[1];

      # Drop corrupted connection
      if ($loop->test($id)) { $result = $id }
      else                  { $loop->drop($id) }
    }

    # Cache again
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
  my $cs = $self->{connections} || {};
  $loop->drop($_) for keys %$cs;

  # Clean up keep alive connections
  my $cache = $self->{cache} || [];
  for my $cached (@$cache) {
    $loop->drop($cached->[1]);
  }
}

sub _connect {
  my ($self, $tx, $cb) = @_;

  # Keep alive connection
  weaken $self;
  my $loop = $self->_loop;
  my $id   = $tx->connection;
  my ($scheme, $host, $port) = $self->transactor->peer($tx);
  $id ||= $self->_cache("$scheme:$host:$port");
  if ($id && !ref $id) {
    warn "KEEP ALIVE CONNECTION ($scheme:$host:$port)\n" if DEBUG;
    $self->{connections}->{$id} = {cb => $cb, transaction => $tx};
    $tx->kept_alive(1);
    $self->_connected($id);
  }

  # New connection
  else {

    # CONNECT request to proxy required
    unless (($tx->req->method || '') eq 'CONNECT') {
      return if $self->_proxy_connect($tx, $cb);
    }

    # Connect
    warn "NEW CONNECTION ($scheme:$host:$port)\n" if DEBUG;
    $id = $loop->connect(
      address  => $host,
      port     => $port,
      handle   => $id,
      tls      => $scheme eq 'https' ? 1 : 0,
      tls_cert => $self->cert,
      tls_key  => $self->key,
      on_connect => sub { $self->_connected($_[1]) }
    );
    $self->{connections}->{$id} = {cb => $cb, transaction => $tx};
  }

  # Callbacks
  $loop->on_close($id => sub { $self->_handle(pop, 1) });
  $loop->on_error($id => sub { $self->_error(@_) });
  $loop->on_read($id => sub { $self->_read(@_) });

  return $id;
}

sub _connected {
  my ($self, $id) = @_;

  # Store connection information in transaction
  my $loop = $self->_loop;
  my $tx   = $self->{connections}->{$id}->{transaction};
  $tx->connection($id);
  my $local = $loop->local_info($id);
  $tx->local_address($local->{address});
  $tx->local_port($local->{port});
  my $remote = $loop->remote_info($id);
  $tx->remote_address($remote->{address});
  $tx->remote_port($remote->{port});
  $loop->connection_timeout($id => $self->keep_alive_timeout);

  # Write
  $self->_write($id);
}

sub _drop {
  my ($self, $id, $close) = @_;

  # Keep non-CONNECTed connection alive
  my $c  = delete $self->{connections}->{$id};
  my $tx = $c->{transaction};
  if (!$close && $tx && $tx->keep_alive && !$tx->error) {
    $self->_cache(join(':', $self->transactor->peer($tx)), $id)
      unless (($tx->req->method || '') =~ /^connect$/i
      && ($tx->res->code || '') eq '200');
    return;
  }

  # Close connection
  $self->_cache($id);
  $self->_loop->drop($id);
}

sub _error {
  my ($self, $loop, $id, $error) = @_;
  if (my $tx = $self->{connections}->{$id}->{transaction}) {
    $tx->res->error($error);
  }
  $self->log->error($error);
  $self->_handle($id, $error);
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
  return unless $cb;
  $self->$cb($tx);
}

sub _handle {
  my ($self, $id, $close) = @_;

  # Finish WebSocket
  my $c   = $self->{connections}->{$id};
  my $old = $c->{transaction};
  if ($old && $old->is_websocket) {
    $old->client_close;
    $self->{processing} -= 1;
    delete $self->{connections}->{$id};
    $self->_drop($id, $close);
  }

  # Upgrade connection to WebSocket
  elsif ($old && (my $new = $self->_upgrade($id))) {

    # Finish transaction and parse leftovers
    $self->_finish($new, $c->{cb});
    $new->client_read($old->res->leftovers);
  }

  # Finish normal connection
  else {
    $self->_drop($id, $close);
    return unless $old;
    if (my $jar = $self->cookie_jar) { $jar->extract($old) }
    $self->{processing} -= 1;

    # Redirect or callback
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

sub _proxy_connect {
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
        $self->_loop->start_tls($id);
        $old->req->proxy(undef);
      }

      # Share connection and start real transaction
      $old->connection($tx->connection);
      $self->_start($old, $cb);
    }
  );

  return 1;
}

sub _read {
  my ($self, $loop, $id, $chunk) = @_;
  warn "< $chunk\n" if DEBUG;

  # Corrupted connection
  return                   unless my $c  = $self->{connections}->{$id};
  return $self->_drop($id) unless my $tx = $c->{transaction};

  # Process incoming data
  $tx->client_read($chunk);
  if ($tx->is_done) { $self->_handle($id) }
  elsif ($c->{transaction}->is_writing) { $self->_write($id) }
}

sub _redirect {
  my ($self, $c, $old) = @_;

  # Build followup transaction
  return unless my $new = $self->transactor->redirect($old);

  # Max redirects
  my $redirects = $c->{redirects} || 0;
  my $max = $self->max_redirects;
  return unless $redirects < $max;

  # Start redirected request
  return 1 unless my $id = $self->_start($new, $c->{cb});
  $self->{connections}->{$id}->{redirects} = $redirects + 1;
  return 1;
}

sub _start {
  my ($self, $tx, $cb) = @_;

  # Embedded server
  if ($self->app) {
    my $req = $tx->req;
    my $url = $req->url->to_abs;
    $req->url($url->base($self->test_server)->to_abs) unless $url->host;
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
  if (my $start = $self->on_start) { $self->$start($tx) }
  return unless my $id = $self->_connect($tx, $cb);
  weaken $self;
  $tx->on_resume(sub { $self->_write($id) });
  $self->{processing} ||= 0;
  $self->{processing} += 1;

  return $id;
}

sub _test_server {
  my ($self, $scheme) = @_;

  # Fresh start
  if ($scheme) {
    delete $self->{port};
    delete $self->{server};
  }

  # Start test server
  unless ($self->{port}) {
    my $loop   = $self->_loop;
    my $server = $self->{server} =
      Mojo::Server::Daemon->new(ioloop => $loop, silent => 1);
    my $port = $self->{port} = $loop->generate_port;
    die "Couldn't find a free TCP port for testing.\n" unless $port;
    $self->{scheme} = $scheme ||= 'http';
    $server->listen(["$scheme://*:$port"]);
    $server->prepare_ioloop;
    warn "TEST SERVER STARTED ($scheme://*:$port)\n" if DEBUG;
  }

  return $self->{server};
}

sub _upgrade {
  my ($self, $id) = @_;

  # No upgrade request
  my $c   = $self->{connections}->{$id};
  my $old = $c->{transaction};
  return unless $old->req->headers->upgrade;

  # Handshake failed
  my $res = $old->res;
  return unless ($res->code || '') eq '101';

  # Upgrade to WebSocket transaction
  my $new = Mojo::Transaction::WebSocket->new(handshake => $old, masked => 1);
  $new->kept_alive($old->kept_alive);
  $res->error('WebSocket challenge failed.') and return
    unless $new->client_challenge;
  $c->{transaction} = $new;
  $self->_loop->connection_timeout($id, $self->websocket_timeout);
  weaken $self;
  $new->on_resume(sub { $self->_write($id) });

  return $new;
}

sub _write {
  my ($self, $id) = @_;

  # Prepare outgoing data
  return unless my $c  = $self->{connections}->{$id};
  return unless my $tx = $c->{transaction};
  return unless $tx->is_writing;
  my $chunk = $tx->client_write;

  # More data to follow
  my $cb;
  if ($tx->is_writing) {
    weaken $self;
    $cb = sub { $self->_write($id) };
  }

  # Write data
  $self->_loop->write($id, $chunk, $cb);
  warn "> $chunk\n"   if DEBUG;
  $self->_handle($id) if $tx->is_done;
}

1;
__END__

=encoding utf8

=head1 NAME

Mojo::UserAgent - Non-Blocking I/O HTTP 1.1 And WebSocket User Agent

=head1 SYNOPSIS

  use Mojo::UserAgent;
  my $ua = Mojo::UserAgent->new;

  # Say hello to the unicode snowman
  print $ua->get('www.☃.net?hello=there')->res->body;

  # Quick JSON API request with Basic authentication
  print $ua->get('https://sri:s3cret@api.twitter.com/1/trends.json')
    ->res->json->{trends}->[0]->{name};

  # Extract data from HTML and XML resources
  print $ua->get('mojolicio.us')->res->dom->html->head->title->text;

  # Scrape the latest headlines from a news site
  $ua->max_redirects(5)->get('www.reddit.com/r/perl/')
    ->res->dom('p.title > a.title')->each(sub { print $_->text, "\n" });

  # Form post with exception handling
  my $tx = $ua->post_form('search.cpan.org/search' => {q => 'mojo'});
  if (my $res = $tx->success) { print $res->body }
  else {
    my ($message, $code) = $tx->error;
    print "Error: $message";
  }

  # Grab the latest Mojolicious release :)
  $ua->max_redirects(5)->get('latest.mojolicio.us')
    ->res->content->asset->move_to('/Users/sri/mojo.tar.gz');

  # Parallel requests
  my $t = Mojo::IOLoop->trigger;
  for my $url ('mojolicio.us', 'cpan.org') {
    $t->begin;
    $ua->get($url => sub {
      my ($self, $tx) = @_;
      $t->end($tx->res->dom->at('title')->text);
    });
  }
  my @titles = $t->start;

  # TLS certificate authentication
  my $tx = $ua->cert('tls.crt')->key('tls.key')->get('https://mojolicio.us');

  # WebSocket request
  $ua->websocket('ws://websockets.org:8787' => sub {
    my ($self, $tx) = @_;
    $tx->on_finish(sub { Mojo::IOLoop->stop });
    $tx->on_message(sub {
      my ($tx, $message) = @_;
      print "$message\n";
      $tx->finish;
    });
    $tx->send_message('hi there!');
  });
  Mojo::IOLoop->start;

=head1 DESCRIPTION

L<Mojo::UserAgent> is a full featured non-blocking I/O HTTP 1.1 and WebSocket
user agent with C<IPv6>, C<TLS> and C<libev> support.

Optional modules L<EV>, L<IO::Socket::IP> and L<IO::Socket::SSL> are
supported transparently and used if installed.

=head1 ATTRIBUTES

L<Mojo::UserAgent> implements the following attributes.

=head2 C<cert>

  my $cert = $ua->cert;
  $ua      = $ua->cert('tls.crt');

Path to TLS certificate file, defaults to the value of the C<MOJO_CERT_FILE>
environment variable.

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

=head2 C<ioloop>

  my $loop = $ua->ioloop;
  $ua      = $ua->ioloop(Mojo::IOLoop->new);

Loop object to use for blocking I/O operations, defaults to a L<Mojo::IOLoop>
object.

=head2 C<keep_alive_timeout>

  my $keep_alive_timeout = $ua->keep_alive_timeout;
  $ua                    = $ua->keep_alive_timeout(15);

Maximum amount of time in seconds a connection can be inactive before being
dropped, defaults to C<15>.

=head2 C<key>

  my $key = $ua->key;
  $ua     = $ua->key('tls.crt');

Path to TLS key file, defaults to the value of the C<MOJO_KEY_FILE>
environment variable.

=head2 C<log>

  my $log = $ua->log;
  $ua     = $ua->log(Mojo::Log->new);

A L<Mojo::Log> object used for logging, defaults to the application log or a
L<Mojo::Log> object.

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
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<on_start>

  my $cb = $ua->on_start;
  $ua    = $ua->on_start(sub {...});

Callback to be invoked whenever a new transaction is about to start, this
includes automatically prepared proxy C<CONNECT> requests and followed
redirects.

  $ua->on_start(sub {
    my ($ua, $tx) = @_;
    $tx->req->headers->header('X-Bender', 'Bite my shiny metal ass!');
  });

=head2 C<transactor>

  my $t = $ua->transactor;
  $ua   = $ua->transactor(Mojo::UserAgent::Transactor->new);

Transaction builder, defaults to a L<Mojo::UserAgent::Transactor> object.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<websocket_timeout>

  my $websocket_timeout = $ua->websocket_timeout;
  $ua                   = $ua->websocket_timeout(300);

Maximum amount of time in seconds a WebSocket connection can be inactive
before being dropped, defaults to C<300>.

=head1 METHODS

L<Mojo::UserAgent> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<app>

  my $app = $ua->app;
  $ua     = $ua->app('MyApp');
  $ua     = $ua->app(MyApp->new);

Application relative URLs will be processed with, defaults to the value of
the C<MOJO_APP> environment variable.

  print $ua->app->secret;
  $ua->app->log->level('fatal');
  $ua->app->defaults(testing => 'oh yea!');

=head2 C<build_form_tx>

  my $tx = $ua->build_form_tx('http://kraih.com/foo' => {test => 123});

Alias for L<Mojo::UserAgent::Transactor/"form">.

=head2 C<build_tx>

  my $tx = $ua->build_tx(GET => 'mojolicio.us');

Alias for L<Mojo::UserAgent::Transactor/"tx">.

=head2 C<build_websocket_tx>

  my $tx = $ua->build_websocket_tx('ws://localhost:3000');

Alias for L<Mojo::UserAgent::Transactor/"websocket">.

=head2 C<delete>

  my $tx = $ua->delete('http://kraih.com');

Perform blocking HTTP C<DELETE> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the exact same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method).
You can also append a callback to perform requests non-blocking.

  $ua->delete('http://kraih.com' => sub {
    my ($self, $tx) = @_;
    print $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<detect_proxy>

  $ua = $ua->detect_proxy;

Check environment variables C<HTTP_PROXY>, C<http_proxy>, C<HTTPS_PROXY>,
C<https_proxy>, C<NO_PROXY> and C<no_proxy> for proxy information.

=head2 C<get>

  my $tx = $ua->get('http://kraih.com');

Perform blocking HTTP C<GET> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the exact same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method).
You can also append a callback to perform requests non-blocking.

  $ua->get('http://kraih.com' => sub {
    my ($self, $tx) = @_;
    print $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<head>

  my $tx = $ua->head('http://kraih.com');

Perform blocking HTTP C<HEAD> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the exact same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method).
You can also append a callback to perform requests non-blocking.

  $ua->head('http://kraih.com' => sub {
    my ($self, $tx) = @_;
    print $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<need_proxy>

  my $need_proxy = $ua->need_proxy('intranet.mojolicio.us');

Check if request for domain would use a proxy server.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<post>

  my $tx = $ua->post('http://kraih.com');

Perform blocking HTTP C<POST> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the exact same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method).
You can also append a callback to perform requests non-blocking.

  $ua->post('http://kraih.com' => sub {
    my ($self, $tx) = @_;
    print $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<post_form>

  my $tx = $ua->post_form('http://kraih.com/foo' => {test => 123});

Perform blocking HTTP C<POST> request with form data and return resulting
L<Mojo::Transaction::HTTP> object, takes the exact same arguments as
L<Mojo::UserAgent::Transactor/"form">.
You can also append a callback to perform requests non-blocking.

  $ua->post_form('http://kraih.com' => {q => 'test'} => sub {
    my ($self, $tx) = @_;
    print $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<put>

  my $tx = $ua->put('http://kraih.com');

Perform blocking HTTP C<PUT> request and return resulting
L<Mojo::Transaction::HTTP> object, takes the exact same arguments as
L<Mojo::UserAgent::Transactor/"tx"> (except for the method).
You can also append a callback to perform requests non-blocking.

  $ua->put('http://kraih.com' => sub {
    my ($self, $tx) = @_;
    print $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<start>

  $ua = $ua->start($tx);

Process blocking transaction.
You can also append a callback to perform transactions non-blocking.

  $ua->start($tx => sub {
    my ($self, $tx) = @_;
    print $tx->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<test_server>

  my $url = $ua->test_server;
  my $url = $ua->test_server('http');
  my $url = $ua->test_server('https');

Starts a test server for C<app> if necessary and returns absolute
L<Mojo::URL> object for it.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<websocket>

  $ua->websocket('ws://localhost:3000' => sub {...});

Open a non-blocking WebSocket connection with transparent handshake, takes
the exact same arguments as L<Mojo::UserAgent::Transactor/"websocket">.

  $ua->websocket('ws://localhost:3000/echo' => sub {
    my ($self, $tx) = @_;
    $tx->on_finish(sub  { Mojo::IOLoop->stop });
    $tx->on_message(sub {
      my ($tx, $message) = @_;
      print "$message\n";
    });
    $tx->send_message('Hi!');
  });
  Mojo::IOLoop->start;

=head1 DEBUGGING

You can set the C<MOJO_USERAGENT_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_USERAGENT_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
