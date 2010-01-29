#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan tests => 2;

# Oh, dear. She’s stuck in an infinite loop and he’s an idiot.
# Well, that’s love for you.
use Mojolicious::Lite;
use Mojo::Client;

# Silence
app->log->level('error');

# WebSocket /
websocket '/' => sub {
    my $self = shift;
    $self->receive_message(
        sub {
            my ($self, $message) = @_;
            is($message, 'test1');
            $self->send_message('test2');
        }
    );
};

# New client
my $client = Mojo::Client->new->app(app);

# WebSocket /
$client->websocket(
    '/',
    sub {
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
