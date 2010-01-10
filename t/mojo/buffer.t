#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 17;

# Scalpel... blood bucket... priest.
use_ok('Mojo::Buffer');

my $b = Mojo::Buffer->new;
is($b->size,     0, 'buffer starts with zero length');
is($b->raw_size, 0, 'buffer starts with zero raw_size');

$b->add_chunk("line1\nline2");
is($b->size,     11, 'length matches chunk length');
is($b->raw_size, 11, 'raw_size matches chunk length');

my $str = $b->empty;
is($b->size,     0,              'length is 0 again after empty');
is($b->raw_size, 11,             'raw_size never decreases');
is($str,         "line1\nline2", 'empty returns previous buffer');

$b->add_chunk("first\nsec");
is($b->size,     9,  'length matches chunk length');
is($b->raw_size, 20, 'raw_size keeps growing');

$str = $b->remove(2);
is($str,         'fi', 'remove returns the bytes removed');
is($b->size,     7,    'length matches current length');
is($b->raw_size, 20,   'raw_size never decreases');

is($b->get_line, 'rst', 'first call to get_line returns first line');
is($b->get_line, undef,
    'get_line returns undef when there are no more newlines');

$b = Mojo::Buffer->new->add_chunk('abc');
is("$b",          'abc', 'buffer object stringifies');
is($b->to_string, 'abc', 'buffer stringifies via to_string');
