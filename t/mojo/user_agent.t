#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 71;

# "The strong must protect the sweet."
use Mojo::IOLoop;
use Mojolicious::Lite;

use_ok 'Mojo::UserAgent';

# Silence
app->log->level('fatal');

# GET /
get '/' => {text => 'works'};

# GET /timeout
my $timeout = undef;
get '/timeout' => sub {
  my $self = shift;
  Mojo::IOLoop->connection_timeout($self->tx->connection => '0.5');
  $self->on(finish => sub { $timeout = 1 });
  $self->render_later;
};

# GET /no_length
get '/no_length' => sub {
  my $self = shift;
  $self->finish('works too!');
  $self->rendered(200);
};

# GET /last
my $last;
get '/last' => sub {
  my $self = shift;
  $last = $self->tx->connection;
  $self->render(text => 'works!');
};

# Proxy detection
my $ua      = Mojo::UserAgent->new;
my $backup  = $ENV{HTTP_PROXY} || '';
my $backup2 = $ENV{HTTPS_PROXY} || '';
my $backup3 = $ENV{NO_PROXY} || '';
my $backup4 = $ENV{http_proxy} || '';
my $backup5 = $ENV{https_proxy} || '';
my $backup6 = $ENV{no_proxy} || '';
$ENV{HTTP_PROXY}  = 'http://127.0.0.1';
$ENV{HTTPS_PROXY} = 'http://127.0.0.1:8080';
$ENV{NO_PROXY}    = 'mojolicio.us';
$ua->detect_proxy;
is $ua->http_proxy,  'http://127.0.0.1',      'right proxy';
is $ua->https_proxy, 'http://127.0.0.1:8080', 'right proxy';
$ua->http_proxy(undef);
$ua->https_proxy(undef);
is $ua->http_proxy,  undef, 'right proxy';
is $ua->https_proxy, undef, 'right proxy';
ok !$ua->need_proxy('dummy.mojolicio.us'), 'no proxy needed';
ok $ua->need_proxy('icio.us'),   'proxy needed';
ok $ua->need_proxy('localhost'), 'proxy needed';
$ENV{HTTP_PROXY}  = undef;
$ENV{HTTPS_PROXY} = undef;
$ENV{NO_PROXY}    = undef;
$ENV{http_proxy}  = 'proxy.kraih.com';
$ENV{https_proxy} = 'tunnel.kraih.com';
$ENV{no_proxy}    = 'localhost,localdomain,foo.com,kraih.com';
$ua->detect_proxy;
is $ua->http_proxy,  'proxy.kraih.com',  'right proxy';
is $ua->https_proxy, 'tunnel.kraih.com', 'right proxy';
ok $ua->need_proxy('dummy.mojolicio.us'), 'proxy needed';
ok $ua->need_proxy('icio.us'),            'proxy needed';
ok !$ua->need_proxy('localhost'),             'proxy needed';
ok !$ua->need_proxy('localhost.localdomain'), 'no proxy needed';
ok !$ua->need_proxy('foo.com'),               'no proxy needed';
ok !$ua->need_proxy('kraih.com'),             'no proxy needed';
ok !$ua->need_proxy('www.kraih.com'),         'no proxy needed';
ok $ua->need_proxy('www.kraih.com.com'), 'proxy needed';
$ENV{HTTP_PROXY}  = $backup;
$ENV{HTTPS_PROXY} = $backup2;
$ENV{NO_PROXY}    = $backup3;
$ENV{http_proxy}  = $backup4;
$ENV{https_proxy} = $backup5;
$ENV{no_proxy}    = $backup6;

# User agent
$ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);

# GET / (non-blocking)
my ($success, $code, $body);
$ua->get(
  '/' => sub {
    my $tx = pop;
    $success = $tx->success;
    $code    = $tx->res->code;
    $body    = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $success, 'successful';
is $code,    200, 'right status';
is $body,    'works', 'right content';

# GET /last (custom connection)
($success, $code, $body) = undef;
Mojo::IOLoop->connect(
  address    => 'localhost',
  port       => $ua->test_server->port,
  on_connect => sub {
    my ($loop, $id) = @_;
    my $tx = $ua->build_tx(GET => 'http://mojolicio.us/last');
    $tx->connection($id);
    $ua->start(
      $tx => sub {
        my $tx = pop;
        $success = $tx->success;
        $code    = $tx->res->code;
        $body    = $tx->res->body;
        Mojo::IOLoop->stop;
      }
    );
  }
);
Mojo::IOLoop->start;
ok $success, 'successful';
is $code,    200, 'right status';
is $body,    'works!', 'right content';

# GET /last (blocking)
my $tx = $ua->get('/last');
ok $tx->success, 'successful';
ok !$tx->kept_alive, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET /last (again)
$tx = $ua->get('/last');
ok $tx->success,    'successful';
ok $tx->kept_alive, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Close connection
Mojo::IOLoop->stream($last)->emit('close');
Mojo::IOLoop->one_tick while Mojo::IOLoop->stream($last);

# GET /last (closed connection)
$tx = $ua->get('/last');
ok $tx->success, 'successful';
ok !$tx->kept_alive, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET /last (again)
$tx = $ua->get('/last');
ok $tx->success,    'successful';
ok $tx->kept_alive, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Close connection
Mojo::IOLoop->stream($last)->emit('close');
Mojo::IOLoop->one_tick while Mojo::IOLoop->stream($last);

# GET /last (closed connection)
$tx = $ua->get('/last');
ok $tx->success, 'successful';
ok !$tx->kept_alive, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET /last (again)
$tx = $ua->get('/last');
ok $tx->success,    'successful';
ok $tx->kept_alive, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET /
$tx = $ua->get('/');
ok $tx->success, 'successful';
is $tx->res->code, 200,     'right status';
is $tx->res->body, 'works', 'right content';

# GET / (callbacks)
my $finished;
$tx = $ua->build_tx(GET => '/');
$ua->on(
  start => sub {
    my ($self, $tx) = @_;
    $tx->on(finish => sub { $finished++ });
  }
);
$tx = $ua->start($tx);
$ua->unsubscribe('start');
ok $tx->success, 'successful';
is $finished, 1, 'finish event has been emitted';
is $tx->res->code, 200,     'right status';
is $tx->res->body, 'works', 'right content';

# GET /no_length (missing Content-Length header)
$tx = $ua->get('/no_length');
ok $tx->success, 'successful';
ok !$tx->error, 'no error';
ok $tx->kept_alive, 'kept connection alive';
ok !$tx->keep_alive, 'keep connection not alive';
is $tx->res->code, 200,          'right status';
is $tx->res->body, 'works too!', 'right content';

# GET / (built-in server)
$tx = $ua->get('/');
ok $tx->success, 'successful';
is $tx->res->code, 200,     'right status';
is $tx->res->body, 'works', 'right content';

# GET / (built-in server times out)
$tx = $ua->get('/timeout');
ok !$tx->success, 'not successful';
is $tx->error, 'Premature connection close.', 'right error';
is $timeout, 1, 'finish event has been emitted';

# Nested keep alive
my @kept_alive;
$ua->get(
  '/',
  sub {
    my ($self, $tx) = @_;
    push @kept_alive, $tx->kept_alive;
    $self->get(
      '/',
      sub {
        my ($self, $tx) = @_;
        push @kept_alive, $tx->kept_alive;
        $self->get(
          '/',
          sub {
            my ($self, $tx) = @_;
            push @kept_alive, $tx->kept_alive;
            Mojo::IOLoop->stop;
          }
        );
      }
    );
  }
);
Mojo::IOLoop->start;
is_deeply \@kept_alive, [undef, 1, 1], 'connections kept alive';

# Simple nested keep alive with timers
@kept_alive = ();
$ua->get(
  '/',
  sub {
    push @kept_alive, pop->kept_alive;
    Mojo::IOLoop->timer(
      '0.25' => sub {
        $ua->get(
          '/',
          sub {
            push @kept_alive, pop->kept_alive;
            Mojo::IOLoop->timer('0.25' => sub { Mojo::IOLoop->stop });
          }
        );
      }
    );
  }
);
Mojo::IOLoop->start;
is_deeply \@kept_alive, [1, 1], 'connections kept alive';

# Premature connection close
my $port = Mojo::IOLoop->generate_port;
my $id   = Mojo::IOLoop->listen(
  port      => $port,
  on_accept => sub { shift->drop(shift) }
);
$tx = $ua->get("http://localhost:$port/");
ok !$tx->success, 'not successful';
is $tx->error, 'Premature connection close.', 'right error';
