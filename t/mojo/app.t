use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo;
use Mojo::IOLoop;
use Mojo::Log;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious;
use Socket qw(SO_REUSEPORT SOL_SOCKET);

# Timeout
{
  is(Mojo::Server::Daemon->new->inactivity_timeout, 15, 'right value');
  local $ENV{MOJO_INACTIVITY_TIMEOUT} = 25;
  is(Mojo::Server::Daemon->new->inactivity_timeout, 25, 'right value');
  $ENV{MOJO_INACTIVITY_TIMEOUT} = 0;
  is(Mojo::Server::Daemon->new->inactivity_timeout, 0, 'right value');
}

# Listen
{
  is_deeply(Mojo::Server::Daemon->new->listen,
    ['http://*:3000'], 'right value');
  local $ENV{MOJO_LISTEN} = 'http://localhost:8080';
  is_deeply(Mojo::Server::Daemon->new->listen,
    ['http://localhost:8080'], 'right value');
  $ENV{MOJO_LISTEN} = 'http://*:80,https://*:443';
  is_deeply(
    Mojo::Server::Daemon->new->listen,
    ['http://*:80', 'https://*:443'],
    'right value'
  );
}

# Logger
my $logger = Mojo::Log->new;
my $app = Mojo->new({log => $logger});
is $app->log, $logger, 'right logger';

# Config
is $app->config('foo'), undef, 'no value';
is_deeply $app->config(foo => 'bar')->config, {foo => 'bar'}, 'right value';
is $app->config('foo'), 'bar', 'right value';
delete $app->config->{foo};
is $app->config('foo'), undef, 'no value';
$app->config(foo => 'bar', baz => 'yada');
is_deeply $app->config, {foo => 'bar', baz => 'yada'}, 'right value';
$app->config({test => 23});
is $app->config->{test}, 23, 'right value';

# Transaction
isa_ok $app->build_tx, 'Mojo::Transaction::HTTP', 'right class';

# Fresh application
$app = Mojolicious->new;
my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton)->app($app);
is $ua->app->moniker, 'mojolicious', 'right moniker';

# Silence
$app->log->level('fatal');

$app->routes->post(
  '/chunked' => sub {
    my $self = shift;

    my $params = $self->req->params->to_hash;
    my @chunks;
    for my $key (sort keys %$params) { push @chunks, $params->{$key} }

    my $cb;
    $cb = sub {
      my $self = shift;
      $cb = undef unless my $chunk = shift @chunks || '';
      $self->write_chunk($chunk, $cb);
    };
    $self->$cb;
  }
);

my ($local_address, $local_port, $remote_address, $remote_port);
$app->routes->post(
  '/upload' => sub {
    my $self = shift;
    $local_address  = $self->tx->local_address;
    $local_port     = $self->tx->local_port;
    $remote_address = $self->tx->remote_address;
    $remote_port    = $self->tx->remote_port;
    $self->render(data => $self->req->upload('file')->slurp);
  }
);

$app->routes->any('/*whatever' => {text => 'Whatever!'});

# Normal request
my $tx = $ua->get('/normal/');
ok $tx->keep_alive, 'will be kept alive';
is $tx->res->code, 200,         'right status';
is $tx->res->body, 'Whatever!', 'right content';

# Keep-alive request
$tx = $ua->get('/normal/');
ok $tx->keep_alive, 'will be kept alive';
ok $tx->kept_alive, 'was kept alive';
is $tx->res->code, 200,         'right status';
is $tx->res->body, 'Whatever!', 'right content';

# Non keep-alive request
$tx = $ua->get('/close/' => {Connection => 'close'});
ok !$tx->keep_alive, 'will not be kept alive';
ok $tx->kept_alive, 'was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->headers->connection, 'close', 'right "Connection" value';
is $tx->res->body, 'Whatever!', 'right content';

# Second non keep-alive request
$tx = $ua->get('/close/' => {Connection => 'close'});
ok !$tx->keep_alive, 'will not be kept alive';
ok !$tx->kept_alive, 'was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->headers->connection, 'close', 'right "Connection" value';
is $tx->res->body, 'Whatever!', 'right content';

# HTTP/1.0 request
$tx = $ua->build_tx(GET => '/normal/');
$tx->req->version('1.0');
$tx = $ua->start($tx);
ok !$tx->keep_alive, 'will not be kept alive';
is $tx->res->version, '1.1', 'right version';
is $tx->res->code,    200,   'right status';
is $tx->res->headers->connection, 'close', 'right "Connection" value';
is $tx->res->body, 'Whatever!', 'right content';

# POST request
$tx = $ua->post('/fun/' => {Expect => 'fun'} => 'foo bar baz' x 128);
ok defined $tx->connection, 'has connection id';
is $tx->res->code, 200,         'right status';
is $tx->res->body, 'Whatever!', 'right content';

# Parallel requests
my $delay = Mojo::IOLoop->delay;
$ua->get('/parallel1/' => $delay->begin);
$ua->post(
  '/parallel2/' => {Expect => 'fun'} => 'bar baz foo' x 128 => $delay->begin);
$ua->get('/parallel3/' => $delay->begin);
($tx, my $tx2, my $tx3) = $delay->wait;
ok $tx->is_finished, 'transaction is finished';
is $tx->res->body, 'Whatever!', 'right content';
ok !$tx->error, 'no error';
ok $tx2->is_finished, 'transaction is finished';
is $tx2->res->body, 'Whatever!', 'right content';
ok !$tx2->error, 'no error';
ok $tx3->is_finished, 'transaction is finished';
is $tx3->res->body, 'Whatever!', 'right content';
ok !$tx3->error, 'no error';

# Form with chunked response
my %params;
for my $i (1 .. 10) { $params{"test$i"} = $i }
my $result = '';
for my $key (sort keys %params) { $result .= $params{$key} }
my ($code, $body);
my $port = $ua->app_url->port;
$tx = $ua->post("http://127.0.0.1:$port/chunked" => form => \%params);
is $tx->res->code, 200, 'right status';
is $tx->res->body, $result, 'right content';

# Upload
($code, $body) = ();
$tx = $ua->post(
  "http://127.0.0.1:$port/upload" => form => {file => {content => $result}});
is $tx->res->code, 200, 'right status';
is $tx->res->body, $result, 'right content';
ok $tx->local_address, 'has local address';
ok $tx->local_port > 0, 'has local port';
ok $tx->remote_address, 'has local address';
ok $tx->remote_port > 0, 'has local port';
ok $local_address, 'has local address';
ok $local_port > 0, 'has local port';
ok $remote_address, 'has local address';
ok $remote_port > 0, 'has local port';

# Pipelined
$port = Mojo::IOLoop->generate_port;
my $daemon = Mojo::Server::Daemon->new(listen => ["http://127.0.0.1:$port"],
  silent => 1);
$daemon->start;
is $daemon->app->moniker, 'HelloWorld', 'right moniker';
my $buffer = '';
my $id;
$id = Mojo::IOLoop->client(
  {port => $port} => sub {
    my ($loop, $err, $stream) = @_;
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;
        $buffer .= $chunk;
        Mojo::IOLoop->remove($id) and Mojo::IOLoop->stop
          if $buffer =~ s/ is working!.*is working!$//gs;
      }
    );
    $stream->write("GET /pipeline1/ HTTP/1.1\x0d\x0a"
        . "Content-Length: 0\x0d\x0a\x0d\x0a"
        . "GET /pipeline2/ HTTP/1.1\x0d\x0a"
        . "Content-Length: 0\x0d\x0a\x0d\x0a");
  }
);
Mojo::IOLoop->start;
like $buffer, qr/Mojo$/, 'transactions were pipelined';

# Throttling
$port   = Mojo::IOLoop->generate_port;
$daemon = Mojo::Server::Daemon->new(
  app    => $app,
  listen => ["http://127.0.0.1:$port"],
  silent => 1
);
is_deeply $daemon->acceptors, [], 'no active acceptors';
$daemon->start;
is scalar @{$daemon->acceptors}, 1, 'one active acceptor';
is $daemon->app->moniker, 'mojolicious', 'right moniker';
$tx = $ua->get("http://127.0.0.1:$port/throttle1" => {Connection => 'close'});
ok $tx->success, 'successful';
is $tx->res->code, 200,         'right status';
is $tx->res->body, 'Whatever!', 'right content';
$daemon->stop;
is_deeply $daemon->acceptors, [], 'no active acceptors';
$tx = $ua->inactivity_timeout(0.5)
  ->get("http://127.0.0.1:$port/throttle2" => {Connection => 'close'});
ok !$tx->success, 'not successful';
is $tx->error, 'Inactivity timeout', 'right error';
$daemon->start;
$tx = $ua->inactivity_timeout(10)
  ->get("http://127.0.0.1:$port/throttle3" => {Connection => 'close'});
ok $tx->success, 'successful';
is $tx->res->code, 200,         'right status';
is $tx->res->body, 'Whatever!', 'right content';

# SO_REUSEPORT
SKIP: {
  skip 'SO_REUSEPORT support required!', 2 unless eval {SO_REUSEPORT};

  $port   = Mojo::IOLoop->generate_port;
  $daemon = Mojo::Server::Daemon->new(
    listen => ["http://127.0.0.1:$port"],
    silent => 1
  )->start;
  ok !Mojo::IOLoop->acceptor($daemon->acceptors->[0])
    ->handle->getsockopt(SOL_SOCKET, SO_REUSEPORT),
    'no SO_REUSEPORT socket option';
  $daemon = Mojo::Server::Daemon->new(
    listen => ["http://127.0.0.1:$port?reuse=1"],
    silent => 1
  );
  $daemon->start;
  ok !!Mojo::IOLoop->acceptor($daemon->acceptors->[0])
    ->handle->getsockopt(SOL_SOCKET, SO_REUSEPORT),
    'SO_REUSEPORT socket option';
}

done_testing();
