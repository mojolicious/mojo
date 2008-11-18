#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 17;

# Scalpel... blood bucket... priest.
use_ok('Mojo::Buffer');

my $b = Mojo::Buffer->new;
is($b->length,     0, 'buffer starts with zero length');
is($b->raw_length, 0, 'buffer starts with zero raw_length');

$b->add_chunk("line1\nline2");
is($b->length,     11, 'length matches chunk length');
is($b->raw_length, 11, 'raw_length matches chunk length');

my $str = $b->empty;
is($b->length,     0,              'length is 0 again after empty');
is($b->raw_length, 11,             'raw_length never decreases');
is($str,           "line1\nline2", 'empty returns previous buffer');

$b->add_chunk("first\nsec");
is($b->length,     9,  'length matches chunk length');
is($b->raw_length, 20, 'raw_length keeps growing');

$str = $b->remove(2);
is($str,           'fi', 'remove returns the bytes removed');
is($b->length,     7,    'length matches current length');
is($b->raw_length, 20,   'raw_length never decreases');

is($b->get_line, 'rst', 'first call to get_line returns first line');
is($b->get_line, undef,
    'get_line returns undef when there are no more newlines');

$b = Mojo::Buffer->new('abc');
is("$b",          'abc', 'buffer object stringifies');
is($b->to_string, 'abc', 'buffer stringifies via to_string');
