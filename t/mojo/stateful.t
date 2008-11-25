#!perl

use strict;
use warnings;

use Test::More tests => 21;

use_ok('Mojo::Stateful');

# basic stuff
my $stateful = Mojo::Stateful->new;
ok($stateful);
is($stateful->state, 'start');
ok(!$stateful->is_done);

# is_state
ok($stateful->is_state(qw( start )));
ok($stateful->is_state(qw( start other )));
ok(!$stateful->is_state(qw( neither other )));


# change state
$stateful->state('connected');
is($stateful->state, 'connected');
ok($stateful->is_state(qw( another connected )));
ok(!$stateful->is_done);


# errors
ok(!defined($stateful->error));
ok(!$stateful->has_error);

$stateful->error('Oops');
ok($stateful->error);
ok($stateful->has_error);
is($stateful->error, 'Oops');
is($stateful->state, 'error');
ok($stateful->is_state(qw( error another )));
ok(!$stateful->is_done);


# done
$stateful->done;
is($stateful->state, 'done');
ok($stateful->is_state(qw( another done error )));
ok($stateful->is_done);
