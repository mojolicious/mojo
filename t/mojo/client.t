#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More;

plan skip_all =>
  'set TEST_CLIENT to enable this test (internet connection required!)'
  unless $ENV{TEST_CLIENT};
plan tests => 75;

# So then I said to the cop, "No, you're driving under the influence...
# of being a jerk".
use_ok('Mojo::Client');
use_ok('Mojo::IOLoop');
use_ok('Mojo::Transaction::Single');

# Make sure clients dont taint the ioloop
my $ioloop = Mojo::IOLoop->new;
my $client = Mojo::Client->new;
$client->get(
    'http://cpan.org' => sub {
        my $self = shift;
        is($self->res->code, 301);
    }
)->process;
$client = undef;
$ioloop->start;

# Fresh client
$client = Mojo::Client->new;

# Custom non keep alive request
my $tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://cpan.org');
$tx->req->headers->connection('close');
$client->process($tx);
is($tx->state,     'done');
is($tx->res->code, 301);
like($tx->res->headers->connection, qr/close/i);

# Simple request
$client->get(
    'http://cpan.org' => sub {
        my $self = shift;
        is($self->req->method, 'GET');
        is($self->req->url,    'http://cpan.org');
        is($self->res->code,   301);
    }
)->process;

# Simple request with body
$client->get(
    'http://www.apache.org' => 'Hi there!' => sub {
        my $self = shift;
        is($self->req->method,                  'GET');
        is($self->req->url,                     'http://www.apache.org');
        is($self->req->headers->content_length, 9);
        is($self->req->body,                    'Hi there!');
        is($self->res->code,                    200);
    }
)->process;

# Simple request with headers and body
$client->get(
    'http://www.apache.org' => (Expect => '100-continue') => 'Hi there!' =>
      sub {
        my $self = shift;
        is($self->req->method, 'GET');
        is($self->req->url,    'http://www.apache.org');
        is($self->req->body,   'Hi there!');
        is($self->res->code,   200);
        ok($self->tx->continued);
    }
)->process;

# Simple parallel requests with keep alive
$client->get(
    'http://google.com' => sub {
        my $self = shift;
        is($self->req->method, 'GET');
        is($self->req->url,    'http://google.com');
        is($self->res->code,   301);
    }
);
$client->get(
    'http://www.apache.org' => sub {
        my $self = shift;
        is($self->req->method,    'GET');
        is($self->req->url,       'http://www.apache.org');
        is($self->res->code,      200);
        is($self->tx->kept_alive, 1);
    }
);
$client->get(
    'http://www.google.de' => sub {
        my $self = shift;
        is($self->req->method, 'GET');
        is($self->req->url,    'http://www.google.de');
        is($self->res->code,   200);
    }
);
$client->process;

# Websocket request
$client->websocket(
    'ws://websockets.org:8787' => sub {
        my $self = shift;
        is($self->tx->is_websocket, 1);
        $self->receive_message(
            sub {
                my ($self, $message) = @_;
                is($message, 'echo: hi there!');
                $self->finish;
            }
        );
        $self->send_message('hi there!');
    }
)->process;

# Simple requests with redirect
$client->max_redirects(3);
$client->get(
    'http://www.google.com' => sub {
        my ($self, $tx, $h) = @_;
        is($tx->req->method,     'GET');
        is($tx->req->url,        'http://www.google.de/');
        is($tx->res->code,       200);
        is($h->[0]->req->method, 'GET');
        is($h->[0]->req->url,    'http://www.google.com');
        is($h->[0]->res->code,   302);
    }
)->process;
$client->max_redirects(0);

# Custom chunked request without callback
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.google.com');
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
$tx->req->url->parse('http://www.apache.org');
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
$tx->req->url->parse('http://www.apache.org');
ok(!$tx->kept_alive);
$client->process(
    $tx => sub {
        my ($self, $tx) = @_;
        ok($tx->is_done);
        ok($tx->kept_alive);
        ok($tx->local_address);
        ok($tx->local_port > 0);
        is($tx->remote_port, 80);
    }
);
ok($tx->is_done);

# Custom pipelined requests
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.apache.org');
my $tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://www.apache.org');
my $tx3 = Mojo::Transaction::Single->new;
$tx3->req->method('GET');
$tx3->req->url->parse('http://www.apache.org');
$client->process(
    ([$tx, $tx2], $tx3) => sub {
        my ($self, $tx) = @_;
        return ok($tx->is_done) unless ref $tx eq 'ARRAY';
        ok($tx->[0]->is_done);
        ok($tx->[1]->is_done);
    }
);
ok($tx2->is_done);
ok($tx3->is_done);
is($tx->res->code,  200);
is($tx2->res->code, 200);
is($tx3->res->code, 200);
like($tx2->res->content->asset->slurp, qr/Apache/);

# Custom pipelined HEAD request
$tx = Mojo::Transaction::Single->new;
$tx->req->method('HEAD');
$tx->req->url->parse('http://www.apache.org');
$tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://www.apache.org');
$client->process(
    [$tx, $tx2] => sub {
        my ($self, $p) = @_;
        ok($p->[0]->is_done);
        ok($p->[1]->is_done);
    }
);
ok($tx2->is_done);
is($tx->res->code,  200);
is($tx2->res->code, 200);
like($tx2->res->content->asset->slurp, qr/Apache/);

# Custom pipelined requests with 100 Continue
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.apache.org');
$tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://www.apache.org');
$tx2->req->headers->expect('100-continue');
$tx2->req->body('foo bar baz');
$tx3 = Mojo::Transaction::Single->new;
$tx3->req->method('GET');
$tx3->req->url->parse('http://www.apache.org');
my $tx4 = Mojo::Transaction::Single->new;
$tx4->req->method('GET');
$tx4->req->url->parse('http://www.apache.org');
$client->process([$tx, $tx2, $tx3, $tx4]);
ok($tx->is_done);
ok($tx2->is_done);
ok($tx3->is_done);
ok($tx4->is_done);
is($tx->res->code,  200);
is($tx2->res->code, 200);
is($tx2->continued, 1);
is($tx3->res->code, 200);
is($tx4->res->code, 200);
like($tx2->res->content->asset->slurp, qr/Apache/);
