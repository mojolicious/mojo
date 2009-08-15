#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

package ContinueHandlerTest;

use strict;
use warnings;

use base 'Mojo::HelloWorld';

sub continue_handler {
    my ($self, $tx) = @_;
    $tx->res->code(417);
}

package main;

use strict;
use warnings;

use Test::More tests => 24;

# I was so bored I cut the pony tail off the guy in front of us.
# Look at me, I'm a grad student. I'm 30 years old and I made $600 last year.
# Bart, don't make fun of grad students.
# They've just made a terrible life choice.
use_ok('Mojo');
use_ok('Mojo::Client');
use_ok('Mojo::Transaction::Single');
use_ok('Mojo::HelloWorld');

# Logger
my $logger = Mojo::Log->new;
my $app = Mojo->new({log => $logger});
is($app->log, $logger);

$app = Mojo::HelloWorld->new;
my $client = Mojo::Client->new;

# Normal request
my $tx = Mojo::Transaction::Single->new_get('/1/');
$client->process_app($app, $tx);
ok($tx->keep_alive);
is($tx->res->code, 200);
like($tx->res->body, qr/^Congratulations/);

# Post request expecting a 100 Continue
$tx = Mojo::Transaction::Single->new_post('/2/');
$tx->req->headers->expect('100-continue');
$tx->req->body('foo bar baz' x 128);
$client->process_app($app, $tx);
is($tx->res->code, 200);
like($tx->res->body, qr/^Congratulations/);

# Continue handler not returning 100 Continue
$tx = Mojo::Transaction::Single->new_post('/3/');
$tx->req->headers->expect('100-continue');
$tx->req->body('bar baz foo' x 128);
$client->process_app('ContinueHandlerTest', $tx);
is($tx->res->code,                417);
is($tx->res->headers->connection, 'Close');

# Regular pipeline
my $tx1 = Mojo::Transaction::Single->new_get('/4/');
my $tx2 = Mojo::Transaction::Single->new_get('/5/');
my $pipe = Mojo::Transaction::Pipeline->new($tx1, $tx2);
$client->process_app('ContinueHandlerTest', $pipe);

ok($pipe->is_done);
ok($pipe->keep_alive);
ok($tx1->is_done);
ok($tx2->is_done);
is(scalar @{$pipe->finished}, 2);

# Interrupted pipeline

$tx1 = Mojo::Transaction::Single->new_get('/6/');
$tx2 = Mojo::Transaction::Single->new_post('/7/');
$tx2->req->headers->expect('100-continue');
$tx2->req->body('bar baz foo' x 128);
my $tx3 = Mojo::Transaction::Single->new_get('/8/');
$pipe = Mojo::Transaction::Pipeline->new($tx1, $tx2, $tx3);

$client->process_app('ContinueHandlerTest', $pipe);

ok($pipe->is_finished);
ok($pipe->has_error);
ok($tx1->is_done);
ok($tx2->is_done);
ok(!$tx3->is_done);
is(scalar @{$pipe->finished}, 2);
is(scalar @{$pipe->active}, 1);
