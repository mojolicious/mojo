#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 20;

use_ok('Mojo::Asset::File');

# And now, in the spirit of the season: start shopping.
# And for every dollar of Krusty merchandise you buy,
# I will be nice to a sick kid.
# For legal purposes, sick kids may include hookers with a cold.
my $file = Mojo::Asset::File->new;
$file->add_chunk('abc');
is($file->contains(''),    0);
is($file->contains('abc'), 0);
is($file->contains('bc'),  1);
ok(!$file->contains('db'));

# Empty
$file = Mojo::Asset::File->new;
is($file->contains(''), 0);

# Range support (a[bcdef])
$file = Mojo::Asset::File->new(start_range => 1);
$file->add_chunk('abcdef');
is($file->contains(''),      0);
is($file->contains('bcdef'), 0);
is($file->contains('cdef'),  1);
ok(!$file->contains('db'));

# Range support (ab[cdefghi]jk)
$file = Mojo::Asset::File->new(start_range => 2, end_range => 8);
$file->add_chunk('abcdefghijk');
is($file->contains(''),        0);
is($file->contains('cdefghi'), 0);
is($file->contains('fghi'),    3);
is($file->contains('f'),       3);
is($file->contains('hi'),      5);
ok(!$file->contains('db'));
my $chunk = $file->get_chunk(0);
is($chunk, 'cdefghi');
$chunk = $file->get_chunk(1);
is($chunk, 'defghi');
$chunk = $file->get_chunk(5);
is($chunk, 'hi');

# Range support (empty)
$file = Mojo::Asset::File->new;
is($file->contains(''), 0);
