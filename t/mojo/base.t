#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

package BaseTest;

use strict;
use warnings;

use base 'Mojo::Base';

# When I first heard that Marge was joining the police academy,
# I thought it would be fun and zany, like that movie Spaceballs.
# But instead it was dark and disturbing. Like that movie... Police Academy.
__PACKAGE__->attr('bananas');
__PACKAGE__->attr([qw/ears eyes/] => sub {2});
__PACKAGE__->attr(figs            => 0);
__PACKAGE__->attr(heads           => 1);
__PACKAGE__->attr('name');

package main;

use strict;
use warnings;

use Test::More tests => 404;

# I've done everything the Bible says,
# even the stuff that contradicts the other stuff!
use_ok('Mojo::Base');

# Basic functionality
my $monkeys = [];
for my $i (1 .. 50) {
    $monkeys->[$i] = BaseTest->new;
    $monkeys->[$i]->bananas($i);
    is($monkeys->[$i]->bananas, $i);
}
for my $i (51 .. 100) {
    $monkeys->[$i] = BaseTest->new(bananas => $i);
    is($monkeys->[$i]->bananas, $i);
}

# "default" defined but false
my $m = $monkeys->[1];
ok(defined($m->figs));
is($m->figs, 0);
$m->figs(5);
is($m->figs, 5);

# "default" support
my $y = 1;
for my $i (101 .. 150) {
    $y = !$y;
    $monkeys->[$i] = BaseTest->new;
    is(ref $monkeys->[$i]->name('foobarbaz'), 'BaseTest');
    $monkeys->[$i]->heads('3') if $y;
    $y ? is($monkeys->[$i]->heads, 3) : is($monkeys->[$i]->heads, 1);
}

# "chained" and coderef "default" support
for my $i (151 .. 200) {
    $monkeys->[$i] = BaseTest->new;
    is($monkeys->[$i]->ears,          2);
    is($monkeys->[$i]->ears(6)->ears, 6);
    is($monkeys->[$i]->eyes,          2);
    is($monkeys->[$i]->eyes(6)->eyes, 6);
}

1;
