#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless my $proxy = Mojo::IOLoop->new->generate_port;
plan tests => 5;

# Your mistletoe is no match for my *tow* missile.
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
    $self->finished(sub { is($flag, 24) });
    $self->receive_message(
        sub {
            my ($self, $message) = @_;
            is($message, 'test1');
            $self->send_message('test2');
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
$loop->listen(
    port    => $proxy,
    read_cb => sub {
        my ($loop, $client, $chunk) = @_;
        $c->{$client}->{client} ||= '';
        $c->{$client}->{client} .= $chunk;
        if (my $server = $c->{$client}->{connection}) {
            $loop->writing($server);
            return;
        }
        if ($c->{$client}->{client} =~ /\x0d?\x0a\x0d?\x0a$/) {
            my $buffer = delete $c->{$client}->{client};
            if ($buffer =~ /CONNECT (\S+):(\d+)?/) {
                my $server = $loop->connect(
                    address    => $1,
                    port       => $2 || 80,
                    connect_cb => sub {
                        my ($loop, $server) = @_;
                        $c->{$client}->{connection} = $server;
                        $c->{$client}->{server} = "HTTP/1.1 200 OK\x0d\x0a"
                          . "Connection: keep-alive\x0d\x0a\x0d\x0a";
                        $loop->writing($client);
                    },
                    error_cb => sub {
                        shift->drop($client);
                        delete $c->{$client};
                    },
                    read_cb => sub {
                        my ($loop, $server, $chunk) = @_;
                        $c->{$client}->{server} ||= '';
                        $c->{$client}->{server} .= $chunk;
                        $loop->writing($client);
                    },
                    write_cb => sub {
                        my ($loop, $server) = @_;
                        $loop->not_writing($server);
                        return delete $c->{$client}->{client};
                    }
                );
            }
            else { $loop->drop($client) }
        }
    },
    write_cb => sub {
        my ($loop, $client) = @_;
        $loop->not_writing($client);
        return delete $c->{$client}->{server};
    },
    error_cb => sub {
        my ($self, $client) = @_;
        shift->drop($c->{$client}->{connection})
          if $c->{$client}->{connection};
        delete $c->{$client};
    }
);

# GET / (normal request)
is($client->get("http://localhost:$port/")->success->body, 'Hello World!');

# WebSocket /test (normal websocket)
$client->websocket(
    "ws://localhost:$port/test" => sub {
        my $self = shift;
        $self->receive_message(
            sub {
                my ($self, $message) = @_;
                is($message, 'test2');
                $self->finish;
            }
        );
        $self->send_message('test1');
    }
)->process;

# GET http://kraih.com/proxy (proxy request)
$client->http_proxy("http://localhost:$port");
is($client->get("http://kraih.com/proxy")->success->body,
    'http://kraih.com/proxy');
