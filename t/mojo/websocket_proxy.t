use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

use Mojo::File 'curfile';
use lib curfile->sibling('lib')->to_string;

use Mojo::IOLoop;
use Mojo::IOLoop::Server;
use Mojo::Server::Daemon;
use Mojo::TestConnectProxy;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/' => sub {
  my $c   = shift;
  my $rel = $c->req->url;
  my $abs = $rel->to_abs;
  $c->render(text => "Hello World! $rel $abs");
};

get '/proxy' => sub {
  my $c = shift;
  $c->render(text => $c->req->url);
};

websocket '/test' => sub {
  my $c = shift;
  $c->on(message => sub { shift->send(shift() . 'test2') });
};

# HTTP server for testing
my $ua     = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
my $daemon = Mojo::Server::Daemon->new(app => app, silent => 1);
my $port   = $daemon->listen(['http://127.0.0.1'])->start->ports->[0];

# CONNECT proxy server for testing
my $id = Mojo::TestConnectProxy::proxy({address => '127.0.0.1'},
  {address => '127.0.0.1', port => $port});
my $proxy = Mojo::IOLoop->acceptor($id)->port;

# Normal non-blocking request
my $result;
$ua->get(
  "http://127.0.0.1:$port/" => sub {
    my ($ua, $tx) = @_;
    $result = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, "Hello World! / http://127.0.0.1:$port/", 'right content';

# Normal WebSocket
$result = undef;
$ua->websocket(
  "ws://127.0.0.1:$port/test" => sub {
    my ($ua, $tx) = @_;
    $tx->on(finish  => sub { Mojo::IOLoop->stop });
    $tx->on(message => sub { shift->finish; $result = shift });
    $tx->send('test1');
  }
);
Mojo::IOLoop->start;
is $result, 'test1test2', 'right result';

# Non-blocking proxy request
$ua->proxy->http("http://127.0.0.1:$port");
my $kept_alive;
$result = undef;
$ua->get(
  'http://example.com/proxy' => sub {
    my ($ua, $tx) = @_;
    $kept_alive = $tx->kept_alive;
    $result     = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$kept_alive, 'connection was not kept alive';
is $result, 'http://example.com/proxy', 'right content';

# Kept alive proxy WebSocket
($kept_alive, $result) = ();
$ua->websocket(
  "ws://127.0.0.1:$port/test" => sub {
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

# Blocking proxy request
my $tx = $ua->get('http://example.com/proxy');
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'http://example.com/proxy', 'right content';

# Proxy WebSocket
$ua = Mojo::UserAgent->new;
$ua->proxy->http("http://127.0.0.1:$proxy");
$result = undef;
$ua->websocket(
  "ws://127.0.0.1:$port/test" => sub {
    my ($ua, $tx) = @_;
    $tx->on(finish  => sub { Mojo::IOLoop->stop });
    $tx->on(message => sub { shift->finish; $result = shift });
    $tx->send('test1');
  }
);
Mojo::IOLoop->start;
is $result, 'test1test2', 'right result';

# Proxy WebSocket with bad target
$ua->proxy->http("http://127.0.0.1:$proxy");
my ($leak, $err);
$ua->websocket(
  "ws://127.0.0.1:0/test" => sub {
    my ($ua, $tx) = @_;
    $leak = !!Mojo::IOLoop->stream($tx->previous->connection);
    $err  = $tx->error;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$leak, 'connection has been removed';
is $err->{message}, 'Proxy connection failed', 'right message';

done_testing();
