use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 2;

# "It's not just safe, it's 40% safe!"
use Mojo::IOLoop;
use Mojo::IOLoop::Steps;

# Basic functionality
my $result;
my $steps = Mojo::IOLoop::Steps->new(
  sub {
    my $next = shift;
    $next->(1, 2, 3);
  },
  sub {
    my ($next, @numbers) = @_;
    $result = \@numbers;
    $next->();
  }
);
is_deeply $result, [2, 3], 'right numbers';

# Event loop
$result = undef;
$steps  = Mojo::IOLoop->steps(
  sub {
    my $next  = shift;
    my $delay = Mojo::IOLoop->delay($next);
    Mojo::IOLoop->timer(0 => $delay->begin);
    $delay->begin;
    Mojo::IOLoop->timer(0 => sub { $delay->end(1, 2, 3) });
  },
  sub { shift->(@_) },
  sub {
    my ($next, @numbers) = @_;
    $result = \@numbers;
  }
);
Mojo::IOLoop->start;
is_deeply $result, [1, 2, 3], 'right numbers';
