use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 14;

# "And now to create an unstoppable army of between one million and two
#  million zombies!"
use Mojo::IOLoop;
use Mojo::IOLoop::Delay;

# Basic functionality
my $delay = Mojo::IOLoop::Delay->new;
my @results;
for my $i (0, 0) {
  $delay->begin;
  Mojo::IOLoop->timer(0 => sub { push @results, $i; $delay->end });
}
my $end = $delay->begin;
$delay->begin;
is $end->(), 3, 'three remaining';
is $delay->end, 2, 'two remaining';
$delay->wait;
is_deeply \@results, [0, 0], 'right results';

# Arguments
$delay = Mojo::IOLoop::Delay->new;
my $finished;
$delay->on(finish => sub { shift; $finished = [@_, 'works!'] });
for my $i (0, 0) {
  $delay->begin;
  Mojo::IOLoop->timer(0 => sub { $delay->end($i) });
}
@results = $delay->wait;
is_deeply $finished, [0, 0, 'works!'], 'right results';
is_deeply \@results, [0, 0], 'right results';

# Context
$delay = Mojo::IOLoop::Delay->new;
for my $i (3, 3) {
  $delay->begin;
  Mojo::IOLoop->timer(0 => sub { $delay->end($i) });
}
is $delay->wait, 3, 'right results';

# Steps
my $result;
$finished = undef;
$delay    = Mojo::IOLoop::Delay->new;
$delay->on(finish => sub { $finished++ });
$delay->steps(
  sub {
    my $delay = shift;
    my $cb    = $delay->begin;
    $delay->begin->(3, 2, 1);
    Mojo::IOLoop->timer(0 => sub { $cb->(1, 2, 3) });
  },
  sub {
    my ($delay, @numbers) = @_;
    my $cb = $delay->begin;
    Mojo::IOLoop->timer(0 => sub { $cb->(undef, @numbers, 4) });
  },
  sub {
    my ($delay, @numbers) = @_;
    $result = \@numbers;
  }
);
is_deeply [$delay->wait], [2, 3, 2, 1, 4], 'right numbers';
is $finished, 1, 'finish event has been emitted once';
is_deeply $result, [2, 3, 2, 1, 4], 'right numbers';

# Event loop
$finished = undef;
$delay = Mojo::IOLoop->delay(sub { shift; $finished = [@_, 'too!'] });
for my $i (1, 1) {
  my $cb = $delay->begin;
  Mojo::IOLoop->timer(0 => sub { $delay->$cb($i) });
}
@results = $delay->wait;
is_deeply $finished, [1, 1, 'too!'], 'right results';
is_deeply \@results, [1, 1], 'right results';

# Nested delays
($result, $finished) = undef;
$delay = Mojo::IOLoop->delay(
  sub {
    my $first = shift;
    $first->on(finish => sub { $finished++ });
    my $second = Mojo::IOLoop->delay($first->begin);
    Mojo::IOLoop->timer(0 => $second->begin);
    Mojo::IOLoop->timer(0 => $first->begin);
    $second->begin;
    Mojo::IOLoop->timer(0 => sub { $second->end(1, 2, 3) });
  },
  sub {
    my ($first, @numbers) = @_;
    $result = \@numbers;
    my $cb = $first->begin;
    $first->begin->(3, 2, 1);
    $first->begin;
    $first->begin;
    $first->end(4);
    $first->end(5, 6);
    $cb->(1, 2, 3);
  },
  sub {
    my ($first, @numbers) = @_;
    push @$result, @numbers;
  }
);
is_deeply [$delay->wait], [2, 3, 2, 1, 4, 5, 6], 'right numbers';
is $finished, 1, 'finish event has been emitted once';
is_deeply $result, [1, 2, 3, 2, 3, 2, 1, 4, 5, 6], 'right numbers';
