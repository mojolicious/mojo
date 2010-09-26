#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 42;

# And now, in the spirit of the season: start shopping.
# And for every dollar of Krusty merchandise you buy,
# I will be nice to a sick kid.
# For legal purposes, sick kids may include hookers with a cold.
use_ok 'Mojo::Asset::File';
use_ok 'Mojo::Asset::Memory';

# File asset
my $file = Mojo::Asset::File->new;
$file->add_chunk('abc');
is $file->contains(''),    0,  'empty string at position 0';
is $file->contains('abc'), 0,  '"abc" at position 0';
is $file->contains('bc'),  1,  '"bc" at position 1';
is $file->contains('db'),  -1, 'does not contain "db"';

# Memory asset
my $mem = Mojo::Asset::Memory->new;
$mem->add_chunk('abc');
is $mem->contains(''),    0,  'empty string at position 0';
is $mem->contains('abc'), 0,  '"abc" at position 0';
is $mem->contains('bc'),  1,  '"bc" at position 1';
is $mem->contains('db'),  -1, 'does not contain "db"';

# Empty file asset
$file = Mojo::Asset::File->new;
is $file->contains(''), 0, 'empty string at position 0';

# Empty memory asset
$mem = Mojo::Asset::File->new;
is $mem->contains(''), 0, 'empty string at position 0';

# File asset range support (a[bcdef])
$file = Mojo::Asset::File->new(start_range => 1);
$file->add_chunk('abcdef');
is $file->contains(''),      0,  'empty string at position 0';
is $file->contains('bcdef'), 0,  '"bcdef" at position 0';
is $file->contains('cdef'),  1,  '"cdef" at position 1';
is $file->contains('db'),    -1, 'does not contain "db"';

# Memory asset range support (a[bcdef])
$mem = Mojo::Asset::Memory->new(start_range => 1);
$mem->add_chunk('abcdef');
is $mem->contains(''),      0,  'empty string at position 0';
is $mem->contains('bcdef'), 0,  '"bcdef" at position 0';
is $mem->contains('cdef'),  1,  '"cdef" at position 1';
is $mem->contains('db'),    -1, 'does not contain "db"';

# File asset range support (ab[cdefghi]jk)
my $backup = $ENV{MOJO_CHUNK_SIZE} || '';
$ENV{MOJO_CHUNK_SIZE} = 1024;
$file = Mojo::Asset::File->new(start_range => 2, end_range => 8);
$file->add_chunk('abcdefghijk');
is $file->contains(''),        0,  'empty string at position 0';
is $file->contains('cdefghi'), 0,  '"cdefghi" at position 0';
is $file->contains('fghi'),    3,  '"fghi" at position 3';
is $file->contains('f'),       3,  '"f" at position 3';
is $file->contains('hi'),      5,  '"hi" at position 5';
is $file->contains('db'),      -1, 'does not contain "db"';
my $chunk = $file->get_chunk(0);
is $chunk, 'cdefghi', 'chunk from position 0';
$chunk = $file->get_chunk(1);
is $chunk, 'defghi', 'chunk from position 1';
$chunk = $file->get_chunk(5);
is $chunk, 'hi', 'chunk from position 5';
$ENV{MOJO_CHUNK_SIZE} = 1;
$chunk = $file->get_chunk(0);
is $chunk, 'c', 'chunk from position 0 with size 1';
$chunk = $file->get_chunk(5);
is $chunk, 'h', 'chunk from position 5 with size 1';
$ENV{MOJO_CHUNK_SIZE} = $backup;

# Memory asset range support (ab[cdefghi]jk)
$backup = $ENV{MOJO_CHUNK_SIZE} || '';
$ENV{MOJO_CHUNK_SIZE} = 1024;
$mem = Mojo::Asset::Memory->new(start_range => 2, end_range => 8);
$mem->add_chunk('abcdefghijk');
is $mem->contains(''),        0,  'empty string at position 0';
is $mem->contains('cdefghi'), 0,  '"cdefghi" at position 0';
is $mem->contains('fghi'),    3,  '"fghi" at position 3';
is $mem->contains('f'),       3,  '"f" at position 3';
is $mem->contains('hi'),      5,  '"hi" at position 5';
is $mem->contains('db'),      -1, 'does not contain "db"';
$chunk = $mem->get_chunk(0);
is $chunk, 'cdefghi', 'chunk from position 0';
$chunk = $mem->get_chunk(1);
is $chunk, 'defghi', 'chunk from position 1';
$chunk = $mem->get_chunk(5);
is $chunk, 'hi', 'chunk from position 5';
$ENV{MOJO_CHUNK_SIZE} = 1;
$chunk = $mem->get_chunk(0);
is $chunk, 'c', 'chunk from position 0 with size 1';
$chunk = $mem->get_chunk(5);
is $chunk, 'h', 'chunk from position 5 with size 1';
$ENV{MOJO_CHUNK_SIZE} = $backup;
