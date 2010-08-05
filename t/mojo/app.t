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
plan tests => 25;

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
is($app->log, $logger, 'right logger');

$app = Mojo::HelloWorld->new;
my $client = Mojo::Client->new->app($app);

# Continue
my $port   = $client->test_server;
my $buffer = '';
my $i      = 1;
$client->ioloop->connect(
    address => 'localhost',
    port    => $port,
    read_cb => sub {
        my ($self, $id, $chunk) = @_;
        $buffer .= $chunk;
        $self->drop($id) and $self->stop if $buffer =~ /Mojo is working!/;
        $self->writing($id)
          if $buffer =~ /HTTP\/1.1 100 Continue.*\x0d\x0a\x0d\x0a/gs;
    },
    write_cb => sub {
        my ($self, $id) = @_;
        $self->not_writing($id);
        return '4321' if $i == 2;
        $i++;
        return
            "GET / HTTP/1.1\x0d\x0a"
          . "Expect: 100-continue\x0d\x0a"
          . "Content-Length: 4\x0d\x0a\x0d\x0a";
    }
);
$client->ioloop->start;
like($buffer, qr/HTTP\/1.1 100 Continue/, 'request was continued');

# Pipelined
$buffer = '';
$client->ioloop->connect(
    address => 'localhost',
    port    => $port,
    read_cb => sub {
        my ($self, $id, $chunk) = @_;
        $buffer .= $chunk;
        $self->drop($id) and $self->stop if $buffer =~ /working!.*working!/gs;
    },
    write_cb => sub {
        my ($self, $id) = @_;
        $self->not_writing($id);
        return
            "GET / HTTP/1.1\x0d\x0a"
          . "Content-Length: 0\x0d\x0a\x0d\x0a"
          . "GET / HTTP/1.1\x0d\x0a"
          . "Content-Length: 0\x0d\x0a\x0d\x0a";
    }
);
$client->ioloop->start;
like($buffer, qr/Mojo is working!/, 'transactions were pipelined');

# Normal request
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/1/');
$client->process($tx);
ok($tx->keep_alive, 'will be kept alive');
is($tx->res->code, 200, 'right status');
like($tx->res->body, qr/^Congratulations/, 'right content');

# POST request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/2/');
$tx->req->headers->expect('fun');
$tx->req->body('foo bar baz' x 128);
$client->process($tx);
is($tx->res->code, 200, 'right status');
like($tx->res->body, qr/^Congratulations/, 'right content');

# POST request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/3/');
$tx->req->headers->expect('fun');
$tx->req->body('bar baz foo' x 128);
$client->process($tx);
ok(defined $tx->connection, 'has connection id');
is($tx->res->code, 200, 'right status');
like($tx->res->body, qr/^Congratulations/, 'right content');

# Multiple requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/4/');
my $tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('/5/');
$client->process($tx, $tx2);
ok(defined $tx->connection,  'has connection id');
ok(defined $tx2->connection, 'has connection id');
ok($tx->is_done,             'state is done');
ok($tx2->is_done,            'state is done');

# Multiple requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/6/');
$tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('POST');
$tx2->req->url->parse('/7/');
$tx2->req->headers->expect('fun');
$tx2->req->body('bar baz foo' x 128);
my $tx3 = Mojo::Transaction::HTTP->new;
$tx3->req->method('GET');
$tx3->req->url->parse('/8/');
$client->process($tx, $tx2, $tx3);
ok($tx->is_finished, 'state is finished');
ok(!$tx->has_error,  'has no errors');
ok($tx2->is_done,    'state is done');
ok(!$tx2->has_error, 'has no error');
ok($tx3->is_done,    'state is done');
ok(!$tx3->has_error, 'has no error');
