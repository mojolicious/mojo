#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless my $proxy = Mojo::IOLoop->new->generate_port;
plan tests => 9;

# Your mistletoe is no match for my *tow* missile.
use Mojo::ByteStream 'b';
use Mojo::Client;
use Mojo::Server::Daemon;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => sub { shift->render_text('Hello World!') };

# GET /proxy
get '/proxy' => sub {
    my $self = shift;
    $self->render_text($self->req->url);
};

# Websocket /test
websocket '/test' => sub {
    my $self = shift;
    my $flag = 0;
    $self->receive_message(
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
$server->listen("http://*:$port");
$server->prepare_ioloop;

# Connect proxy server for testing
my $c = {};
my $connected;
my ($read, $sent, $fail) = 0;
my $nf = "HTTP/1.1 404 NOT FOUND\x0d\x0aConnection: close\x0d\x0a\x0d\x0a";
my $ok = "HTTP/1.1 200 OK\x0d\x0aConnection: keep-alive\x0d\x0a\x0d\x0a";
$loop->listen(
    port    => $proxy,
    read_cb => sub {
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
                    connect_cb => sub {
                        my ($loop, $server) = @_;
                        $c->{$client}->{connection} = $server;
                        $loop->write($client, $fail ? $nf : $ok);
                    },
                    error_cb => sub {
                        shift->drop($client);
                        delete $c->{$client};
                    },
                    read_cb => sub {
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
    error_cb => sub {
        my ($self, $client) = @_;
        shift->drop($c->{$client}->{connection})
          if $c->{$client}->{connection};
        delete $c->{$client};
    }
);

# GET / (normal request)
is($client->get("http://localhost:$port/")->success->body,
    'Hello World!', 'right content');

# WebSocket /test (normal websocket)
my $result;
$client->websocket(
    "ws://localhost:$port/test" => sub {
        my $self = shift;
        $self->receive_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->finish;
            }
        );
        $self->send_message('test1');
    }
)->process;
is($result, 'test1test2', 'right result');

# GET http://kraih.com/proxy (proxy request)
$client->http_proxy("http://localhost:$port");
is($client->get("http://kraih.com/proxy")->success->body,
    'http://kraih.com/proxy', 'right content');

# WebSocket /test (proxy websocket)
$client->http_proxy("http://localhost:$proxy");
$result = undef;
$client->websocket(
    "ws://localhost:$port/test" => sub {
        my $self = shift;
        $self->receive_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->finish;
            }
        );
        $self->send_message('test1');
    }
)->process;
is($connected, "localhost:$port", 'connected');
is($result,    'test1test2',      'right result');
ok($read > 25, 'read enough');
ok($sent > 25, 'sent enough');

# WebSocket /test (proxy websocket with bad target)
$client->http_proxy("http://localhost:$proxy");
my $port2 = $port + 1;
my ($success, $error);
$client->websocket(
    "ws://localhost:$port2/test" => sub {
        my ($self, $tx) = @_;
        $success = $tx->success;
        $error   = $tx->error;
    }
)->process;
is($success, undef, 'no success');
is($error, 'Proxy connection failed.', 'right message');
