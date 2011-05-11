#!/usr/bin/env perl

use strict;
use warnings;

# Disable IPv6, epoll and kqueue
BEGIN { $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1 }

use Test::More;
use Mojo::IOLoop;
plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.43 required for this test!'
  unless Mojo::IOLoop::TLS;
plan skip_all => 'Windows is too fragile for this test!'
  if Mojo::IOLoop::WINDOWS;
plan tests => 15;

# "I was a hero to broken robots 'cause I was one of them, but how can I sing
#  about being damaged if I'm not?
#  That's like Christina Aguilera singing Spanish.
#  Ooh, wait! That's it! I'll fake it!"
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => sub {
  my $self = shift;
  $self->res->headers->header('X-Works',
    $self->req->headers->header('X-Works'));
  my $rel = $self->req->url;
  my $abs = $rel->to_abs;
  $self->render_text("Hello World! $rel $abs");
};

# GET /broken_redirect
get '/broken_redirect' => sub {
  my $self = shift;
  $self->render(text => 'Redirecting!', status => 302);
  $self->res->headers->location('/');
};

# GET /proxy
get '/proxy' => sub {
  my $self = shift;
  $self->render_text($self->req->url);
};

# Websocket /test
websocket '/test' => sub {
  my $self = shift;
  my $flag = 0;
  $self->on_message(
    sub {
      my ($self, $message) = @_;
      $self->send_message("${message}test2");
      $flag = 24;
    }
  );
};

# HTTP server for testing
my $ua     = Mojo::UserAgent->new;
my $loop   = Mojo::IOLoop->singleton;
my $server = Mojo::Server::Daemon->new(app => app, ioloop => $loop);
my $port   = Mojo::IOLoop->new->generate_port;
$server->listen(["https://*:$port"]);
$server->prepare_ioloop;

# Connect proxy server for testing
my $proxy = Mojo::IOLoop->generate_port;
my $c     = {};
my $connected;
my ($read, $sent, $fail) = 0;
my $nf =
    "HTTP/1.1 404 NOT FOUND\x0d\x0a"
  . "Content-Length: 0\x0d\x0a"
  . "Connection: close\x0d\x0a\x0d\x0a";
my $ok = "HTTP/1.0 200 OK\x0d\x0aX-Something: unimportant\x0d\x0a\x0d\x0a";
$loop->listen(
  port    => $proxy,
  on_read => sub {
    my ($loop, $client, $chunk) = @_;
    if (my $server = $c->{$client}->{connection}) {
      return $loop->write($server, $chunk);
    }
    $c->{$client}->{client} = '' unless defined $c->{$client}->{client};
    $c->{$client}->{client} .= $chunk if defined $chunk;
    if ($c->{$client}->{client} =~ /\x0d?\x0a\x0d?\x0a$/) {
      my $buffer = $c->{$client}->{client};
      $c->{$client}->{client} = '';
      if ($buffer =~ /CONNECT (\S+):(\d+)?/) {
        $connected = "$1:$2";
        $fail = 1 if $2 == $port + 1;
        my $server = $loop->connect(
          address    => $1,
          port       => $fail ? $port : $2,
          on_connect => sub {
            my ($loop, $server) = @_;
            $c->{$client}->{connection} = $server;
            $loop->write($client, $fail ? $nf : $ok);
          },
          on_error => sub {
            shift->drop($client);
            delete $c->{$client};
          },
          on_read => sub {
            my ($loop, $server, $chunk) = @_;
            $read += length $chunk;
            $sent += length $chunk;
            $loop->write($client, $chunk);
          }
        );
      }
      else { $loop->drop($client) }
    }
  },
  on_error => sub {
    my ($self, $client) = @_;
    shift->drop($c->{$client}->{connection})
      if $c->{$client}->{connection};
    delete $c->{$client};
  }
);

# GET / (normal request)
my $result;
$ua->get(
  "https://localhost:$port/" => sub {
    $result = pop->success->body;
    $loop->stop;
  }
);
$loop->start;
is $result, "Hello World! / https://localhost:$port/", 'right content';

# GET /broken_redirect (broken redirect)
my $start = 0;
$ua->on_start(
  sub {
    $start++;
    pop->req->headers->header('X-Works', 'it does!');
  }
);
$result = undef;
my $works;
$ua->max_redirects(3)->get(
  "https://localhost:$port/broken_redirect" => sub {
    my $tx = pop;
    $result = $tx->success->body;
    $works  = $tx->res->headers->header('X-Works');
    $loop->stop;
  }
);
$loop->start;
is $result, "Hello World! / https://localhost:$port/", 'right content';
is $works,  'it does!',                                'right header';
is $start,  2,                                         'redirected once';
$ua->on_start(undef);

# WebSocket /test (normal websocket)
$result = undef;
$ua->websocket(
  "wss://localhost:$port/test" => sub {
    my $tx = pop;
    $tx->on_finish(sub { $loop->stop });
    $tx->on_message(
      sub {
        my ($tx, $message) = @_;
        $result = $message;
        $tx->finish;
      }
    );
    $tx->send_message('test1');
  }
);
$loop->start;
is $result, 'test1test2', 'right result';

# GET /proxy (proxy request)
$ua->https_proxy("http://localhost:$proxy");
$result = undef;
$ua->get(
  "https://localhost:$port/proxy" => sub {
    $result = pop->success->body;
    $loop->stop;
  }
);
$loop->start;
is $result, "https://localhost:$port/proxy", 'right content';

# GET /proxy (kept alive proxy request)
$result = undef;
my $kept_alive;
$ua->get(
  "https://localhost:$port/proxy" => sub {
    my $tx = pop;
    $result     = $tx->success->body;
    $kept_alive = $tx->kept_alive;
    $loop->stop;
  }
);
$loop->start;
is $result, "https://localhost:$port/proxy", 'right content';
is $kept_alive, 1, 'kept alive';

# WebSocket /test (kept alive proxy websocket)
$ua->https_proxy("http://localhost:$proxy");
$result     = undef;
$kept_alive = undef;
$ua->websocket(
  "wss://localhost:$port/test" => sub {
    my $tx = pop;
    $kept_alive = $tx->kept_alive;
    $tx->on_finish(sub { $loop->stop });
    $tx->on_message(
      sub {
        my ($tx, $message) = @_;
        $result = $message;
        $tx->finish;
      }
    );
    $tx->send_message('test1');
  }
);
$loop->start;
is $kept_alive, 1,                 'kept alive';
is $connected,  "localhost:$port", 'connected';
is $result,     'test1test2',      'right result';
ok $read > 25, 'read enough';
ok $sent > 25, 'sent enough';

# WebSocket /test (proxy websocket with bad target)
$ua->https_proxy("http://localhost:$proxy");
my $port2 = $port + 1;
my ($success, $error);
$ua->websocket(
  "wss://localhost:$port2/test" => sub {
    my $tx = pop;
    $success = $tx->success;
    $error   = $tx->error;
    $loop->stop;
  }
);
$loop->start;
is $success, undef, 'no success';
is $error, 'Proxy connection failed.', 'right message';
