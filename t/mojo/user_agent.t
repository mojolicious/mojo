#!/usr/bin/env perl

use strict;
use warnings;

# Disable IPv6, epoll and kqueue
BEGIN { $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1 }

use Test::More;
plan skip_all => 'Windows is too fragile for this test!'
  if $^O eq 'MSWin32' || $^O =~ /cygwin/;
plan tests => 68;

use_ok 'Mojo::UserAgent';

# "The strong must protect the sweet."
use Mojo::IOLoop;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => {text => 'works'};

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
is $ua->need_proxy('dummy.mojolicio.us'), undef, 'no proxy needed';
is $ua->need_proxy('icio.us'),            1,     'proxy needed';
is $ua->need_proxy('localhost'),          1,     'proxy needed';
$ENV{HTTP_PROXY}  = undef;
$ENV{HTTPS_PROXY} = undef;
$ENV{NO_PROXY}    = undef;
$ENV{http_proxy}  = 'proxy.kraih.com';
$ENV{https_proxy} = 'tunnel.kraih.com';
$ENV{no_proxy}    = 'localhost,localdomain,foo.com,kraih.com';
$ua->detect_proxy;
is $ua->http_proxy,  'proxy.kraih.com',  'right proxy';
is $ua->https_proxy, 'tunnel.kraih.com', 'right proxy';
is $ua->need_proxy('dummy.mojolicio.us'),    1,     'proxy needed';
is $ua->need_proxy('icio.us'),               1,     'proxy needed';
is $ua->need_proxy('localhost'),             undef, 'proxy needed';
is $ua->need_proxy('localhost.localdomain'), undef, 'no proxy needed';
is $ua->need_proxy('foo.com'),               undef, 'no proxy needed';
is $ua->need_proxy('kraih.com'),             undef, 'no proxy needed';
is $ua->need_proxy('www.kraih.com'),         undef, 'no proxy needed';
is $ua->need_proxy('www.kraih.com.com'),     1,     'proxy needed';
$ENV{HTTP_PROXY}  = $backup;
$ENV{HTTPS_PROXY} = $backup2;
$ENV{NO_PROXY}    = $backup3;
$ENV{http_proxy}  = $backup4;
$ENV{https_proxy} = $backup5;
$ENV{no_proxy}    = $backup6;

# User agent
$ua = Mojo::UserAgent->new(app => app);

# Server
my $port   = Mojo::IOLoop->generate_port;
my $buffer = {};
my $last;
my $id = Mojo::IOLoop->listen(
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
my $port2   = Mojo::IOLoop->generate_port;
my $buffer2 = {};
Mojo::IOLoop->listen(
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
my $tx = $ua->get('/');
ok $tx->success, 'successful';
is $tx->res->code, 200,     'right status';
is $tx->res->body, 'works', 'right content';

# GET / (custom connection)
my ($success, $code, $body);
Mojo::IOLoop->connect(
  address    => 'localhost',
  port       => $port,
  on_connect => sub {
    my ($loop, $id) = @_;
    my $tx = $ua->build_tx(GET => "http://mojolicio.us:$port/");
    $tx->connection($id);
    $ua->start(
      $tx => sub {
        my $tx = pop;
        $loop->drop($id);
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

# Fresh blocking user agent
$ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton, app => app);

# GET / (missing Content-Lengt header)
$tx = $ua->get("http://localhost:$port2/");
ok $tx->success, 'successful';
ok !$tx->error, 'no error';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->keep_alive, 1,     'keep connection alive';
is $tx->res->code, 200,          'right status';
is $tx->res->body, 'works too!', 'right content';

# GET / (mock server)
$tx = $ua->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET / (mock server again)
$tx = $ua->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, 1, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Close connection (bypassing safety net)
Mojo::IOLoop->singleton->_drop_immediately($last);

# GET / (mock server closed connection)
$tx = $ua->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET / (mock server again)
$tx = $ua->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, 1, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Close connection (bypassing safety net)
Mojo::IOLoop->singleton->_drop_immediately($last);

# GET / (mock server closed connection)
$tx = $ua->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET / (mock server again)
$tx = $ua->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, 1, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Taint connection
Mojo::IOLoop->singleton->write($last => 'broken!');
sleep 1;

# GET / (mock server tainted connection)
$tx = $ua->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET / (mock server again)
$tx = $ua->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, 1, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Taint connection
Mojo::IOLoop->singleton->write($last => 'broken!');
sleep 1;

# GET / (mock server tainted connection)
$tx = $ua->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

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
