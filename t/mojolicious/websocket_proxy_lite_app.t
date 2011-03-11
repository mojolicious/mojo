#!/usr/bin/env perl

use strict;
use warnings;

# Disable IPv6, epoll and kqueue
BEGIN { $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1 }

use Test::More tests => 9;

# "Your mistletoe is no match for my *tow* missile."
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => sub {
  my $self = shift;
  my $rel  = $self->req->url;
  my $abs  = $rel->to_abs;
  $self->render_text("Hello World! $rel $abs");
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
$server->listen(["http://*:$port"]);
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
my $ok = "HTTP/1.1 200 OK\x0d\x0aConnection: keep-alive\x0d\x0a\x0d\x0a";
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
  "http://localhost:$port/" => sub {
    $result = pop->success->body;
    $loop->stop;
  }
);
$loop->start;
is $result, "Hello World! / http://localhost:$port/", 'right content';

# WebSocket /test (normal websocket)
$result = undef;
$ua->websocket(
  "ws://localhost:$port/test" => sub {
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

# GET http://kraih.com/proxy (proxy request)
$ua->http_proxy("http://localhost:$port");
$result = undef;
$ua->get(
  "http://kraih.com/proxy" => sub {
    $result = pop->success->body;
    $loop->stop;
  }
);
$loop->start;
is $result, 'http://kraih.com/proxy', 'right content';

# WebSocket /test (proxy websocket)
$ua->http_proxy("http://localhost:$proxy");
$result = undef;
$ua->websocket(
  "ws://localhost:$port/test" => sub {
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
is $connected, "localhost:$port", 'connected';
is $result,    'test1test2',      'right result';
ok $read > 25, 'read enough';
ok $sent > 25, 'sent enough';

# WebSocket /test (proxy websocket with bad target)
$ua->http_proxy("http://localhost:$proxy");
my $port2 = $port + 1;
my ($success, $error);
$ua->websocket(
  "ws://localhost:$port2/test" => sub {
    my $tx = pop;
    $success = $tx->success;
    $error   = $tx->error;
    $loop->stop;
  }
);
$loop->start;
is $success, undef, 'no success';
is $error, 'Proxy connection failed.', 'right message';
