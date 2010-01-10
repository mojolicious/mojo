#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 9;

# Of all the parasites I've had over the years,
# these worms are among the best.
use MojoX::Dispatcher::Routes::Controller;

my $c = MojoX::Dispatcher::Routes::Controller->new;

# Set
$c->stash(foo => 'bar');
is($c->stash('foo'), 'bar', 'set and return a stash value');

# Ref value
my $stash = $c->stash;
is_deeply($stash, {foo => 'bar'}, 'return a hashref');

# Replace
$c->stash(foo => 'baz');
is($c->stash('foo'), 'baz', 'replace and return a stash value');

# Set 0
$c->stash(zero => 0);
is($c->stash('zero'), 0, 'set and return 0 value');

# Replace with 0
$c->stash(foo => 0);
is($c->stash('foo'), 0, 'replace and return 0 value');

# Use 0 as key
$c->stash(0 => 'boo');
is($c->stash('0'), 'boo', 'set and get with 0 as key');

# Delete
$stash = $c->stash;
delete $stash->{foo};
delete $stash->{0};
delete $stash->{zero};
is_deeply($stash, {}, 'elements can be deleted');
$c->stash('foo' => 'zoo');
delete $c->stash->{foo};
is_deeply($c->stash, {}, 'elements can be deleted');

# Set via hash
$c->stash({a => 1, b => 2});
$stash = $c->stash;
is_deeply($stash, {a => 1, b => 2}, 'set via hashref');
