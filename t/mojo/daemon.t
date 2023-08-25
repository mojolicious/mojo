use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_TLS}  = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use IO::Socket::INET;
use Mojo::File qw(curfile path);
use Mojo::IOLoop;
use Mojo::Promise;
use Mojo::Log;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious;

package TestApp;
use Mojo::Base 'Mojolicious';

sub handler {
  my ($self, $tx) = @_;
  $tx->res->code(200);
  $tx->res->body('Hello TestApp!');
  $tx->resume;
}

package main;

subtest 'Minimal application' => sub {
  my $ua = Mojo::UserAgent->new;
  $ua->server->app(TestApp->new);
  my $tx = $ua->get('/');
  is $tx->res->code, 200,              'right status';
  is $tx->res->body, 'Hello TestApp!', 'right content';
};

subtest 'Timeouts' => sub {
  is(Mojo::Server::Daemon->new->inactivity_timeout, 30, 'right value');
  local $ENV{MOJO_INACTIVITY_TIMEOUT} = 25;
  is(Mojo::Server::Daemon->new->inactivity_timeout, 25, 'right value');
  $ENV{MOJO_INACTIVITY_TIMEOUT} = 0;
  is(Mojo::Server::Daemon->new->inactivity_timeout, 0, 'right value');
  is(Mojo::Server::Daemon->new->keep_alive_timeout, 5, 'right value');
  local $ENV{MOJO_KEEP_ALIVE_TIMEOUT} = 25;
  is(Mojo::Server::Daemon->new->keep_alive_timeout, 25, 'right value');
  $ENV{MOJO_KEEP_ALIVE_TIMEOUT} = 0;
  is(Mojo::Server::Daemon->new->keep_alive_timeout, 0, 'right value');
};

subtest 'Listen' => sub {
  is_deeply(Mojo::Server::Daemon->new->listen, ['http://*:3000'], 'right value');
  local $ENV{MOJO_LISTEN} = 'http://127.0.0.1:8080';
  is_deeply(Mojo::Server::Daemon->new->listen, ['http://127.0.0.1:8080'], 'right value');
  $ENV{MOJO_LISTEN} = 'http://*:80,https://*:443';
  is_deeply(Mojo::Server::Daemon->new->listen, ['http://*:80', 'https://*:443'], 'right value');
};

subtest 'Reverse proxy' => sub {
  ok !Mojo::Server::Daemon->new->reverse_proxy, 'no reverse proxy';
  local $ENV{MOJO_REVERSE_PROXY} = 1;
  ok !!Mojo::Server::Daemon->new->reverse_proxy, 'reverse proxy';
};

subtest 'Config' => sub {
  my $app = Mojolicious->new;
  is $app->config('foo'), undef, 'no value';
  is_deeply $app->config(foo => 'bar')->config, {foo => 'bar'}, 'right value';
  is $app->config('foo'), 'bar', 'right value';
  delete $app->config->{foo};
  is $app->config('foo'), undef, 'no value';
  $app->config(foo => 'bar', baz => 'yada');
  is $app->config({test => 23})->config->{test}, 23, 'right value';
  is_deeply $app->config, {foo => 'bar', baz => 'yada', test => 23}, 'right value';
};

subtest 'Loading' => sub {
  my $daemon = Mojo::Server::Daemon->new;
  my $path   = curfile->sibling('lib', '..', 'lib', 'myapp.pl');
  is ref $daemon->load_app($path),      'Mojolicious::Lite', 'right reference';
  is $daemon->app->config('script'),    path($path)->to_abs, 'right script name';
  is ref $daemon->build_app('TestApp'), 'TestApp',           'right reference';
  is ref $daemon->app,                  'TestApp',           'right reference';
};

subtest 'Load broken app' => sub {
  my $bin = curfile->dirname;
  eval { Mojo::Server::Daemon->new->load_app("$bin/lib/Mojo/LoaderTest/A.pm") };
  like $@, qr/did not return an application object/, 'right error';
  eval { Mojo::Server::Daemon->new->load_app("$bin/lib/Mojo/LoaderException.pm") };
  like $@, qr/^Can't load application/, 'right error';
};

subtest 'Load app using module_true' => sub {
  plan skip_all => 'module_true feature requires perl 5.38' if $] < 5.038;
  my $daemon = Mojo::Server::Daemon->new;
  my $path   = curfile->sibling('lib', '..', 'lib', 'myapp-module-true.pl');
  my $app    = eval { $daemon->load_app($path) };
  is $@,       '',                  'no error loading app';
  is ref $app, 'Mojolicious::Lite', 'right reference';
};

subtest 'Load missing application class' => sub {
  eval { Mojo::Server::Daemon->new->build_app('Mojo::DoesNotExist') };
  like $@, qr/^Can't find application class "Mojo::DoesNotExist" in \@INC/, 'right error';
};

subtest 'Invalid listen location' => sub {
  eval { Mojo::Server::Daemon->new(listen => ['fail'])->start };
  like $@, qr/Invalid listen location/, 'right error';
};

subtest 'Transaction' => sub {
  my $app = Mojolicious->new;
  isa_ok $app->build_tx, 'Mojo::Transaction::HTTP', 'right transaction';
};

my $app = Mojolicious->new;
my $ua  = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);

subtest 'Moniker' => sub {
  is $ua->server->app($app)->app->moniker, 'mojolicious', 'right moniker';
};

# Silence
$app->log->level('fatal');

$app->routes->post(
  '/chunked' => sub {
    my $c = shift;

    my $params = $c->req->params->to_hash;
    my @chunks;
    for my $key (sort keys %$params) { push @chunks, $params->{$key} }

    my $cb = sub {
      my $c     = shift;
      my $chunk = shift @chunks || '';
      $c->write_chunk($chunk, $chunk ? __SUB__ : ());
    };
    $c->$cb;
  }
);

my ($local_address, $local_port, $remote_address, $remote_port);
$app->routes->post(
  '/upload' => sub {
    my $c = shift;
    $local_address  = $c->tx->local_address;
    $local_port     = $c->tx->local_port;
    $remote_address = $c->tx->remote_address;
    $remote_port    = $c->tx->remote_port;
    $c->render(data => $c->req->upload('file')->slurp);
  }
);

$app->routes->any(
  '/port' => sub {
    my $c = shift;
    $c->render(text => $c->req->url->to_abs->port);
  }
);

$app->routes->any(
  '/timeout' => sub {
    my $c  = shift;
    my $id = $c->tx->connection;
    $c->res->headers->header('X-Connection-ID' => $id);
    $c->render(text => Mojo::IOLoop->stream($id)->timeout);
  }
);

$app->routes->any('/*whatever' => {text => 'Whatever!'});

subtest 'Normal request' => sub {
  my $tx = $ua->get('/normal/');
  ok $tx->keep_alive, 'will be kept alive';
  is $tx->res->code, 200,         'right status';
  is $tx->res->body, 'Whatever!', 'right content';
};

subtest 'Keep-alive request' => sub {
  my $tx = $ua->get('/normal/');
  ok $tx->keep_alive, 'will be kept alive';
  ok $tx->kept_alive, 'was kept alive';
  is $tx->res->code, 200,         'right status';
  is $tx->res->body, 'Whatever!', 'right content';
};

subtest 'Non-keep-alive request' => sub {
  my $tx = $ua->get('/close/' => {Connection => 'close'});
  ok !$tx->keep_alive, 'will not be kept alive';
  ok $tx->kept_alive,  'was kept alive';
  is $tx->res->code, 200,         'right status';
  is $tx->res->body, 'Whatever!', 'right content';
};

subtest 'Second non-keep-alive request' => sub {
  my $tx = $ua->get('/close/' => {Connection => 'close'});
  ok !$tx->keep_alive, 'will not be kept alive';
  ok !$tx->kept_alive, 'was not kept alive';
  is $tx->res->code, 200,         'right status';
  is $tx->res->body, 'Whatever!', 'right content';
};

subtest 'HTTP/1.0 request' => sub {
  my $tx = $ua->build_tx(GET => '/normal/');
  $tx->req->version('1.0');
  $tx = $ua->start($tx);
  ok !$tx->keep_alive, 'will not be kept alive';
  is $tx->res->version, '1.1',       'right version';
  is $tx->res->code,    200,         'right status';
  is $tx->res->body,    'Whatever!', 'right content';
};

subtest 'POST request' => sub {
  my $tx = $ua->post('/fun/' => {Expect => 'fun'} => 'foo bar baz' x 128);
  ok defined $tx->connection, 'has connection id';
  is $tx->res->code, 200,         'right status';
  is $tx->res->body, 'Whatever!', 'right content';
};

subtest 'Concurrent requests' => sub {
  my $tx = $ua->post('/fun/' => {Expect => 'fun'} => 'foo bar baz' x 128);
  my ($tx2, $tx3);
  Mojo::Promise->all(
    $ua->get_p('/concurrent1/'),
    $ua->post_p('/concurrent2/' => {Expect => 'fun'} => 'bar baz foo' x 128),
    $ua->get_p('/concurrent3/')
  )->then(sub {
    ($tx, $tx2, $tx3) = map { $_->[0] } @_;
  })->wait;
  ok $tx->is_finished, 'transaction is finished';
  is $tx->res->body, 'Whatever!', 'right content';
  ok !$tx->error,       'no error';
  ok $tx2->is_finished, 'transaction is finished';
  is $tx2->res->body, 'Whatever!', 'right content';
  ok !$tx2->error,      'no error';
  ok $tx3->is_finished, 'transaction is finished';
  is $tx3->res->body, 'Whatever!', 'right content';
  ok !$tx3->error, 'no error';
};

subtest 'Form with chunked response' => sub {
  my %params;
  for my $i (1 .. 10) { $params{"test$i"} = $i }
  my $result = '';
  for my $key (sort keys %params) { $result .= $params{$key} }
  my $tx = $ua->post('/chunked' => form => \%params);
  is $tx->res->code, 200,     'right status';
  is $tx->res->body, $result, 'right content';
};

subtest 'Upload' => sub {
  my $result = '';
  my $tx     = $ua->post('/upload' => form => {file => {content => $result}});
  is $tx->res->code, 200,     'right status';
  is $tx->res->body, $result, 'right content';
  ok $tx->local_address,           'has local address';
  ok $tx->local_port > 0,          'has local port';
  ok $tx->original_remote_address, 'has original remote address';
  ok $tx->remote_address,          'has remote address';
  ok $tx->remote_port > 0,         'has remote port';
  ok $local_address,               'has local address';
  ok $local_port > 0,              'has local port';
  ok $remote_address,              'has remote address';
  ok $remote_port > 0,             'has remote port';
};

subtest 'Timeout' => sub {
  my $tx = $ua->get('/timeout');
  ok $tx->keep_alive, 'will be kept alive';
  is $tx->res->code, 200, 'right status';
  is $tx->res->body, 30,  'inactivity timeout was used for the request';
  is(Mojo::IOLoop->stream($tx->res->headers->header('X-Connection-ID'))->timeout,
    5, 'keep-alive timeout was assigned after the request');
};

subtest 'Pipelined' => sub {
  my $daemon = Mojo::Server::Daemon->new({listen => ['http://127.0.0.1'], silent => 1});
  my $port   = $daemon->start->ports->[0];
  is $daemon->app->moniker, 'mojo-hello_world', 'right moniker';
  my $buffer = '';
  my $id;
  $id = Mojo::IOLoop->client(
    {port => $port} => sub {
      my ($loop, $err, $stream) = @_;
      $stream->on(
        read => sub {
          my ($stream, $chunk) = @_;
          $buffer .= $chunk;
          Mojo::IOLoop->remove($id) and Mojo::IOLoop->stop if $buffer =~ s/ is working!.*is working!$//gs;
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
};

subtest 'Throttling' => sub {
  my $daemon = Mojo::Server::Daemon->new(app => $app, listen => ['http://127.0.0.1'], max_clients => 23, silent => 1);
  is scalar @{$daemon->acceptors},               0,  'no active acceptors';
  is scalar @{$daemon->start->start->acceptors}, 1,  'one active acceptor';
  is $daemon->ioloop->max_connections,           23, 'right value';
  my $id = $daemon->acceptors->[0];
  ok !!Mojo::IOLoop->acceptor($id), 'acceptor has been added';
  is scalar @{$daemon->stop->acceptors}, 0, 'no active acceptors';
  ok !Mojo::IOLoop->acceptor($id), 'acceptor has been removed';
  is scalar @{$daemon->start->acceptors}, 1, 'one active acceptor';
  $id = $daemon->acceptors->[0];
  ok !!Mojo::IOLoop->acceptor($id), 'acceptor has been added';
  undef $daemon;
  ok !Mojo::IOLoop->acceptor($id), 'acceptor has been removed';
};

subtest 'Single-accept and connection limit' => sub {
  my $loop   = Mojo::IOLoop->new;
  my $daemon = Mojo::Server::Daemon->new(
    app         => $app,
    ioloop      => $loop,
    listen      => ['http://127.0.0.1?single_accept=1'],
    max_clients => 2,
    silent      => 1
  )->start;
  my $acceptor = $loop->acceptor($daemon->acceptors->[0]);
  my @accepting;
  $acceptor->on(
    accept => sub {
      my $acceptor = shift;
      $loop->next_tick(sub {
        push @accepting, $acceptor->is_accepting;
        shift->stop if @accepting == 2;
      });
    }
  );
  $loop->client({port => $acceptor->port} => sub { }) for 1 .. 2;
  $loop->start;
  ok $accepting[0],  'accepting connections';
  ok !$accepting[1], 'connection limit reached';
};

subtest 'Request limit' => sub {
  my $daemon = Mojo::Server::Daemon->new(app => $app, listen => ['http://127.0.0.1'], silent => 1)->start;
  my $port   = $daemon->ports->[0];
  is $daemon->max_requests,                  100, 'right value';
  is $daemon->max_requests(2)->max_requests, 2,   'right value';
  my $tx = $ua->get("http://127.0.0.1:$port/keep_alive/1");
  ok $tx->keep_alive, 'will be kept alive';
  is $tx->res->code, 200,         'right status';
  is $tx->res->body, 'Whatever!', 'right content';
  $tx = $ua->get("http://127.0.0.1:$port/keep_alive/1");
  ok !$tx->keep_alive, 'will not be kept alive';
  is $tx->res->code, 200,         'right status';
  is $tx->res->body, 'Whatever!', 'right content';
};

subtest 'File descriptor' => sub {
  my $listen = IO::Socket::INET->new(Listen => 5, LocalAddr => '127.0.0.1');
  my $fd     = fileno $listen;
  my $daemon = Mojo::Server::Daemon->new(app => $app, listen => ["http://127.0.0.1?fd=$fd"], silent => 1)->start;
  my $port   = $listen->sockport;
  is $daemon->ports->[0], $port, 'same port';
  my $tx = $ua->get("http://127.0.0.1:$port/port");
  is $tx->res->code, 200,   'right status';
  is $tx->res->body, $port, 'right content';
};

subtest 'No TLS support' => sub {
  eval { Mojo::Server::Daemon->new(listen => ['https://127.0.0.1'], silent => 1)->start };
  like $@, qr/IO::Socket::SSL/, 'right error';
};

subtest 'Abstract methods' => sub {
  eval { Mojo::Server->run };
  like $@, qr/Method "run" not implemented by subclass/, 'right error';
};

done_testing();
