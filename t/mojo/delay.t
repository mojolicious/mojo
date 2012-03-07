use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 6;

# "And now to create an unstoppable army of between one million and two
#  million zombies!"
use Mojo::IOLoop;
use Mojo::IOLoop::Delay;

# Minimal
my $delay = Mojo::IOLoop::Delay->new;
my @results;
for my $i (0, 0) {
  $delay->begin;
  Mojo::IOLoop->timer(0 => sub { push @results, $i; $delay->end });
}
$delay->wait;
is_deeply \@results, [0, 0], 'right results';

# Everything
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

# Mojo::IOLoop
$finished = undef;
$delay = Mojo::IOLoop->delay(sub { shift; $finished = [@_, 'too!'] });
for my $i (1, 1) {
  my $cb = $delay->begin;
  Mojo::IOLoop->timer(0 => sub { $delay->$cb($i) });
}
@results = $delay->wait;
is_deeply $finished, [1, 1, 'too!'], 'right results';
is_deeply \@results, [1, 1], 'right results';
