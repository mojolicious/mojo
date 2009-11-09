#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 26;

# I personalized each of your meals.
# For example, Amy: you're cute, so I baked you a pony.
use_ok('Mojo::Stateful');

# Basic stuff
my $stateful = Mojo::Stateful->new;
ok($stateful);
is($stateful->state, 'start');
ok(!$stateful->is_done);

# is_state
ok($stateful->is_state('start'));
ok($stateful->is_state(qw/start other/));
ok(!$stateful->is_state(qw/neither other/));
ok(!$stateful->is_finished);

# Change state
$stateful->state('connected');
is($stateful->state, 'connected');
ok($stateful->is_state(qw/another connected/));
ok(!$stateful->is_done);
ok(!$stateful->is_finished);

# Errors
ok(!defined($stateful->error));
ok(!$stateful->has_error);
$stateful->error('Oops');
ok($stateful->error);
ok($stateful->has_error);
is($stateful->error, 'Oops');
is($stateful->state, 'error');
ok($stateful->is_state(qw/error another/));
ok(!$stateful->is_done);
ok($stateful->is_finished);

# done
$stateful->done;
is($stateful->state, 'done');
ok($stateful->is_state(qw/another done error/));
ok($stateful->is_done);
ok($stateful->is_finished);

# Unknown error
$stateful = Mojo::Stateful->new;
$stateful->state('error');
is($stateful->error, 'Unknown state machine error.');
