#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 505;

use FindBin;
use lib "$FindBin::Bin/lib";

use Scalar::Util 'isweak';

# I've done everything the Bible says,
# even the stuff that contradicts the other stuff!
use_ok('LoaderTest');

# Syntax
use_ok('Mojo::Base');

# Basic functionality
my $monkeys = [];
for my $i (1 .. 50) {
    $monkeys->[$i] = LoaderTest->new;
    $monkeys->[$i]->bananas($i);
    is($monkeys->[$i]->bananas, $i);
}
for my $i (51 .. 100) {
    $monkeys->[$i] = LoaderTest->new(bananas => $i);
    is($monkeys->[$i]->bananas, $i);
}
my $y = 1;

# "default" defined but false
my $m = $monkeys->[1];
ok(defined($m->figs));
is($m->figs, 0);
$m->figs(5);
is($m->figs, 5);

# "default" support
for my $i (101 .. 150) {
    $y = !$y;
    $monkeys->[$i] = LoaderTest->new;
    is($monkeys->[$i]->name('foobarbaz'), 'foobarbaz');
    $monkeys->[$i]->heads('3') if $y;
    $y ? is($monkeys->[$i]->heads, 3) : is($monkeys->[$i]->heads, 1);
}

# "chained", "weak" and coderef "default" support
for my $i (151 .. 200) {
    $monkeys->[$i] = LoaderTest->new;
    $monkeys->[$i]->friend($monkeys->[$i]);
    ok(isweak $monkeys->[$i]->{friend});
    is($monkeys->[$i]->friend,        $monkeys->[$i]);
    is($monkeys->[$i]->ears,          2);
    is($monkeys->[$i]->ears(6)->ears, 6);
    is($monkeys->[$i]->eyes,          2);
    is($monkeys->[$i]->eyes(6)->eyes, 6);
}

1;
