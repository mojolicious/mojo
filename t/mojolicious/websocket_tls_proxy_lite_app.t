#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More;
use Mojo::IOLoop;
plan skip_all => 'IO::Socket::SSL 1.33 required for this test!'
  unless Mojo::IOLoop::TLS;
plan tests => 16;

# I was a hero to broken robots 'cause I was one of them, but how can I sing
# about being damaged if I'm not?
# That's like Christina Aguilera singing Spanish.
# Ooh, wait! That's it! I'll fake it!
use Mojo::ByteStream 'b';
use Mojo::Client;
use Mojo::Server::Daemon;
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
my $client = Mojo::Client->new;
my $loop   = $client->ioloop;
my $server = Mojo::Server::Daemon->new(app => app, ioloop => $loop);
my $port   = Mojo::IOLoop->new->generate_port;
$server->listen("https://*:$port");
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
        $c->{$client}->{client} = b unless exists $c->{$client}->{client};
        $c->{$client}->{client}->add_chunk($chunk);
        if ($c->{$client}->{client} =~ /\x0d?\x0a\x0d?\x0a$/) {
            my $buffer = $c->{$client}->{client}->empty;
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
is $client->get("https://localhost:$port/")->success->body,
  "Hello World! / https://localhost:$port/", 'right content';

# WebSocket /test (normal websocket)
my $result;
$client->websocket(
    "wss://localhost:$port/test" => sub {
        my $self = shift;
        $self->on_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->finish;
            }
        );
        $self->send_message('test1');
    }
)->start;
is $result, 'test1test2', 'right result';

# GET /proxy (proxy request)
$client->https_proxy("http://localhost:$proxy");
is $client->get("https://localhost:$port/proxy")->success->body,
  "https://localhost:$port/proxy", 'right content';

# GET /proxy (kept alive proxy request)
$client->https_proxy("http://localhost:$proxy");
my $tx = $client->build_tx(GET => "https://localhost:$port/proxy");
$client->start($tx);
is $tx->success->body, "https://localhost:$port/proxy", 'right content';
is $tx->kept_alive, 1, 'kept alive';

# WebSocket /test (kept alive proxy websocket)
$client->https_proxy("http://localhost:$proxy");
$result = undef;
my $kept_alive;
$client->websocket(
    "wss://localhost:$port/test" => sub {
        my $self = shift;
        $kept_alive = $self->tx->kept_alive;
        $self->on_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->finish;
            }
        );
        $self->send_message('test1');
    }
)->start;
is $kept_alive, 1,                 'kept alive';
is $connected,  "localhost:$port", 'connected';
is $result,     'test1test2',      'right result';
ok $read > 25, 'read enough';
ok $sent > 25, 'sent enough';

# WebSocket /test (proxy websocket)
$client->https_proxy("http://localhost:$proxy");
($connected, $result, $read, $sent) = undef;
$client->websocket(
    "wss://localhost:$port/test" => sub {
        my $self = shift;
        $self->on_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->finish;
            }
        );
        $self->send_message('test1');
    }
)->start;
is $connected, "localhost:$port", 'connected';
is $result,    'test1test2',      'right result';
ok $read > 25, 'read enough';
ok $sent > 25, 'sent enough';

# WebSocket /test (proxy websocket with bad target)
$client->https_proxy("http://localhost:$proxy");
my $port2 = $port + 1;
my ($success, $error);
$client->websocket(
    "wss://localhost:$port2/test" => sub {
        my ($self, $tx) = @_;
        $success = $tx->success;
        $error   = $tx->error;
    }
)->start;
is $success, undef, 'no success';
is $error, 'Proxy connection failed.', 'right message';
