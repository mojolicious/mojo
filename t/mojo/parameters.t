#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 35;

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
is_deeply($params->params, ['foo', 'b;ar', 'baz', 23]);
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
is_deeply($params->param('foo'), 'b;ar');
is_deeply([$params->param('a')], [4, 5]);

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

# List names
is_deeply([$params->param], [qw/q t w/]);

# Append
$params->append('a', 4, 'a', 5, 'b', 6, 'b', 7);
is_deeply($params->to_hash,
    {a => [4, 5], b => [6, 7], q => 1, w => 2, t => 7});

# 0 value
$params = Mojo::Parameters->new(foo => 0);
is_deeply($params->param('foo'), 0);
is($params->to_string, 'foo=0');
$params = Mojo::Parameters->new($params->to_string);
is_deeply($params->param('foo'), 0);
is($params->to_string, 'foo=0');

# Reconstruction
$params = Mojo::Parameters->new('foo=bar&baz=23');
is("$params", 'foo=bar&baz=23');
$params = Mojo::Parameters->new('foo=bar;baz=23');
is("$params", 'foo=bar;baz=23');

# Undefined params
$params = Mojo::Parameters->new;
$params->append('c',   undef);
$params->append(undef, 'c');
$params->append(undef, undef);
is($params->to_string, "c=&=c&=");
is_deeply($params->to_hash, {c => '', '' => ['c', '']});
$params->remove('c');
is($params->to_string, "=c&=");
$params->remove(undef);
ok(not defined $params->to_string);

# +
$params = Mojo::Parameters->new('foo=%2B');
is($params->param('foo'), '+');
is_deeply($params->to_hash, {foo => '+'});
$params->param('foo ' => 'a');
is($params->to_string, "foo=%2B&foo+=a");
$params->remove('foo ');
is_deeply($params->to_hash, {foo => '+'});
$params->append('1 2', '3+3');
is($params->param('1 2'), '3+3');
is_deeply($params->to_hash, {foo => '+', '1 2' => '3+3'});
