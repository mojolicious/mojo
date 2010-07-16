#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = $ENV{MOJO_NO_TLS} = 1 }

use Test::More;

plan skip_all =>
  'set TEST_CLIENT to enable this test (internet connection required!)'
  unless $ENV{TEST_CLIENT};
plan tests => 97;

# So then I said to the cop, "No, you're driving under the influence...
# of being a jerk".
use_ok('Mojo::Client');
use_ok('Mojo::IOLoop');
use_ok('Mojo::Transaction::HTTP');
use_ok('ojo');

# Make sure clients dont taint the ioloop
my $loop   = Mojo::IOLoop->new;
my $client = Mojo::Client->new;
my $code;
$client->get(
    'http://cpan.org' => sub {
        my $self = shift;
        $code = $self->res->code;
    }
)->process;
$client = undef;
my $ticks = 0;
$loop->tick_cb(sub { $ticks++ });
$loop->idle_cb(sub { shift->stop });
$loop->start;
is($ticks, 1,   'loop not tainted');
is($code,  301, 'right status');

# Fresh client
$client = Mojo::Client->new;

# Host does not exist
my $tx = $client->build_tx(GET => 'http://cdeabcdeffoobarnonexisting.com');
$client->process($tx);
is($tx->state, 'error', 'right state');

# Custom non keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://cpan.org');
$tx->req->headers->connection('close');
$client->process($tx);
is($tx->state,     'done', 'right state');
is($tx->res->code, 301,    'right status');
like($tx->res->headers->connection, qr/close/i, 'right "Connection" header');

# Proxy check
my $backup  = $ENV{HTTP_PROXY}  || '';
my $backup2 = $ENV{HTTPS_PROXY} || '';
$ENV{HTTP_PROXY}  = 'http://127.0.0.1';
$ENV{HTTPS_PROXY} = 'https://127.0.0.1';
$client->proxy_env;
is($client->http_proxy,  'http://127.0.0.1',  'right proxy');
is($client->https_proxy, 'https://127.0.0.1', 'right proxy');
$client->http_proxy(undef);
$client->https_proxy(undef);
is($client->http_proxy,  undef, 'right proxy');
is($client->https_proxy, undef, 'right proxy');
$ENV{HTTP_PROXY}  = $backup;
$ENV{HTTPS_PROXY} = $backup2;

# Oneliner
is(g('http://mojolicious.org')->code,  200, 'right status');
is(p('http://mojolicious.org')->code,  404, 'right status');
is(oO('http://mojolicious.org')->code, 200, 'right status');
is(oO(POST => 'http://mojolicious.org')->code, 404, 'right status');

# Simple request
my ($method, $url);
$code = undef;
$client->get(
    'http://cpan.org' => sub {
        my $self = shift;
        $method = $self->req->method;
        $url    = $self->req->url;
        $code   = $self->res->code;
    }
)->process;
is($method, 'GET',             'right method');
is($url,    'http://cpan.org', 'right url');
is($code,   301,               'right status');

# HTTPS request without TLS support
$tx = $client->get('https://www.google.com');
is($tx->has_error, 1, 'request failed');

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
my ($body, $continued);
($method, $url, $code) = undef;
$client->get(
    'http://www.apache.org' => {Expect => '100-continue'} => 'Hi there!' =>
      sub {
        my $self = shift;
        $method    = $self->req->method;
        $url       = $self->req->url;
        $body      = $self->req->body;
        $code      = $self->res->code;
        $continued = $self->tx->continued;
    }
)->process;
is($method, 'GET',                   'right method');
is($url,    'http://www.apache.org', 'right url');
is($body,   'Hi there!',             'right content');
is($code,   200,                     'right status');
ok($continued, 'request was continued');

# Simple parallel requests with keep alive
($method, $url, $code) = undef;
$client->get(
    'http://google.com' => sub {
        my $self = shift;
        $method = $self->req->method;
        $url    = $self->req->url;
        $code   = $self->res->code;
    }
);
my ($method2, $url2, $code2, $kept_alive);
$client->get(
    'http://www.apache.org' => sub {
        my $self = shift;
        $method2    = $self->req->method;
        $url2       = $self->req->url;
        $code2      = $self->res->code;
        $kept_alive = $self->tx->kept_alive;
    }
);
my ($method3, $url3, $code3);
$client->get(
    'http://www.google.de' => sub {
        my $self = shift;
        $method3 = $self->req->method;
        $url3    = $self->req->url;
        $code3   = $self->res->code;
    }
);
$client->process;
is($method,     'GET',                   'right method');
is($url,        'http://google.com',     'right url');
is($code,       301,                     'right status');
is($method2,    'GET',                   'right method');
is($url2,       'http://www.apache.org', 'right url');
is($code2,      200,                     'right status');
is($kept_alive, 1,                       'connection was kept alive');
is($method3,    'GET',                   'right method');
is($url3,       'http://www.google.de',  'right url');
is($code3,      200,                     'right status');

# Simple requests with redirect
($method, $url, $code, $method2, $url2, $code2) = undef;
$client->max_redirects(3);
$client->get(
    'http://www.google.com' => sub {
        my ($self, $tx) = @_;
        $method  = $tx->req->method;
        $url     = $tx->req->url;
        $code    = $tx->res->code;
        $method2 = $tx->previous->[-1]->req->method;
        $url2    = $tx->previous->[-1]->req->url;
        $code2   = $tx->previous->[-1]->res->code;
    }
)->process;
$client->max_redirects(0);
is($method,  'GET',                   'right method');
is($url,     'http://www.google.de/', 'right url');
is($code,    200,                     'right status');
is($method2, 'GET',                   'right method');
is($url2,    'http://www.google.com', 'right url');
is($code2,   302,                     'right status');

# Simple requests with redirect and no callback
$client->max_redirects(3);
$tx = $client->get('http://www.google.com');
$client->max_redirects(0);
is($tx->req->method,                'GET',                   'right method');
is($tx->req->url,                   'http://www.google.de/', 'right url');
is($tx->res->code,                  200,                     'right status');
is($tx->previous->[0]->req->method, 'GET',                   'right method');
is($tx->previous->[0]->req->url,    'http://www.google.com', 'right url');
is($tx->previous->[0]->res->code,   302,                     'right status');

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
my $done;
$kept_alive = undef;
$client->queue(
    $tx => sub {
        my ($self, $tx) = @_;
        $done       = $tx->is_done;
        $kept_alive = $tx->kept_alive;
    }
);
$client->process;
ok($done,        'state is done');
ok($kept_alive,  'connection was kept alive');
ok($tx->is_done, 'right state');
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.apache.org');
ok(!$tx->kept_alive, 'connection was not kept alive');
my ($address, $port, $port2);
($done, $kept_alive) = undef;
$client->process(
    $tx => sub {
        my ($self, $tx) = @_;
        $done       = $tx->is_done;
        $kept_alive = $tx->kept_alive;
        $address    = $tx->local_address;
        $port       = $tx->local_port;
        $port2      = $tx->remote_port, 80;
    }
);
ok($done,       'state is done');
ok($kept_alive, 'connection was kept alive');
ok($address,    'has local address');
ok($port > 0,   'has local port');
is($port2, 80, 'right remote port');
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
my ($done2, $done3);
$done = undef;
$client->process(
    ([$tx, $tx2], $tx3) => sub {
        my ($self, $tx, $tx2) = @_;
        return $done3 = $tx->is_done unless $tx2;
        $done  = $tx->is_done;
        $done2 = $tx2->is_done;
    }
);
ok($done,         'state is done');
ok($done2,        'state is done');
ok($done3,        'state is done');
ok($tx2->is_done, 'state is done');
ok($tx3->is_done, 'state is done');
is($tx->res->code,  200, 'right status');
is($tx2->res->code, 200, 'right status');
is($tx3->res->code, 200, 'right status');
like($tx2->res->content->asset->slurp, qr/Apache/, 'right content');

# Custom pipelined HEAD request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('HEAD');
$tx->req->url->parse('http://www.apache.org');
$tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://www.apache.org');
($done, $done2) = undef;
$client->process(
    [$tx, $tx2] => sub {
        my ($self, $tx, $tx2) = @_;
        $done  = $tx->is_done;
        $done2 = $tx2->is_done;
    }
);
ok($done,         'state is done');
ok($done2,        'state is done');
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
