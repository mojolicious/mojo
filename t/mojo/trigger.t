#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

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
  Mojo::IOLoop->defer(sub { push @results, $i; $t->end });
}
$t->start;
is_deeply \@results, [0, 0], 'right results';

# Everything
$t = Mojo::IOLoop::Trigger->new;
my $done;
$t->on(done => sub { shift; $done = [@_, 'works!'] });
for my $i (0, 0) {
  $t->begin;
  Mojo::IOLoop->defer(sub { $t->end($i) });
}
@results = $t->start;
is_deeply $done, [0, 0, 'works!'], 'right results';
is_deeply \@results, [0, 0], 'right results';

# Mojo::IOLoop
$done = undef;
$t = Mojo::IOLoop->trigger(sub { shift; $done = [@_, 'too!'] });
for my $i (1, 1) {
  my $cb = $t->begin;
  Mojo::IOLoop->defer(sub { $t->$cb($i) });
}
@results = $t->start;
is_deeply $done, [1, 1, 'too!'], 'right results';
is_deeply \@results, [1, 1], 'right results';
