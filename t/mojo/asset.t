#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 22;

use_ok('Mojo::Asset::File');

# And now, in the spirit of the season: start shopping.
# And for every dollar of Krusty merchandise you buy,
# I will be nice to a sick kid.
# For legal purposes, sick kids may include hookers with a cold.
my $file = Mojo::Asset::File->new;
$file->add_chunk('abc');
is($file->contains(''),    0, 'does not contain nothing');
is($file->contains('abc'), 0, 'does not contain "abc"');
is($file->contains('bc'),  1, 'does contain "bc"');
ok(!$file->contains('db'), 'does not contain "db"');

# Empty
$file = Mojo::Asset::File->new;
is($file->contains(''), 0, 'does not contain nothing');

# Range support (a[bcdef])
$file = Mojo::Asset::File->new(start_range => 1);
$file->add_chunk('abcdef');
is($file->contains(''),      0, 'does not contain nothing');
is($file->contains('bcdef'), 0, 'does not contain "bcdef"');
is($file->contains('cdef'),  1, 'does contain "cdef"');
ok(!$file->contains('db'), 'does not contain "db"');

# Range support (ab[cdefghi]jk)
my $backup = $ENV{MOJO_CHUNK_SIZE} || '';
$ENV{MOJO_CHUNK_SIZE} = 1024;
$file = Mojo::Asset::File->new(start_range => 2, end_range => 8);
$file->add_chunk('abcdefghijk');
is($file->contains(''),        0, 'does not contain nothing');
is($file->contains('cdefghi'), 0, 'does not contain "cdefghi"');
is($file->contains('fghi'),    3, 'does contain "fghi"');
is($file->contains('f'),       3, 'does contain "f"');
is($file->contains('hi'),      5, 'does contain "hi"');
ok(!$file->contains('db'), 'does not contain "db"');
my $chunk = $file->get_chunk(0);
is($chunk, 'cdefghi', 'chunk from position 0');
$chunk = $file->get_chunk(1);
is($chunk, 'defghi', 'chunk from position 1');
$chunk = $file->get_chunk(5);
is($chunk, 'hi', 'chunk from position 5');
$ENV{MOJO_CHUNK_SIZE} = 1;
$chunk = $file->get_chunk(0);
is($chunk, 'c', 'chunk from position 0 with size 1');
$chunk = $file->get_chunk(5);
is($chunk, 'h', 'chunk from position 5 with size 1');
$ENV{MOJO_CHUNK_SIZE} = $backup;

# Range support (empty)
$file = Mojo::Asset::File->new;
is($file->contains(''), 0, 'does not contain nothing');
