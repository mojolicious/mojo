#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More;

plan skip_all => 'set TEST_CLIENT to enable this test'
  unless $ENV{TEST_CLIENT};
plan tests => 6;

# So then I said to the cop, "No, you're driving under the influence...
# of being a jerk".
use_ok('Mojo::Client');
use_ok('Mojo::Transaction');

# Parallel async io
my $client = Mojo::Client->new;
my $tx =
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
