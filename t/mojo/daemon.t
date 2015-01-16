use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Cwd 'abs_path';
use File::Spec::Functions 'catdir';
use FindBin;
use Mojo;
use Mojo::IOLoop;
use Mojo::Log;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious;

package TestApp;
use Mojo::Base 'Mojo';

sub handler {
  my ($self, $tx) = @_;
  $tx->res->code(200);
  $tx->res->body('Hello TestApp!');
  $tx->resume;
}

package main;

# Minimal application
my $ua = Mojo::UserAgent->new;
$ua->server->app(TestApp->new);
my $tx = $ua->get('/');
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello TestApp!', 'right content';

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
  local $ENV{MOJO_LISTEN} = 'http://127.0.0.1:8080';
  is_deeply(Mojo::Server::Daemon->new->listen,
    ['http://127.0.0.1:8080'], 'right value');
  $ENV{MOJO_LISTEN} = 'http://*:80,https://*:443';
  is_deeply(
    Mojo::Server::Daemon->new->listen,
    ['http://*:80', 'https://*:443'],
    'right value'
  );
}

# Reverse proxy
{
  ok !Mojo::Server::Daemon->new->reverse_proxy, 'no reverse proxy';
  local $ENV{MOJO_REVERSE_PROXY} = 1;
  ok !!Mojo::Server::Daemon->new->reverse_proxy, 'reverse proxy';
}

# Optional home detection
my @path = qw(th is mojo dir wil l never-ever exist);
my $app = Mojo->new(home => Mojo::Home->new(catdir @path));
is $app->home, catdir(@path), 'right home directory';

# Config
is $app->config('foo'), undef, 'no value';
is_deeply $app->config(foo => 'bar')->config, {foo => 'bar'}, 'right value';
is $app->config('foo'), 'bar', 'right value';
delete $app->config->{foo};
is $app->config('foo'), undef, 'no value';
$app->config(foo => 'bar', baz => 'yada');
is $app->config({test => 23})->config->{test}, 23, 'right value';
is_deeply $app->config, {foo => 'bar', baz => 'yada', test => 23},
  'right value';

# Script name
my $path = "$FindBin::Bin/lib/../lib/myapp.pl";
is(Mojo::Server::Daemon->new->load_app($path)->config('script'),
  abs_path($path), 'right script name');

# Load broken app
eval {
  Mojo::Server::Daemon->new->load_app(
    "$FindBin::Bin/lib/Mojo/LoaderException.pm");
};
like $@, qr/^Can't load application/, 'right error';

# Load missing application class
eval { Mojo::Server::Daemon->new->build_app('Mojo::DoesNotExist') };
like $@, qr/^Can't find application class "Mojo::DoesNotExist" in \@INC/,
  'right error';

# Transaction
isa_ok $app->build_tx, 'Mojo::Transaction::HTTP', 'right class';

# Fresh application
$app = Mojolicious->new;
$ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
is $ua->server->app($app)->app->moniker, 'mojolicious', 'right moniker';

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
$tx = $ua->get('/normal/');
ok $tx->keep_alive, 'will be kept alive';
is $tx->res->code, 200,         'right status';
is $tx->res->body, 'Whatever!', 'right content';

# Keep-alive request
$tx = $ua->get('/normal/');
ok $tx->keep_alive, 'will be kept alive';
ok $tx->kept_alive, 'was kept alive';
is $tx->res->code, 200,         'right status';
is $tx->res->body, 'Whatever!', 'right content';

# Non-keep-alive request
$tx = $ua->get('/close/' => {Connection => 'close'});
ok !$tx->keep_alive, 'will not be kept alive';
ok $tx->kept_alive, 'was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->headers->connection, 'close', 'right "Connection" value';
is $tx->res->body, 'Whatever!', 'right content';

# Second non-keep-alive request
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

# Concurrent requests
my ($tx2, $tx3);
my $delay = Mojo::IOLoop->delay(sub { (undef, $tx, $tx2, $tx3) = @_ });
$ua->get('/concurrent1/' => $delay->begin);
$ua->post('/concurrent2/' => {Expect => 'fun'} => 'bar baz foo' x 128 =>
    $delay->begin);
$ua->get('/concurrent3/' => $delay->begin);
$delay->wait;
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
$tx = $ua->post('/chunked' => form => \%params);
is $tx->res->code, 200, 'right status';
is $tx->res->body, $result, 'right content';

# Upload
$tx = $ua->post('/upload' => form => {file => {content => $result}});
is $tx->res->code, 200, 'right status';
is $tx->res->body, $result, 'right content';
ok $tx->local_address, 'has local address';
ok $tx->local_port > 0, 'has local port';
ok $tx->original_remote_address, 'has original remote address';
ok $tx->remote_address,          'has remote address';
ok $tx->remote_port > 0, 'has remote port';
ok $local_address, 'has local address';
ok $local_port > 0, 'has local port';
ok $remote_address, 'has remote address';
ok $remote_port > 0, 'has remote port';

# Pipelined
my $daemon
  = Mojo::Server::Daemon->new(listen => ['http://127.0.0.1'], silent => 1);
$daemon->start;
my $port = Mojo::IOLoop->acceptor($daemon->acceptors->[0])->port;
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
$daemon = Mojo::Server::Daemon->new(
  app    => $app,
  listen => ['http://127.0.0.1'],
  silent => 1
);
is scalar @{$daemon->acceptors}, 0, 'no active acceptors';
is scalar @{$daemon->start->acceptors}, 1, 'one active acceptor';
$id = $daemon->acceptors->[0];
ok !!Mojo::IOLoop->acceptor($id), 'acceptor has been added';
is scalar @{$daemon->stop->acceptors}, 0, 'no active acceptors';
ok !Mojo::IOLoop->acceptor($id), 'acceptor has been removed';
is scalar @{$daemon->start->acceptors}, 1, 'one active acceptor';
$id = $daemon->acceptors->[0];
ok !!Mojo::IOLoop->acceptor($id), 'acceptor has been added';
undef $daemon;
ok !Mojo::IOLoop->acceptor($id), 'acceptor has been removed';

# Abstract methods
eval { Mojo::Server->run };
like $@, qr/Method "run" not implemented by subclass/, 'right error';

done_testing();
