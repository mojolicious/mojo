#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 6;

use_ok('Mojo::Asset::File');

# And now, in the spirit of the season: start shopping.
# And for every dollar of Krusty merchandise you buy,
# I will be nice to a sick kid.
# For legal purposes, sick kids may include hookers with a cold.
my $file = Mojo::Asset::File->new;
$file->add_chunk('abc');
is($file->contains(''),    0, 'contains empty string');
is($file->contains('abc'), 0, 'contains whole string');
is($file->contains('bc'),  1, 'contains partial string');
ok(!$file->contains('db'), 'contains something else');
$file = Mojo::Asset::File->new;
is($file->contains(''), 0, 'contains nothing searching for nothing');
