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
plan tests => 10;

# Oh, dear. She’s stuck in an infinite loop and he’s an idiot.
# Well, that’s love for you.
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
$client->ioloop->one_tick(1);
$client->ioloop->one_tick(1);
is($result, 'test1test2');
is($flag,   24);

# WebSocket /early_start (server directly sends a message)
($flag, $result) = undef;
$client->websocket(
    '/early_start' => sub {
        my $self = shift;
        $self->finished(sub { $flag += 5 });
        $self->receive_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->send_message('test3');
                $flag = 18;
            }
        );
    }
)->process;
is($flag,   23);
is($result, 'test3test2');

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
is($websocket, 0);
is($code,      500);
is($message,   'Internal Server Error');

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
is($websocket, 0);
is($code,      403);
is($message,   "i'm a teapot");

# WebSocket /deadcallback (dies in callback)
$client->websocket(
    '/deadcallback' => sub {
        my $self = shift;
        $self->send_message('test1');
    }
)->process;
