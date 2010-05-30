#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 26;

# I personalized each of your meals.
# For example, Amy: you're cute, so I baked you a pony.
use_ok('Mojo::Stateful');

# Basic stuff
my $stateful = Mojo::Stateful->new;
ok($stateful, 'initialized');
is($stateful->state, 'start', 'default state');
ok(!$stateful->is_done, 'state is not done');

# is_state
ok($stateful->is_state('start'),            'state is start');
ok($stateful->is_state(qw/start other/),    'state is start or other');
ok(!$stateful->is_state(qw/neither other/), 'state is not neither or other');
ok(!$stateful->is_finished,                 'state is not finished');

# Change state
$stateful->state('connected');
is($stateful->state, 'connected', 'right state');
ok($stateful->is_state(qw/another connected/),
    'state is another or connected');
ok(!$stateful->is_done,     'state is not done');
ok(!$stateful->is_finished, 'state is not finished');

# Errors
ok(!defined($stateful->error), 'has no error');
ok(!$stateful->has_error,      'has no error');
$stateful->state_cb(sub { $stateful->{error}->[0] .= 'st' });
$stateful->error('te');
ok($stateful->has_error, 'has error');
is($stateful->error, 'test',  'right error');
is($stateful->state, 'error', 'right state');
ok($stateful->is_state(qw/error another/), 'state is error or another');
ok(!$stateful->is_done,                    'state is not done');
ok($stateful->is_finished,                 'state is finished');
$stateful->error('te', 500);
is_deeply([$stateful->error], ['test', 500], 'right error and code');

# done
$stateful->done;
is($stateful->state, 'done', 'right state');
ok($stateful->is_state(qw/another done error/),
    'state is another, done or error');
ok($stateful->is_done,     'state is done');
ok($stateful->is_finished, 'state is finished');

# Unknown error
$stateful = Mojo::Stateful->new;
$stateful->state('error');
is($stateful->error, 'Unknown error.', 'right error');
