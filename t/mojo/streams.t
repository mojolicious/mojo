use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop;
use Mojo::IOLoop::Stream::HTTPClient;
use Mojo::IOLoop::Stream::HTTPServer;
use Mojo::IOLoop::Stream::WebSocketClient;
use Mojo::IOLoop::Stream::WebSocketServer;
use Mojo::Transaction::HTTP;
use Mojolicious;

# Default app
my ($app, $client_stream, $server_stream);
$server_stream = Mojo::IOLoop::Stream::HTTPServer->new;
$app           = $server_stream->app;
ok $app, 'has default app';
isa_ok $app, 'Mojo::HelloWorld', 'right default app';

# App
$app = Mojolicious->new;
$app->log->level('fatal');

$app->routes->any('/' => sub { shift->render(text => 'Yay!') });

$app->routes->any(
  '/hello' => sub {
    my $c = shift;
    $c->render(text => $c->req->body . 'World!');
  }
);

$app->routes->any(
  '/keep-alive' => sub {
    my $c = shift;
    Mojo::IOLoop->stream($c->tx->connection)->max_requests(2);
    $c->on(finish => sub { $_[0]->stash->{kept_alive} = $_[0]->tx->kept_alive }
    );
    $c->render(text => 'Ok');
  }
);
$app->routes->any(
  '/premature' => sub { Mojo::IOLoop->stream(shift->tx->connection)->close });

$app->routes->any('/timeout' => sub { shift->render_later });

# Server
my $id = Mojo::IOLoop->server(
  {address => '127.0.0.1',
    stream_class => 'Mojo::IOLoop::Stream::HTTPServer'} => sub {
    my ($loop, $stream, $id) = @_;
    $server_stream = $stream->app($app);
    $stream->on(request => sub { shift->app->handler(shift) });
    $stream->on(start   => sub { pop->connection($id) });
  }
);
my $port = Mojo::IOLoop->acceptor($id)->port;

# Client connection options and callback
my $opts = {port => $port, stream_class => 'Mojo::IOLoop::Stream::HTTPClient'};
my $tx;
my $cb = sub {
  $client_stream = pop;
  $client_stream->process($tx);
  return $client_stream;
};

# Simple request
$tx = _tx('http://127.0.0.1/hello');
$tx->req->body('Hello');
my ($code, $result);
$tx->on(
  finish => sub {
    my $tx = shift;
    $code   = $tx->res->code;
    $result = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
_client($opts => $cb);
Mojo::IOLoop->start;
is $code,   200,           'right code';
is $result, 'HelloWorld!', 'right result';

# Premature connection close (server)
$tx = _tx('http://127.0.0.1/premature');
my $err;
$tx->on(
  finish => sub {
    $err = shift->error;
    Mojo::IOLoop->stop;
  }
);
$client_stream->process($tx);
Mojo::IOLoop->start;
ok !defined $err->{code}, 'no code';
is $err->{message}, 'Premature connection close', 'right message';

# Premature connection close (client)
$tx = _tx('http://127.0.0.1/');
$tx->on(
  finish => sub {
    $err = shift->error;
    Mojo::IOLoop->stop;
  }
);
$err = undef;
_client($opts => sub { $cb->(@_)->close });
Mojo::IOLoop->start;
ok !defined $err->{code}, 'no code';
is $err->{message}, 'Premature connection close', 'right message';

# HTTP Error
$tx = _tx('http://127.0.0.1/not_found');
$tx->on(
  finish => sub {
    $err = shift->error;
    Mojo::IOLoop->stop;
  }
);
$err = undef;
_client($opts => $cb);
Mojo::IOLoop->start;
is $err->{code},    404,         'right code';
is $err->{message}, 'Not Found', 'right message';

# Keep-alive
my ($closed, $stash);
$app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$tx = _tx('http://127.0.0.1/keep-alive');
$tx->on(finish => sub { Mojo::IOLoop->stop });
_client(
  $opts => sub {
    $cb->(@_)->on(close => sub { $closed++ });
  }
);
Mojo::IOLoop->start;
ok !$stash->{kept_alive}, 'connection was not kept alive';
ok !$closed, 'connection is not closed';
$app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$tx = _tx('http://127.0.0.1/keep-alive');
$tx->on(finish => sub { Mojo::IOLoop->stop });
$client_stream->process($tx);
Mojo::IOLoop->start;
ok $stash->{kept_alive}, 'connection was kept alive';
is $closed, 1, 'connection is closed';

# Timeout
$tx = _tx('http://127.0.0.1/timeout');
$tx->on(
  finish => sub {
    $err = shift->error;
    Mojo::IOLoop->stop;
  }
);
$err = undef;
_client(
  $opts => sub {
    $client_stream = pop->request_timeout(0.5);
    $client_stream->process($tx);
  }
);
Mojo::IOLoop->start;
ok !defined $err->{code}, 'no code';
is $err->{message}, 'Request timeout', 'right message';

sub _client {
  my $opts = {%{(shift)}};
  Mojo::IOLoop->client($opts => shift);
}

sub _tx {
  my $t = Mojo::Transaction::HTTP->new;
  $t->req->method('GET')->url->parse(shift);
  return $t;
}

done_testing();

