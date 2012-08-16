use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 3;

# "It's not just safe, it's 40% safe!"
use Mojo::IOLoop;
use Mojo::IOLoop::Steps;

# Basic functionality
my $result;
my $steps = Mojo::IOLoop::Steps->new(
  sub {
    my $steps = shift;
    $steps->next->(1, 2, 3);
  },
  sub {
    my ($steps, @numbers) = @_;
    $result = \@numbers;
  }
);
is_deeply $result, [2, 3], 'right numbers';

# Multiple steps
$result = undef;
$steps  = Mojo::IOLoop::Steps->new(
  sub {
    my $steps = shift;
    my $cb    = $steps->next;
    $steps->next->(1, 2, 3);
    $cb->(3, 2, 1);
  },
  sub { shift->next->(@_) },
  sub {
    my ($steps, @numbers) = @_;
    $result = \@numbers;
  }
);
is_deeply $result, [2, 3, 2, 1], 'right numbers';

# Event loop
$result = undef;
$steps  = Mojo::IOLoop->steps(
  sub {
    my $steps = shift;
    my $delay = Mojo::IOLoop->delay;
    $delay->on(finish => $steps->next);
    Mojo::IOLoop->timer(0 => $delay->begin);
    Mojo::IOLoop->timer(0 => $steps->next);
    $delay->begin;
    Mojo::IOLoop->timer(0 => sub { $delay->end(1, 2, 3) });
  },
  sub {
    my ($steps, @numbers) = @_;
    $result = \@numbers;
  }
);
Mojo::IOLoop->start;
is_deeply $result, [1, 2, 3], 'right numbers';
