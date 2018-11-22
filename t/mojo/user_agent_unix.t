use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::File 'tempdir';
use IO::Socket::UNIX;

use FindBin;
use lib "$FindBin::Bin/lib";

plan skip_all => 'set TEST_UNIX to enable this test (developer only!)'
  unless $ENV{TEST_UNIX} || $ENV{TEST_ALL};
my $dir   = tempdir;
my $dummy = $dir->child('dummy.sock')->to_string;
plan skip_all => 'UNIX domain socket support required for this test!'
  unless IO::Socket::UNIX->new(Listen => 1, Local => $dummy);

use Mojo::Server::Daemon;
use Mojo::TestConnectProxy;
use Mojo::UserAgent;
use Mojo::Util 'url_escape';
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/' => sub {
  my $c = shift;
  $c->render(text => $c->req->url);
};

get '/info' => sub {
  my $c              = shift;
  my $local_address  = $c->tx->local_address // 'None';
  my $local_port     = $c->tx->local_port // 'None';
  my $remote_address = $c->tx->remote_address // 'None';
  my $remote_port    = $c->tx->remote_port // 'None';
  $c->render(text => "$local_address:$local_port:$remote_address:$remote_port");
};

websocket '/echo' => sub {
  my $c = shift;
  $c->on(message =>
      sub { shift->send($c->req->url->to_abs->host . ': ' . shift)->finish });
};

# UNIX domain socket server
my $test    = $dir->child('test.sock');
my $encoded = url_escape "$test";
ok !$ENV{MOJO_REUSE}, 'environment is clean';
my $daemon = Mojo::Server::Daemon->new(
  app    => app,
  listen => ["http+unix://$encoded"],
  silent => 1
)->start;
ok -S $test, 'UNIX domain socket exists';
my $fd = fileno $daemon->ioloop->acceptor($daemon->acceptors->[0])->handle;
like $ENV{MOJO_REUSE}, qr/^unix:\Q$test\E:\Q$fd\E/,
  'file descriptor can be reused';

# Root
my $ua = Mojo::UserAgent->new(ioloop => $daemon->ioloop);
my $tx = $ua->get("http+unix://$encoded/");
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, '/', 'right content';
$tx = $ua->get("http+unix://$encoded/");
ok $tx->kept_alive, 'connection was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, '/', 'right content';

# Connection information
$tx = $ua->get("http+unix://$encoded/info");
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'None:None:None:None', 'right content';

# WebSocket
my $result;
$ua->websocket(
  "ws+unix://$encoded/echo" => sub {
    my ($ua, $tx) = @_;
    $tx->on(finish  => sub { Mojo::IOLoop->stop });
    $tx->on(message => sub { shift->finish; $result = shift });
    $tx->send('roundtrip works!');
  }
);
Mojo::IOLoop->start;
is $result, "$test: roundtrip works!", 'right result';

# WebSocket again
$result = undef;
$ua->websocket(
  "ws+unix://$encoded/echo" => sub {
    my ($ua, $tx) = @_;
    $tx->on(finish  => sub { Mojo::IOLoop->stop });
    $tx->on(message => sub { shift->finish; $result = shift });
    $tx->send('roundtrip works!');
  }
);
Mojo::IOLoop->start;
is $result, "$test: roundtrip works!", 'right result';

# WebSocket with proxy
my $proxy         = $dir->child('proxy.sock');
my $encoded_proxy = url_escape $proxy;
my $id = Mojo::TestConnectProxy::proxy({path => "$proxy"}, {path => "$test"});
$result = undef;
$ua->proxy->http("http+unix://$encoded_proxy");
$ua->websocket(
  'ws://example.com/echo' => sub {
    my ($ua, $tx) = @_;
    $tx->on(finish  => sub { Mojo::IOLoop->stop });
    $tx->on(message => sub { shift->finish; $result = shift });
    $tx->send('roundtrip works!');
  }
);
Mojo::IOLoop->start;
is $result, 'example.com: roundtrip works!', 'right result';
Mojo::IOLoop->remove($id);

# Proxy
$ua->proxy->http("http+unix://$encoded");
$tx = $ua->get('http://example.com');
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'http://example.com', 'right content';
$tx = $ua->get('http://example.com');
ok $tx->kept_alive, 'connection was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'http://example.com', 'right content';

# Cleanup
undef $daemon;
ok !$ENV{MOJO_REUSE}, 'environment is clean';

done_testing();
