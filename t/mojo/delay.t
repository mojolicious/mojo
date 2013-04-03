use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::IOLoop;
use Mojo::IOLoop::Delay;

# Basic functionality
my $delay = Mojo::IOLoop::Delay->new;
my @results;
for my $i (1, 1) {
  $delay->begin;
  Mojo::IOLoop->timer(0 => sub { push @results, $i; $delay->end });
}
my $cb = $delay->begin;
$delay->begin;
is $cb->(), 3, 'three remaining';
is $delay->end, 2, 'two remaining';
$delay->wait;
is_deeply \@results, [1, 1], 'right results';

# Arguments
$delay = Mojo::IOLoop::Delay->new;
my $result;
$delay->on(finish => sub { shift; $result = [@_] });
for my $i (2, 2) {
  $delay->begin;
  Mojo::IOLoop->timer(0 => sub { $delay->end($i) });
}
is_deeply [$delay->wait], [2, 2], 'right results';
is_deeply $result, [2, 2], 'right results';

# Scalar context
$delay = Mojo::IOLoop::Delay->new;
for my $i (3, 3) {
  $delay->begin;
  Mojo::IOLoop->timer(0 => sub { $delay->end($i) });
}
is $delay->wait, 3, 'right results';

# Steps
my $finished;
$result = undef;
$delay  = Mojo::IOLoop::Delay->new;
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

# Clear all remaining steps
($finished, $result) = ();
$delay = Mojo::IOLoop::Delay->new;
$delay->on(finish => sub { $finished++ });
$delay->steps(
  sub {
    my $delay = shift;
    Mojo::IOLoop->timer(0 => $delay->begin);
  },
  sub {
    my $delay = shift;
    $delay->clear;
    Mojo::IOLoop->timer(0 => $delay->begin);
  },
  sub {
    my $delay = shift;
    $result = 'fail';
    Mojo::IOLoop->timer(0 => $delay->begin);
  },
  sub { $result = 'fail' }
);
$delay->wait;
is $finished, 1, 'finish event has been emitted once';
ok !$result, 'no result';

# Clear all steps (except for the first)
$result = undef;
$delay  = Mojo::IOLoop::Delay->new;
$delay->steps(
  sub {
    my $delay = shift;
    Mojo::IOLoop->timer(0 => $delay->begin);
  },
  sub { $result = 'fail' }
);
$delay->clear->wait;
ok !$result, 'no result';

# Finish steps with event
$result = undef;
$delay  = Mojo::IOLoop::Delay->new;
$delay->on(
  finish => sub {
    my ($delay, @numbers) = @_;
    $result = \@numbers;
  }
);
$delay->steps(
  sub {
    my $delay = shift;
    my $cb    = $delay->begin;
    Mojo::IOLoop->timer(0 => sub { $cb->(1, 2, 3) });
  },
  sub {
    my ($delay, @numbers) = @_;
    my $cb = $delay->begin;
    Mojo::IOLoop->timer(0 => sub { $cb->(undef, @numbers, 4) });
  }
);
is_deeply [$delay->wait], [2, 3, 4], 'right numbers';
is_deeply $result, [2, 3, 4], 'right numbers';

# Nested delays
($finished, $result) = ();
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

done_testing();
