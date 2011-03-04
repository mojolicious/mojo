#!/usr/bin/env perl

use strict;
use warnings;

# Disable IPv6, epoll and kqueue
BEGIN { $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1 }

use Test::More;
plan skip_all => 'Windows is too fragile for this test!'
  if $^O eq 'MSWin32' || $^O =~ /cygwin/;
plan tests => 81;

use_ok 'Mojo::Client';

# "The strong must protect the sweet."
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => {text => 'works'};

# Proxy detection
my $client  = Mojo::Client->new;
my $backup  = $ENV{HTTP_PROXY} || '';
my $backup2 = $ENV{HTTPS_PROXY} || '';
my $backup3 = $ENV{NO_PROXY} || '';
my $backup4 = $ENV{http_proxy} || '';
my $backup5 = $ENV{https_proxy} || '';
my $backup6 = $ENV{no_proxy} || '';
$ENV{HTTP_PROXY}  = 'http://127.0.0.1';
$ENV{HTTPS_PROXY} = 'http://127.0.0.1:8080';
$ENV{NO_PROXY}    = 'mojolicio.us';
$client->detect_proxy;
is $client->http_proxy,  'http://127.0.0.1',      'right proxy';
is $client->https_proxy, 'http://127.0.0.1:8080', 'right proxy';
$client->http_proxy(undef);
$client->https_proxy(undef);
is $client->http_proxy,  undef, 'right proxy';
is $client->https_proxy, undef, 'right proxy';
is $client->need_proxy('dummy.mojolicio.us'), undef, 'no proxy needed';
is $client->need_proxy('icio.us'),            1,     'proxy needed';
is $client->need_proxy('localhost'),          1,     'proxy needed';
$ENV{HTTP_PROXY}  = undef;
$ENV{HTTPS_PROXY} = undef;
$ENV{NO_PROXY}    = undef;
$ENV{http_proxy}  = 'proxy.kraih.com';
$ENV{https_proxy} = 'tunnel.kraih.com';
$ENV{no_proxy}    = 'localhost,localdomain,foo.com,kraih.com';
$client->detect_proxy;
my $client2 = $client->clone;
is $client2->http_proxy,  'proxy.kraih.com',  'right proxy';
is $client2->https_proxy, 'tunnel.kraih.com', 'right proxy';
is $client2->need_proxy('dummy.mojolicio.us'),    1,     'proxy needed';
is $client2->need_proxy('icio.us'),               1,     'proxy needed';
is $client2->need_proxy('localhost'),             undef, 'proxy needed';
is $client2->need_proxy('localhost.localdomain'), undef, 'no proxy needed';
is $client2->need_proxy('foo.com'),               undef, 'no proxy needed';
is $client2->need_proxy('kraih.com'),             undef, 'no proxy needed';
is $client2->need_proxy('www.kraih.com'),         undef, 'no proxy needed';
is $client2->need_proxy('www.kraih.com.com'),     1,     'proxy needed';
$ENV{HTTP_PROXY}  = $backup;
$ENV{HTTPS_PROXY} = $backup2;
$ENV{NO_PROXY}    = $backup3;
$ENV{http_proxy}  = $backup4;
$ENV{https_proxy} = $backup5;
$ENV{no_proxy}    = $backup6;

# Missing callback
$client = Mojo::Client->new;
eval { $client->managed(0)->get('/') };
like $@, qr/^Unmanaged client requests require a callback/, 'right error';

# Cloning
$client = Mojo::Client->new;
$client->on_start(sub {23});
$client->cert('/cert');
$client->key('/key');
$client->http_proxy('http://127.0.0.1:3000');
$client->https_proxy('http://127.0.0.1:4000');
$client->no_proxy('127.0.0.1');
$client->user_agent('Trololo');
$client->keep_alive_timeout(23);
$client->max_connections(13);
$client->max_redirects(7);
$client->websocket_timeout(333);
$client2 = $client->clone;
is $client2->on_start,           $client->on_start,           'right value';
is $client2->cert,               $client->cert,               'right value';
is $client2->key,                $client->key,                'right value';
is $client2->http_proxy,         $client->http_proxy,         'right value';
is $client2->https_proxy,        $client->https_proxy,        'right value';
is $client2->no_proxy,           $client->no_proxy,           'right value';
is $client2->user_agent,         $client->user_agent,         'right value';
is $client2->cookie_jar,         $client->cookie_jar,         'right value';
is $client2->keep_alive_timeout, $client->keep_alive_timeout, 'right value';
is $client2->max_connections,    $client->max_connections,    'right value';
is $client2->max_redirects,      $client->max_redirects,      'right value';
is $client2->websocket_timeout,  $client->websocket_timeout,  'right value';

# Fresh client
$client = Mojo::Client->singleton->app(app);

# Server
my $port   = $client->ioloop->generate_port;
my $buffer = {};
my $last;
my $id = $client->ioloop->listen(
  port      => $port,
  on_accept => sub {
    my ($loop, $id) = @_;
    $last = $id;
    $buffer->{$id} = '';
  },
  on_read => sub {
    my ($loop, $id, $chunk) = @_;
    $buffer->{$id} .= $chunk;
    if (index $buffer->{$id}, "\x0d\x0a\x0d\x0a") {
      delete $buffer->{$id};
      $loop->write($id => "HTTP/1.1 200 OK\x0d\x0a"
          . "Connection: keep-alive\x0d\x0a"
          . "Content-Length: 6\x0d\x0a\x0d\x0aworks!");
    }
  },
  on_error => sub {
    my ($self, $id) = @_;
    delete $buffer->{$id};
  }
);

# Wonky server (missing Content-Length header)
my $port2   = $client->ioloop->generate_port;
my $buffer2 = {};
$client->ioloop->listen(
  port      => $port2,
  on_accept => sub {
    my ($loop, $id) = @_;
    $buffer2->{$id} = '';
  },
  on_read => sub {
    my ($loop, $id, $chunk) = @_;
    $buffer2->{$id} .= $chunk;
    if (index($buffer2->{$id}, "\x0d\x0a\x0d\x0a") >= 0) {
      delete $buffer2->{$id};
      $loop->write(
        $id => "HTTP/1.1 200 OK\x0d\x0a"
          . "Content-Type: text/plain\x0d\x0a\x0d\x0aworks too!",
        sub { shift->drop(shift) }
      );
    }
  },
  on_error => sub {
    my ($self, $id) = @_;
    delete $buffer2->{$id};
  }
);

# GET /
my $tx = $client->get('/');
ok $tx->success, 'successful';
is $tx->res->code, 200,     'right status';
is $tx->res->body, 'works', 'right content';

# GET / (custom connection)
my ($success, $code, $body);
$client->ioloop->connect(
  address    => 'localhost',
  port       => $port,
  on_connect => sub {
    my ($loop, $id) = @_;
    my $tx = $client->build_tx(GET => "http://mojolicio.us:$port/");
    $tx->connection($id);
    $client->start(
      $tx => sub {
        my $self = shift;
        $self->ioloop->drop($id);
        $success = $self->tx->success;
        $code    = $self->res->code;
        $body    = $self->res->body;
      }
    );
  }
);
$client->ioloop->start;
ok $success, 'successful';
is $code,    200, 'right status';
is $body,    'works!', 'right content';

# GET / (missing Content-Lengt header)
$tx = $client->get("http://localhost:$port2/");
ok $tx->success, 'successful';
ok !$tx->error, 'no error';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->keep_alive, 1,     'keep connection alive';
is $tx->res->code, 200,          'right status';
is $tx->res->body, 'works too!', 'right content';

# GET / (mock server)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET / (mock server again)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, 1, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Close connection (bypassing safety net)
$client->ioloop->_drop_immediately($last);

# GET / (mock server closed connection)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET / (mock server again)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, 1, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Close connection (bypassing safety net)
$client->ioloop->_drop_immediately($last);

# GET / (mock server closed connection)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET / (mock server again)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, 1, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Taint connection
$client->ioloop->write($last => 'broken!');
sleep 1;

# GET / (mock server tainted connection)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET / (mock server again)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, 1, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Taint connection
$client->ioloop->write($last => 'broken!');
sleep 1;

# GET / (mock server tainted connection)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Nested keep alive
my @kept_alive;
$client = $client->clone->app(app)->managed(0);
$client->get(
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
            $self->ioloop->stop;
          }
        );
      }
    );
  }
);
$client->ioloop->start;
is_deeply \@kept_alive, [undef, 1, 1], 'connections kept alive';

# Simple nested keep alive with timers
@kept_alive = ();
my $loop = $client->ioloop;
$client->get(
  '/',
  sub {
    push @kept_alive, pop->kept_alive;
    $loop->timer(
      '0.25' => sub {
        $client->get(
          '/',
          sub {
            push @kept_alive, pop->kept_alive;
            $loop->timer('0.25' => sub { $loop->stop });
          }
        );
      }
    );
  }
);
$loop->start;
is_deeply \@kept_alive, [1, 1], 'connections kept alive';
