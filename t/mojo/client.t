#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More;

plan skip_all =>
  'set TEST_CLIENT to enable this test (internet connection required!)'
  unless $ENV{TEST_CLIENT};
plan tests => 63;

# So then I said to the cop, "No, you're driving under the influence...
# of being a jerk".
use_ok('Mojo::Client');
use_ok('Mojo::IOLoop');
use_ok('Mojo::Transaction::Pipeline');
use_ok('Mojo::Transaction::Single');

# Make sure clients dont taint the ioloop
my $ioloop = Mojo::IOLoop->new;
my $client = Mojo::Client->new;
$client->get(
    'http://kraih.com' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code, 200);
    }
)->process;
$client = undef;
$ioloop->start;

# Fresh client
$client = Mojo::Client->new;

# Custom non keep alive request
my $tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://kraih.com');
$tx->req->headers->connection('close');
$client->process($tx);
is($tx->state,     'done');
is($tx->res->code, 200);
like($tx->res->headers->connection, qr/close/i);

# Simple request
$client->get(
    'http://kraih.com' => sub {
        my ($self, $tx) = @_;
        is($tx->req->method, 'GET');
        is($tx->req->url,    'http://kraih.com');
        is($tx->res->code,   200);
    }
)->process;

# Simple parallel requests with keep alive
$client->get(
    'http://labs.kraih.com' => sub {
        my ($self, $tx) = @_;
        is($tx->req->method, 'GET');
        is($tx->req->url,    'http://labs.kraih.com');
        is($tx->res->code,   301);
    }
);
$client->get(
    'http://kraih.com' => sub {
        my ($self, $tx) = @_;
        is($tx->req->method, 'GET');
        is($tx->req->url,    'http://kraih.com');
        is($tx->res->code,   200);
        is($tx->kept_alive,  1);
    }
);
$client->get(
    'http://mojolicious.org' => sub {
        my ($self, $tx) = @_;
        is($tx->req->method, 'GET');
        is($tx->req->url,    'http://mojolicious.org');
        is($tx->res->code,   200);
    }
);
$client->process;

# Simple requests with redirect
$client->max_redirects(3);
$client->get(
    'http://labs.kraih.com' => sub {
        my ($self, $tx, $h) = @_;
        is($tx->req->method,     'GET');
        is($tx->req->url,        'http://labs.kraih.com/blog/');
        is($tx->res->code,       200);
        is($h->[0]->req->method, 'GET');
        is($h->[0]->req->url,    'http://labs.kraih.com');
        is($h->[0]->res->code,   301);
    }
)->process;
$client->max_redirects(0);

# Custom chunked request without callback
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://google.com');
$tx->req->headers->transfer_encoding('chunked');
my $counter = 1;
my $chunked = Mojo::Filter::Chunked->new;
$tx->req->body(
    sub {
        my $self  = shift;
        my $chunk = '';
        $chunk = "hello world!"      if $counter == 1;
        $chunk = "hello world2!\n\n" if $counter == 2;
        $counter++;
        return $chunked->build($chunk);
    }
);
$client->process($tx);
ok($tx->is_done);

# Custom requests with keep alive
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://labs.kraih.com');
ok(!$tx->kept_alive);
$client->queue(
    $tx => sub {
        my ($self, $tx) = @_;
        ok($tx->is_done);
        ok($tx->kept_alive);
    }
);
$client->process;
ok($tx->is_done);
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://labs.kraih.com');
ok(!$tx->kept_alive);
$client->process(
    $tx => sub {
        my ($self, $tx) = @_;
        ok($tx->is_done);
        ok($tx->kept_alive);
        ok($tx->local_address);
        ok($tx->local_port > 0);
        is($tx->remote_address, '88.198.25.164');
        is($tx->remote_port,    80);
    }
);
ok($tx->is_done);

# Custom pipelined requests
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://labs.kraih.com');
my $tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://mojolicious.org');
my $tx3 = Mojo::Transaction::Single->new;
$tx3->req->method('GET');
$tx3->req->url->parse('http://kraih.com');
$client->process(
    (Mojo::Transaction::Pipeline->new($tx, $tx2), $tx3) => sub {
        my ($self, $tx) = @_;
        ok($tx->is_done);
    }
);
ok($tx2->is_done);
ok($tx3->is_done);
is($tx->res->code,  301);
is($tx2->res->code, 200);
is($tx3->res->code, 200);
like($tx2->res->content->asset->slurp, qr/Mojolicious/);

# Custom pipelined HEAD request
$tx = Mojo::Transaction::Single->new;
$tx->req->method('HEAD');
$tx->req->url->parse('http://labs.kraih.com/blog/');
$tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://mojolicious.org');
$client->process(
    Mojo::Transaction::Pipeline->new($tx, $tx2) => sub {
        my ($self, $tx) = @_;
        ok($tx->is_done);
    }
);
ok($tx2->is_done);
is($tx->res->code,  200);
is($tx2->res->code, 200);
like($tx2->res->content->asset->slurp, qr/Mojolicious/);

# Custom pipelined requests with 100 Continue
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://labs.kraih.com');
$tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://mojolicious.org');
$tx2->req->headers->expect('100-continue');
$tx2->req->body('foo bar baz');
$tx3 = Mojo::Transaction::Single->new;
$tx3->req->method('GET');
$tx3->req->url->parse('http://labs.kraih.com/blog/');
my $tx4 = Mojo::Transaction::Single->new;
$tx4->req->method('GET');
$tx4->req->url->parse('http://labs.kraih.com/blog');
$client->process(Mojo::Transaction::Pipeline->new($tx, $tx2, $tx3, $tx4));
ok($tx->is_done);
ok($tx2->is_done);
ok($tx3->is_done);
ok($tx4->is_done);
is($tx->res->code,  301);
is($tx2->res->code, 200);
is($tx2->continued, 1);
is($tx3->res->code, 200);
is($tx4->res->code, 301);
like($tx2->res->content->asset->slurp, qr/Mojolicious/);
