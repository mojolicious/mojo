use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 55;

# "I was so bored I cut the pony tail off the guy in front of us.
#  Look at me, I'm a grad student.
#  I'm 30 years old and I made $600 last year.
#  Bart, don't make fun of grad students.
#  They've just made a terrible life choice."
use Mojo;
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::Transaction::HTTP;
use Mojo::UserAgent;
use Mojolicious;

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

# Silence
$app->log->level('fatal');

# POST /chunked
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
    $self->$cb();
  }
);

# POST /upload
$app->routes->post(
  '/upload' => sub {
    my $self = shift;
    $self->render_data($self->req->upload('file')->slurp);
  }
);

# /*
$app->routes->any('/*whatever' => {text => 'Your Mojo is working!'});

# Continue
my $port   = $ua->app_url->port;
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
          if $buffer =~ s/ is working!$//;
        $stream->write('4321')
          if $buffer =~ m#HTTP/1.1 100 Continue.*\x0d\x0a\x0d\x0a#gs;
      }
    );
    $stream->write("GET /1/ HTTP/1.1\x0d\x0a"
        . "Expect: 100-continue\x0d\x0a"
        . "Content-Length: 4\x0d\x0a\x0d\x0a");
  }
);
Mojo::IOLoop->start;
like $buffer, qr#HTTP/1.1 100 Continue.*Mojo$#s, 'request was continued';

# Pipelined
$buffer = '';
$id     = Mojo::IOLoop->client(
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
    $stream->write("GET /2/ HTTP/1.1\x0d\x0a"
        . "Content-Length: 0\x0d\x0a\x0d\x0a"
        . "GET /3/ HTTP/1.1\x0d\x0a"
        . "Content-Length: 0\x0d\x0a\x0d\x0a");
  }
);
Mojo::IOLoop->start;
like $buffer, qr/Mojo$/, 'transactions were pipelined';

# Normal request
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/5/');
$ua->start($tx);
ok $tx->keep_alive, 'will be kept alive';
is $tx->res->code,   200,      'right status';
like $tx->res->body, qr/Mojo/, 'right content';

# Keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/6/');
$ua->start($tx);
ok $tx->keep_alive, 'will be kept alive';
ok $tx->kept_alive, 'was kept alive';
is $tx->res->code,   200,      'right status';
like $tx->res->body, qr/Mojo/, 'right content';

# Non keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/7/');
$tx->req->headers->connection('close');
$ua->start($tx);
ok !$tx->keep_alive, 'will not be kept alive';
ok $tx->kept_alive, 'was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->headers->connection, 'close', 'right "Connection" value';
like $tx->res->body, qr/Mojo/, 'right content';

# Second non keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/8/');
$tx->req->headers->connection('close');
$ua->start($tx);
ok !$tx->keep_alive, 'will not be kept alive';
ok !$tx->kept_alive, 'was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->headers->connection, 'close', 'right "Connection" value';
like $tx->res->body, qr/Mojo/, 'right content';

# POST request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/9/');
$tx->req->headers->expect('fun');
$tx->req->body('foo bar baz' x 128);
$ua->start($tx);
is $tx->res->code,   200,      'right status';
like $tx->res->body, qr/Mojo/, 'right content';

# POST request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/10/');
$tx->req->headers->expect('fun');
$tx->req->body('bar baz foo' x 128);
$ua->start($tx);
ok defined $tx->connection, 'has connection id';
is $tx->res->code,   200,      'right status';
like $tx->res->body, qr/Mojo/, 'right content';

# Multiple requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/11/');
my $tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('/12/');
$ua->start($tx);
$ua->start($tx2);
ok defined $tx->connection,  'has connection id';
ok defined $tx2->connection, 'has connection id';
ok $tx->is_finished,  'transaction is finished';
ok $tx2->is_finished, 'transaction is finished';

# Form with chunked response
my %params;
for my $i (1 .. 10) { $params{"test$i"} = $i }
my $result = '';
for my $key (sort keys %params) { $result .= $params{$key} }
my ($code, $body);
$tx = $ua->post_form("http://127.0.0.1:$port/chunked" => \%params);
is $tx->res->code, 200, 'right status';
is $tx->res->body, $result, 'right content';

# Upload
($code, $body) = undef;
$tx = $ua->post_form(
  "http://127.0.0.1:$port/upload" => {file => {content => $result}});
is $tx->res->code, 200, 'right status';
is $tx->res->body, $result, 'right content';

# Parallel requests
my $delay = Mojo::IOLoop->delay;
$ua->get('/13/', $delay->begin);
$ua->post('/14/', {Expect => 'fun'}, 'bar baz foo' x 128, $delay->begin);
$ua->get('/15/', $delay->begin);
($tx, $tx2, my $tx3) = $delay->wait;
ok $tx->is_finished, 'transaction is finished';
is $tx->res->body, 'Your Mojo is working!', 'right content';
ok !$tx->error, 'no error';
ok $tx2->is_finished, 'transaction is finished';
is $tx2->res->body, 'Your Mojo is working!', 'right content';
ok !$tx2->error, 'no error';
ok $tx3->is_finished, 'transaction is finished';
is $tx3->res->body, 'Your Mojo is working!', 'right content';
ok !$tx3->error, 'no error';
