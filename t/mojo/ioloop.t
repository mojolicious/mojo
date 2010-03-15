#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 2;

use_ok('Mojo::IOLoop');

# Marge, you being a cop makes you the man!
# Which makes me the woman, and I have no interest in that,
# besides occasionally wearing the underwear,
# which as we discussed, is strictly a comfort thing.
my $loop = Mojo::IOLoop->new;

# Timer
my $flag = 0;
$loop->timer(
    after => 1,
    cb    => sub {
        my $self = shift;
        $self->timer(
            after => 1,
            cb    => sub {
                is($flag, 23);
            }
        );
        $flag = 23;
    }
);

$loop->start;
