#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More;

plan skip_all =>
  'set TEST_CLIENT to enable this test (internet connection required!)'
  unless $ENV{TEST_CLIENT};
plan tests => 81;

# So then I said to the cop, "No, you're driving under the influence...
# of being a jerk".
use_ok('Mojo::Client');
use_ok('Mojo::IOLoop');
use_ok('Mojo::Transaction::HTTP');

# Make sure clients dont taint the ioloop
my $ioloop = Mojo::IOLoop->new;
my $client = Mojo::Client->new;
$client->get(
    'http://cpan.org' => sub {
        my $self = shift;
        is($self->res->code, 301, 'right status');
    }
)->process;
$client = undef;
$ioloop->start;

# Fresh client
$client = Mojo::Client->new;

# Custom non keep alive request
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://cpan.org');
$tx->req->headers->connection('close');
$client->process($tx);
is($tx->state,     'done', 'right state');
is($tx->res->code, 301,    'right status');
like($tx->res->headers->connection, qr/close/i, 'right "Connection" header');

# Simple request
$client->get(
    'http://cpan.org' => sub {
        my $self = shift;
        is($self->req->method, 'GET',             'rigth method');
        is($self->req->url,    'http://cpan.org', 'right url');
        is($self->res->code,   301,               'right status');
    }
)->process;

# Simple request with body
$tx = $client->get('http://www.apache.org' => 'Hi there!');
is($tx->req->method, 'GET', 'right method');
is($tx->req->url, 'http://www.apache.org', 'right url');
is($tx->req->headers->content_length, 9,           'right content length');
is($tx->req->body,                    'Hi there!', 'right content');
is($tx->res->code,                    200,         'right status');

# Simple form post
$tx = $client->post_form(
    'http://search.cpan.org/search' => {query => 'mojolicious'});
is($tx->req->method, 'POST', 'right method');
is($tx->req->url, 'http://search.cpan.org/search', 'right url');
is($tx->req->headers->content_length, 17, 'right content length');
is($tx->req->body, 'query=mojolicious', 'right content');
like($tx->res->body, qr/Mojolicious/, 'right content');
is($tx->res->code, 200, 'right status');

# Simple request with headers and body
$client->async->get(
    'http://www.apache.org' => {Expect => '100-continue'} => 'Hi there!' =>
      sub {
        my $self = shift;
        is($self->req->method, 'GET',                   'right method');
        is($self->req->url,    'http://www.apache.org', 'right url');
        is($self->req->body,   'Hi there!',             'right content');
        is($self->res->code,   200,                     'right status');
        ok($self->tx->continued, 'request was continued');
    }
)->process;

# Simple parallel requests with keep alive
$client->get(
    'http://google.com' => sub {
        my $self = shift;
        is($self->req->method, 'GET',               'right method');
        is($self->req->url,    'http://google.com', 'right url');
        is($self->res->code,   301,                 'right status');
    }
);
$client->get(
    'http://www.apache.org' => sub {
        my $self = shift;
        is($self->req->method, 'GET',                   'right method');
        is($self->req->url,    'http://www.apache.org', 'right url');
        is($self->res->code,   200,                     'right status');
        is($self->tx->kept_alive, 1, 'connection was kept alive');
    }
);
$client->get(
    'http://www.google.de' => sub {
        my $self = shift;
        is($self->req->method, 'GET',                  'right method');
        is($self->req->url,    'http://www.google.de', 'right url');
        is($self->res->code,   200,                    'right status');
    }
);
$client->process;

# Websocket request
$client->websocket(
    'ws://websockets.org:8787' => sub {
        my $self = shift;
        is($self->tx->is_websocket, 1, 'websocket transaction');
        $self->receive_message(
            sub {
                my ($self, $message) = @_;
                is($message, 'echo: hi there!', 'right message');
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
        is($tx->req->method,     'GET',                   'right method');
        is($tx->req->url,        'http://www.google.de/', 'right url');
        is($tx->res->code,       200,                     'right status');
        is($h->[0]->req->method, 'GET',                   'right method');
        is($h->[0]->req->url,    'http://www.google.com', 'right url');
        is($h->[0]->res->code,   302,                     'right status');
    }
)->process;
$client->max_redirects(0);

# Custom chunked request without callback
$tx = Mojo::Transaction::HTTP->new;
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
ok($tx->is_done, 'state is done');

# Custom requests with keep alive
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.apache.org');
ok(!$tx->kept_alive, 'connection was not kept alive');
$client->queue(
    $tx => sub {
        my ($self, $tx) = @_;
        ok($tx->is_done,    'state is done');
        ok($tx->kept_alive, 'connection was kept alive');
    }
);
$client->process;
ok($tx->is_done, 'rigth state');
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.apache.org');
ok(!$tx->kept_alive, 'connection was not kept alive');
$client->process(
    $tx => sub {
        my ($self, $tx) = @_;
        ok($tx->is_done,        'state is done');
        ok($tx->kept_alive,     'connection was kept alive');
        ok($tx->local_address,  'has local address');
        ok($tx->local_port > 0, 'has local port');
        is($tx->remote_port, 80, 'right remote port');
    }
);
ok($tx->is_done, 'state is done');

# Custom pipelined requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.apache.org');
my $tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://www.apache.org');
my $tx3 = Mojo::Transaction::HTTP->new;
$tx3->req->method('GET');
$tx3->req->url->parse('http://www.apache.org');
$client->process(
    ([$tx, $tx2], $tx3) => sub {
        my ($self, $tx) = @_;
        return ok($tx->is_done) unless ref $tx eq 'ARRAY';
        ok($tx->[0]->is_done, 'state is done');
        ok($tx->[1]->is_done, 'state is done');
    }
);
ok($tx2->is_done, 'state is done');
ok($tx3->is_done, 'state is done');
is($tx->res->code,  200, 'right status');
is($tx2->res->code, 200, 'rigth status');
is($tx3->res->code, 200, 'right status');
like($tx2->res->content->asset->slurp, qr/Apache/, 'right content');

# Custom pipelined HEAD request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('HEAD');
$tx->req->url->parse('http://www.apache.org');
$tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://www.apache.org');
$client->process(
    [$tx, $tx2] => sub {
        my ($self, $p) = @_;
        ok($p->[0]->is_done, 'state is done');
        ok($p->[1]->is_done, 'state is done');
    }
);
ok($tx2->is_done, 'state is done');
is($tx->res->code,  200, 'right status');
is($tx2->res->code, 200, 'right status');
like($tx2->res->content->asset->slurp, qr/Apache/, 'right content');

# Custom pipelined requests with 100 Continue
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.apache.org');
$tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://www.apache.org');
$tx2->req->headers->expect('100-continue');
$tx2->req->body('foo bar baz');
$tx3 = Mojo::Transaction::HTTP->new;
$tx3->req->method('GET');
$tx3->req->url->parse('http://www.apache.org');
my $tx4 = Mojo::Transaction::HTTP->new;
$tx4->req->method('GET');
$tx4->req->url->parse('http://www.apache.org');
$client->process([$tx, $tx2, $tx3, $tx4]);
ok($tx->is_done,  'state is done');
ok($tx2->is_done, 'state is done');
ok($tx3->is_done, 'state is done');
ok($tx4->is_done, 'state is done');
is($tx->res->code,  200, 'right status');
is($tx2->res->code, 200, 'right status');
is($tx2->continued, 1,   'transaction was continued');
is($tx3->res->code, 200, 'right status');
is($tx4->res->code, 200, 'right status');
like($tx2->res->content->asset->slurp, qr/Apache/, 'right content');
