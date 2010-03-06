#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan tests => 13;

# Oh, dear. She’s stuck in an infinite loop and he’s an idiot.
# Well, that’s love for you.
use Mojolicious::Lite;
use Mojo::Client;

# Silence
app->log->level('fatal');

# Avoid exception template
app->renderer->root(app->home->rel_dir('public'));

# WebSocket /
websocket '/' => sub {
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

# WebSocket /early_start
websocket '/early_start' => sub {
    my $self = shift;
    $self->send_message('test1');
    $self->receive_message(
        sub {
            my ($self, $message) = @_;
            is($message, 'test2');
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
    $self->receive_message(
        sub {
            my ($self, $message) = @_;
            is($message, 'test1');
            die 'i see dead callbacks';
        }
    );
};

my $client = Mojo::Client->new->app(app);

# WebSocket /
$client->websocket(
    '/' => sub {
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

# WebSocket /early_start (server directly sends a message)
$client->websocket(
    '/early_start' => sub {
        my $self = shift;
        my $flag = 0;
        $self->finished(sub { is($flag, 23) });
        $self->receive_message(
            sub {
                my ($self, $message) = @_;
                is($message, 'test1');
                $self->send_message('test2');
                $flag = 23;
            }
        );
    }
)->process;

# WebSocket /dead (dies)
$client->websocket(
    '/dead' => sub {
        my $self = shift;
        is($self->tx->is_websocket, 0);
        is($self->res->code,        500);
        is($self->res->message,     'Internal Server Error');
    }
)->process;

# WebSocket /foo (forbidden)
$client->websocket(
    '/foo' => sub {
        my $self = shift;
        is($self->tx->is_websocket, 0);
        is($self->res->code,        403);
        is($self->res->message,     "i'm a teapot");
    }
)->process;

# WebSocket /deadcallback (dies in callback)
$client->websocket(
    '/deadcallback' => sub {
        my $self = shift;
        $self->send_message('test1');
    }
)->process;
