use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::TLS;

use Mojo::File qw(curfile);
use lib curfile->sibling('lib')->to_string;

plan skip_all => 'set TEST_TLS to enable this test (developer only!)' unless $ENV{TEST_TLS} || $ENV{TEST_ALL};
plan skip_all => 'IO::Socket::SSL 2.009+ required for this test!'     unless Mojo::IOLoop::TLS->can_tls;

use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::TestConnectProxy;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/' => sub {
  my $c = shift;
  $c->res->headers->header('X-Works', $c->req->headers->header('X-Works') // '');
  my $rel = $c->req->url;
  my $abs = $rel->to_abs;
  $c->render(text => "Hello World! $rel $abs");
};

get '/broken_redirect' => sub {
  my $c = shift;
  $c->render(text => 'Redirecting!', status => 302);
  $c->res->headers->location('/');
};

get '/proxy' => sub {
  my $c = shift;
  $c->render(text => $c->req->url->to_abs);
};

websocket '/test' => sub {
  my $c = shift;
  $c->on(message => sub { shift->send(shift() . 'test2') });
};

# Web server with valid certificates
my $daemon = Mojo::Server::Daemon->new(app => app, silent => 1);
my $listen
  = 'https://127.0.0.1' . '?cert=t/mojo/certs/server.crt' . '&key=t/mojo/certs/server.key' . '&ca=t/mojo/certs/ca.crt';
my $port = $daemon->listen([$listen])->start->ports->[0];

# Connect proxy server for testing
my $zero = "HTTP/1.1 501 FOO\x0d\x0a" . "Content-Length: 0\x0d\x0a" . "Connection: close\x0d\x0a\x0d\x0a";
my $id = Mojo::TestConnectProxy::proxy({address => '127.0.0.1'}, {address => '127.0.0.1', port => $port}, undef, $zero);
my $proxy = Mojo::IOLoop->acceptor($id)->port;

# User agent with valid certificates
my $ua = Mojo::UserAgent->new(
  ioloop => Mojo::IOLoop->singleton,
  ca     => 't/mojo/certs/ca.crt',
  cert   => 't/mojo/certs/client.crt',
  key    => 't/mojo/certs/client.key'
);

# Normal non-blocking request
my $result;
$ua->get(
  "https://127.0.0.1:$port/" => sub {
    my ($ua, $tx) = @_;
    $result = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, "Hello World! / https://127.0.0.1:$port/", 'right content';

# Broken redirect
my $start;
$ua->on(start => sub { $start++; pop->req->headers->header('X-Works', 'it does!') });
$result = undef;
my $works;
$ua->max_redirects(3)->get(
  "https://127.0.0.1:$port/broken_redirect" => sub {
    my ($ua, $tx) = @_;
    $result = $tx->res->body;
    $works  = $tx->res->headers->header('X-Works');
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, "Hello World! / https://127.0.0.1:$port/", 'right content';
is $works,  'it does!',                                'right header';
is $start,  2,                                         'redirected once';
$ua->unsubscribe('start');

# Normal WebSocket
$result = undef;
$ua->websocket(
  "wss://127.0.0.1:$port/test" => sub {
    my ($ua, $tx) = @_;
    $tx->on(finish  => sub { Mojo::IOLoop->stop });
    $tx->on(message => sub { shift->finish; $result = shift });
    $tx->send('test1');
  }
);
Mojo::IOLoop->start;
is $result, 'test1test2', 'right result';

# Non-blocking proxy request
$ua->proxy->https("http://sri:secr3t\@127.0.0.1:$proxy");
$result = undef;
my ($auth, $kept_alive);
$ua->get(
  "https://127.0.0.1:$port/proxy" => sub {
    my ($ua, $tx) = @_;
    $result     = $tx->res->body;
    $auth       = $tx->req->headers->proxy_authorization;
    $kept_alive = $tx->kept_alive;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$auth,       'no "Proxy-Authorization" header';
ok !$kept_alive, 'connection was not kept alive';
is $result, "https://127.0.0.1:$port/proxy", 'right content';

# Non-blocking kept alive proxy request
($kept_alive, $result) = ();
$ua->get(
  "https://127.0.0.1:$port/proxy" => sub {
    my ($ua, $tx) = @_;
    $kept_alive = $tx->kept_alive;
    $result     = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, "https://127.0.0.1:$port/proxy", 'right content';
ok $kept_alive, 'connection was kept alive';

# Kept alive proxy WebSocket
$ua->proxy->https("http://127.0.0.1:$proxy");
($kept_alive, $result) = ();
$ua->websocket(
  "wss://127.0.0.1:$port/test" => sub {
    my ($ua, $tx) = @_;
    $kept_alive = $tx->kept_alive;
    $tx->on(finish  => sub { Mojo::IOLoop->stop });
    $tx->on(message => sub { shift->finish; $result = shift });
    $tx->send('test1');
  }
);
Mojo::IOLoop->start;
ok $kept_alive, 'connection was kept alive';
is $result, 'test1test2', 'right result';

# Blocking proxy requests
$ua->proxy->https("http://sri:secr3t\@127.0.0.1:$proxy");
my $tx = $ua->max_connections(0)->get("https://127.0.0.1:$port/proxy");
is $tx->res->code,             200,                             'right status';
is $tx->res->body,             "https://127.0.0.1:$port/proxy", 'right content';
is $tx->req->method,           'GET',                           'right method';
is $tx->previous->req->method, 'CONNECT',                       'right method';
$tx = $ua->max_connections(5)->get("https://127.0.0.1:$port/proxy");
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code,             200,                             'right status';
is $tx->res->body,             "https://127.0.0.1:$port/proxy", 'right content';
is $tx->req->method,           'GET',                           'right method';
is $tx->previous->req->method, 'CONNECT',                       'right method';

# Proxy WebSocket with bad target
$ua->proxy->https("http://127.0.0.1:$proxy");
my ($leak, $err);
$ua->websocket(
  "wss://127.0.0.1:0/test" => sub {
    my ($ua, $tx) = @_;
    $leak = !!Mojo::IOLoop->stream($tx->previous->connection);
    $err  = $tx->error;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$leak, 'connection has been removed';
is $err->{message}, 'Proxy connection failed', 'right error';

# Blocking proxy request again
$tx = $ua->get("https://127.0.0.1:$port/proxy");
is $tx->res->code, 200,                             'right status';
is $tx->res->body, "https://127.0.0.1:$port/proxy", 'right content';

# Failed TLS handshake through proxy
my $close = Mojo::IOLoop->acceptor(Mojo::IOLoop->server(sub {
  my ($loop, $stream) = @_;
  $stream->on(read => sub { shift->close });
}))->port;
$id = Mojo::TestConnectProxy::proxy({address => '127.0.0.1'}, {address => '127.0.0.1', port => $close});
my $proxy2 = Mojo::IOLoop->acceptor($id)->port;
$ua->proxy->https("http://127.0.0.1:$proxy2");
$tx = $ua->get('https://example.com');
like $tx->error->{message}, qr/SSL connect attempt/, 'right error';

# Idle connection through proxy
my $idle = Mojo::IOLoop->acceptor(Mojo::IOLoop->server(sub { }))->port;
$id = Mojo::TestConnectProxy::proxy({address => '127.0.0.1'}, {address => '127.0.0.1', port => $idle});
my $proxy3 = Mojo::IOLoop->acceptor($id)->port;
$ua->on(start => sub { shift->connect_timeout(0.25) if pop->req->method eq 'CONNECT' });
$ua->proxy->https("http://127.0.0.1:$proxy3");
$tx = $ua->get('https://example.com');
is $tx->error->{message}, 'Connect timeout', 'right error';
$ua->connect_timeout(10);

# Blocking request to bad proxy
$ua    = Mojo::UserAgent->new;
$proxy = Mojo::IOLoop::Server->generate_port;
$ua->proxy->https("http://127.0.0.1:$proxy");
$tx = $ua->get("https://127.0.0.1:$port/proxy");
is $tx->error->{message}, 'Proxy connection failed', 'right error';

# Non-blocking request to bad proxy
$err = undef;
$ua->get(
  "https://127.0.0.1:$port/proxy" => sub {
    my ($ua, $tx) = @_;
    $err = $tx->error;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $err->{message}, 'Proxy connection failed', 'right error';

done_testing();
