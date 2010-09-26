#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 5;

use_ok 'Mojo::IOLoop';

# Marge, you being a cop makes you the man!
# Which makes me the woman, and I have no interest in that,
# besides occasionally wearing the underwear,
# which as we discussed, is strictly a comfort thing.
my $loop = Mojo::IOLoop->new;

# Ticks
my $ticks = 0;
$loop->on_tick(sub { $ticks++ });

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
