#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan tests => 12;

# Oh, dear. She’s stuck in an infinite loop and he’s an idiot.
# Well, that’s love for you.
use IO::Socket::INET;
use Mojolicious::Lite;
use Mojo::Client;

# Silence
app->log->level('fatal');

# Avoid exception template
app->renderer->root(app->home->rel_dir('public'));

# WebSocket /
my $flag;
websocket '/' => sub {
    my $self = shift;
    $self->finished(sub { $flag += 4 });
    $self->receive_message(
        sub {
            my ($self, $message) = @_;
            $self->send_message("${message}test2");
            $flag = 20;
        }
    );
};

# WebSocket /socket
websocket '/socket' => sub {
    my $self = shift;
    $self->send_message(scalar $self->req->headers->host);
    $self->finish;
};

# WebSocket /early_start
websocket '/early_start' => sub {
    my $self = shift;
    $self->send_message('test1');
    $self->receive_message(
        sub {
            my ($self, $message) = @_;
            $self->send_message("${message}test2");
            $self->finish;
        }
    );
};

# WebSocket /dead
websocket '/dead' => sub { die 'i see dead processes' };

# WebSocket /foo
websocket '/foo' => sub { shift->res->code('403')->message("i'm a teapot") };

# WebSocket /deadcallback
websocket '/deadcallback' => sub {
    my $self = shift;
    $self->receive_message(sub { die 'i see dead callbacks' });
};

my $client = Mojo::Client->new->app(app);

# WebSocket /
my $result;
$client->websocket(
    '/' => sub {
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

# WebSocket /socket (using an already prepared socket)
my $peer  = $client->test_server;
my $local = $client->ioloop->generate_port;
$result = undef;
my $tx     = $client->build_websocket_tx("ws://lalala/socket");
my $socket = IO::Socket::INET->new(
    PeerAddr  => 'localhost',
    PeerPort  => $peer,
    LocalPort => $local
);
$tx->connection($socket);
my $port;
$client->process(
    $tx => sub {
        my $self = shift;
        $self->receive_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->finish;
            }
        );
        $port = $self->ioloop->local_info($self->tx->connection)->{port};
    }
)->process;
is($result, 'lalala', 'right result');
is($port,   $local,   'right local port');

# WebSocket /early_start (server directly sends a message)
my $flag2;
$result = undef;
$client->websocket(
    '/early_start' => sub {
        my $self = shift;
        $self->finished(sub { $flag2 += 5 });
        $self->receive_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->send_message('test3');
                $flag2 = 18;
            }
        );
    }
)->process;
is($result, 'test3test2', 'right result');
is($flag2,  23,           'finished callback');

# WebSocket /dead (dies)
my ($websocket, $code, $message);
$client->websocket(
    '/dead' => sub {
        my $self = shift;
        $websocket = $self->tx->is_websocket;
        $code      = $self->res->code;
        $message   = $self->res->message;
    }
)->process;
is($websocket, 0,                       'no websocket');
is($code,      500,                     'right status');
is($message,   'Internal Server Error', 'right message');

# WebSocket /foo (forbidden)
($websocket, $code, $message) = undef;
$client->websocket(
    '/foo' => sub {
        my $self = shift;
        $websocket = $self->tx->is_websocket;
        $code      = $self->res->code;
        $message   = $self->res->message;
    }
)->process;
is($websocket, 0,              'no websocket');
is($code,      403,            'right status');
is($message,   "i'm a teapot", 'right message');

# WebSocket /deadcallback (dies in callback)
$client->websocket(
    '/deadcallback' => sub {
        my $self = shift;
        $self->send_message('test1');
    }
)->process;

# Server side "finished" callback
is($flag, 24, 'finished callback');
