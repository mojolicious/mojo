#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 3;

use_ok('Mojo::IOLoop');

# Marge, you being a cop makes you the man!
# Which makes me the woman, and I have no interest in that,
# besides occasionally wearing the underwear,
# which as we discussed, is strictly a comfort thing.
my $loop = Mojo::IOLoop->new;

# Ticks
my $ticks = 0;
$loop->tick_cb(sub { $ticks++ });

# Timer
my $flag = 0;
$loop->timer(
    1 => sub {
        my $self = shift;
        $self->timer(
            1 => sub {
                is($flag, 23, 'recursive timer works');
            }
        );
        $flag = 23;
    }
);

# Start
$loop->start;

# Another tick
$loop->one_tick;

# Ticks
ok($ticks > 3, 'more than three ticks');
