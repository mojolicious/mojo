#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 8;

# Now that's a wave of destruction that's easy on the eyes.
use_ok('Mojo::Parameters');

# Basics with custom pair separator
my $params = Mojo::Parameters->new('foo=b%3Bar&baz=23');
my $params2 = Mojo::Parameters->new('x', 1, 'y', 2);
is($params->pair_separator, '&');
is($params->to_string,      'foo=b%3Bar&baz=23');
is($params2->to_string,     'x=1&y=2');
$params->pair_separator(';');
is($params->to_string, 'foo=b%3Bar;baz=23');
is("$params",          'foo=b%3Bar;baz=23');

# Append
is_deeply($params->params, ['foo', 'b%3Bar', 'baz', 23]);
$params->append('a', 4, 'a', 5, 'b', 6, 'b', 7);
is($params->to_string, "foo=b%3Bar;baz=23;a=4;a=5;b=6;b=7");

# Clone
my $clone = $params->clone;
is("$params", "$clone");

# Merge
$params->merge($params2);
is($params->to_string,  'foo=b%3Bar;baz=23;a=4;a=5;b=6;b=7;x=1;y=2');
is($params2->to_string, 'x=1&y=2');

# Param
is_deeply($params->param('foo'), ['b;ar']);
is_deeply($params->param('a'), [4, 5]);

# Parse with ";" separator
$params->parse('q=1;w=2;e=3;e=4;r=6;t=7');
is($params->to_string, 'q=1;w=2;e=3;e=4;r=6;t=7');

# Remove
$params->remove('r');
is($params->to_string, 'q=1;w=2;e=3;e=4;t=7');
$params->remove('e');
is($params->to_string, 'q=1;w=2;t=7');

# Hash
is_deeply($params->to_hash, {q => 1, w => 2, t => 7});

# Append
$params->append('a', 4, 'a', 5, 'b', 6, 'b', 7);
is_deeply($params->to_hash,
    {a => [4, 5], b => [6, 7], q => 1, w => 2, t => 7});
