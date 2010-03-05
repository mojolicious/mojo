#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

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

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan tests => 23;

# I was so bored I cut the pony tail off the guy in front of us.
# Look at me, I'm a grad student. I'm 30 years old and I made $600 last year.
# Bart, don't make fun of grad students.
# They've just made a terrible life choice.
use_ok('Mojo');
use_ok('Mojo::Client');
use_ok('Mojo::Transaction::HTTP');
use_ok('Mojo::HelloWorld');

# Logger
my $logger = Mojo::Log->new;
my $app = Mojo->new({log => $logger});
is($app->log, $logger);

$app = Mojo::HelloWorld->new;
my $client = Mojo::Client->new->app($app);

# Normal request
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/1/');
$client->process($tx);
ok($tx->keep_alive);
is($tx->res->code, 200);
like($tx->res->body, qr/^Congratulations/);

# Post request expecting a 100 Continue
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/2/');
$tx->req->headers->expect('100-continue');
$tx->req->body('foo bar baz' x 128);
$client->process($tx);
is($tx->res->code, 200);
like($tx->res->body, qr/^Congratulations/);

$client = Mojo::Client->new->app('ContinueHandlerTest');

# Continue handler not returning 100 Continue
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/3/');
$tx->req->headers->expect('100-continue');
$tx->req->body('bar baz foo' x 128);
$client->process($tx);
ok(defined $tx->connection);
is($tx->res->code,                417);
is($tx->res->headers->connection, 'Close');

# Regular pipeline
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/4/');
my $tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('/5/');
$client->process([$tx, $tx2]);
ok(defined $tx->connection);
ok(defined $tx2->connection);
ok($tx->is_done);
ok($tx2->is_done);

# Interrupted pipeline
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/6/');
$tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('POST');
$tx2->req->url->parse('/7/');
$tx2->req->headers->expect('100-continue');
$tx2->req->body('bar baz foo' x 128);
my $tx3 = Mojo::Transaction::HTTP->new;
$tx3->req->method('GET');
$tx3->req->url->parse('/8/');
$client->process([$tx, $tx2, $tx3]);
ok($tx->is_finished);
ok(!$tx->has_error);
ok($tx2->is_finished);
ok(!$tx2->has_error);
ok($tx3->is_finished);
ok($tx3->has_error);
