#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 6;

use Mojo::IOLoop;

# "And now to create an unstoppable army of between one million and two
#  million zombies!"
use_ok 'Mojo::IOLoop::Trigger';

# Minimal
my $t = Mojo::IOLoop::Trigger->new;
my @results;
for my $i (0, 0) {
  $t->begin;
  Mojo::IOLoop->timer($i => sub { push @results, $i; $t->end });
}
$t->start;
is_deeply \@results, [0, 0], 'right results';

# Everything
$t = Mojo::IOLoop::Trigger->new;
my $done;
$t->on(done => sub { shift; $done = [@_, 'works!'] });
for my $i (0, '0.5') {
  $t->begin;
  Mojo::IOLoop->timer($i => sub { $t->end($i) });
}
@results = $t->start;
is_deeply $done, [0, '0.5', 'works!'], 'right results';
is_deeply \@results, [0, '0.5'], 'right results';

# Mojo::IOLoop
$done = undef;
$t = Mojo::IOLoop->trigger(sub { shift; $done = [@_, 'too!'] });
for my $i (0, 1) {
  $t->begin;
  Mojo::IOLoop->timer($i => sub { $t->end($i) });
}
@results = $t->start;
is_deeply $done, [0, 1, 'too!'], 'right results';
is_deeply \@results, [0, 1], 'right results';
