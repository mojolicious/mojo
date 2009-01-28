#!perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 5;

# Of all the parasites I've had over the years,
# these worms are among the best.
use MojoX::Context;

my $c = MojoX::Context->new;

# Set
$c->stash(foo => 'bar');
is($c->stash('foo'), 'bar', 'set and return a stash value');

# Ref value
my $stash = $c->stash;
is_deeply($stash, {foo => 'bar'}, 'return a hashref');

# Delete
$stash = $c->stash;
delete $stash->{foo};
is_deeply($stash, {}, 'elements can be deleted');
$c->stash('foo' => 'zoo');
delete $c->stash->{foo};
is_deeply($c->stash, {}, 'elements can be deleted');

# Set via hash
$c->stash({a => 1, b => 2});
$stash = $c->stash;
is_deeply($stash, {a => 1, b => 2}, 'set via hashref');
