#!/usr/bin/env perl -w

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More;

plan skip_all => 'set TEST_CLIENT to enable this test'
  unless $ENV{TEST_CLIENT};
plan tests => 45;

# So then I said to the cop, "No, you're driving under the influence...
# of being a jerk".
use_ok('Mojo::Client');
use_ok('Mojo::Pipeline');
use_ok('Mojo::Transaction');

# Chunked request
my $client = Mojo::Client->new;
my $tx     = Mojo::Transaction->new_get('http://google.com');
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
$client->process_all($tx);
ok($tx->is_done);

# Parallel async io
$tx =
  Mojo::Transaction->new_post('http://kraih.com', Expect => '100-continue');
$tx->req->body('foo bar baz');
my $tx2 =
  Mojo::Transaction->new_get('http://labs.kraih.com',
    Expect => '100-continue');
$tx2->req->body('foo bar baz');
my @transactions = ($tx, $tx2);

while (1) {
    $client->spin(@transactions);
    my @buffer;
    while (my $transaction = shift @transactions) {
        unless ($transaction->is_finished) {
            push @buffer, $transaction;
        }
    }
    push @transactions, @buffer;
    last unless @transactions;
}
is($tx->res->code,  200);
is($tx->continued,  1);
is($tx2->res->code, 301);
is($tx2->continued, 1);

# Test keep-alive
$tx = Mojo::Transaction->new_get('http://labs.kraih.com');
ok(!$tx->kept_alive);

# First time, new connection
$client->process_all($tx);
ok($tx->is_done);
ok(!$tx->kept_alive);

# Second time, reuse connection
$tx = Mojo::Transaction->new_get('http://labs.kraih.com');
ok(!$tx->kept_alive);
$client->process_all($tx);
ok($tx->is_done);
ok($tx->kept_alive);
ok($tx->local_address);
ok($tx->local_port > 0);
is($tx->remote_address, '88.198.25.164');
is($tx->remote_port,    80);

# Pipelined
$tx  = Mojo::Transaction->new_get('http://labs.kraih.com');
$tx2 = Mojo::Transaction->new_get('http://mojolicious.org');
my $tx3 = Mojo::Transaction->new_get('http://kraih.com');
$client->process_all(Mojo::Pipeline->new($tx, $tx2), $tx3);
ok($tx->is_done);
ok($tx2->is_done);
ok($tx3->is_done);
is($tx->res->code,  301);
is($tx2->res->code, 200);
is($tx3->res->code, 200);
like($tx2->res->content->file->slurp, qr/Mojolicious/);

# Pipelined with 100 Continue
$tx  = Mojo::Transaction->new_get('http://labs.kraih.com');
$tx2 = Mojo::Transaction->new_get('http://mojolicious.org');
$tx2->req->headers->expect('100-continue');
$tx2->req->body('foo bar baz');
$tx3 = Mojo::Transaction->new_get('http://labs.kraih.com/blog/');
my $tx4 = Mojo::Transaction->new_get('http://labs.kraih.com/blog');
$client->process_all(Mojo::Pipeline->new($tx, $tx2, $tx3, $tx4));
ok($tx->is_done);
ok($tx2->is_done);
ok($tx3->is_done);
ok($tx4->is_done);
is($tx->res->code,  301);
is($tx2->res->code, 200);
is($tx2->continued, 1);
is($tx3->res->code, 200);
is($tx4->res->code, 301);
like($tx2->res->content->file->slurp, qr/Mojolicious/);

# Pipelined head
$tx  = Mojo::Transaction->new_head('http://labs.kraih.com/blog/');
$tx2 = Mojo::Transaction->new_get('http://mojolicious.org');
$client->process_all(Mojo::Pipeline->new($tx, $tx2));
ok($tx->is_done);
ok($tx2->is_done);
is($tx->res->code,  200);
is($tx2->res->code, 200);
like($tx2->res->content->file->slurp, qr/Mojolicious/);

# Bad pipeline
$tx  = Mojo::Transaction->new_get('http://kraih.com');
$tx2 = Mojo::Transaction->new_get('http://mojolicious.org:3131/');
$tx3 = Mojo::Transaction->new_get('http://labs.kraih.com');
my $pipe = Mojo::Pipeline->new($tx, $tx2);
$client->process_all($pipe, $tx3);
ok($pipe->has_error);
is($tx->state,  'start');
is($tx2->state, 'start');
ok($tx3->is_done);
is($tx3->res->code, 301);
