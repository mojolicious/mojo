#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 8;

use_ok 'Mojo::IOLoop';

# "Marge, you being a cop makes you the man!
#  Which makes me the woman, and I have no interest in that,
#  besides occasionally wearing the underwear,
#  which as we discussed, is strictly a comfort thing."
my $loop = Mojo::IOLoop->new;

# Ticks
my $ticks = 0;
my $id = $loop->on_tick(sub { $ticks++ });

# Timer
my $flag = 0;
my $flag2;
$loop->timer(
  1 => sub {
    my $self = shift;
    $self->timer(
      1 => sub {
        shift->stop;
        $flag2 = $flag;
      }
    );
    $flag = 23;
  }
);

# HiRes timer
my $hiresflag = 0;
$loop->timer(0.25 => sub { $hiresflag = 42 });

# Start
$loop->start;

# Timer
is $flag, 23, 'recursive timer works';

# HiRes timer
is $hiresflag, 42, 'hires timer';

# Idle callback
my $idle = 0;
$loop->on_idle(sub { $idle++ });

# Another tick
$loop->one_tick;

# Ticks
ok $ticks > 2, 'more than two ticks';

# Idle callback
is $idle, 1, 'on_idle was called';

# Run again without first tick event handler
my $before = $ticks;
my $after  = 0;
$loop->on_tick(sub { $after++ });
$loop->drop($id);
$loop->timer(1 => sub { shift->stop });
$loop->start;
ok $after > 2, 'more than two ticks';
is $ticks, $before, 'no additional ticks';

# Handle
my $port = Mojo::IOLoop->generate_port;
my $handle;
$loop->listen(
  port      => $port,
  on_accept => sub { $handle = shift->handle(pop) }
);
$loop->connect(
  address => 'localhost',
  port    => $port,
);
$loop->timer('0.5' => sub { shift->stop });
$loop->start;
isa_ok $handle, 'IO::Socket::INET', 'right reference';
