#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 92;

use Mojo::ByteStream 'b';

# We should be safe up here. I'm pretty sure fires can't climb trees.
use_ok('Mojo::JSON');

my $json = Mojo::JSON->new;

# Decode array
my $array = $json->decode('[]');
is_deeply($array, []);
$array = $json->decode('[ [ ]]');
is_deeply($array, [[]]);

# Decode number
$array = $json->decode('[0]');
is_deeply($array, [0], 'decode [0]');
$array = $json->decode('[1]');
is_deeply($array, [1]);
$array = $json->decode('[ -122.026020 ]');
is_deeply($array, ['-122.026020']);
$array = $json->decode('[0.0]');
isa_ok($array, 'ARRAY');
cmp_ok($array->[0], '==', 0);
$array = $json->decode('[0e0]');
isa_ok($array, 'ARRAY');
cmp_ok($array->[0], '==', 0);
$array = $json->decode('[1,-2]');
is_deeply($array, [1, -2]);
$array = $json->decode('[10e12 , [2 ]]');
is_deeply($array, ['10e12', [2]]);
$array = $json->decode('[37.7668 , [ 20 ]] ');
is_deeply($array, [37.7668, [20]]);
$array = $json->decode('[1e3]');
isa_ok($array, 'ARRAY');
cmp_ok($array->[0], '==', 1e3);

# Decode name
$array = $json->decode('[true]');
is_deeply($array, [$json->true]);
$array = $json->decode('[null]');
is_deeply($array, [undef]);
$array = $json->decode('[true, false]');
is_deeply($array, [$json->true, $json->false]);

# Decode string
$array = $json->decode('[" "]');
is_deeply($array, [' ']);
$array = $json->decode('["hello world!"]');
is_deeply($array, ['hello world!']);
$array = $json->decode('["hello\nworld!"]');
is_deeply($array, ["hello\nworld!"]);
$array = $json->decode('["hello\t\"world!"]');
is_deeply($array, ["hello\t\"world!"]);
$array = $json->decode('["hello\u0152world\u0152!"]');
is_deeply($array, ["hello\x{0152}world\x{0152}!"]);
$array = $json->decode('["0."]');
is_deeply($array, ['0.']);
$array = $json->decode('[" 0"]');
is_deeply($array, [' 0']);
$array = $json->decode('["1"]');
is_deeply($array, ['1']);

# Decode object
my $hash = $json->decode('{}');
is_deeply($hash, {});
$hash = $json->decode('{"foo": "bar"}');
is_deeply($hash, {foo => 'bar'});
$hash = $json->decode('{"foo": [23, "bar"]}');
is_deeply($hash, {foo => [qw/23 bar/]});

# Decode full spec example
$hash = $json->decode(<<EOF);
{
   "Image": {
       "Width":  800,
       "Height": 600,
       "Title":  "View from 15th Floor",
       "Thumbnail": {
           "Url":    "http://www.example.com/image/481989943",
           "Height": 125,
           "Width":  "100"
       },
       "IDs": [116, 943, 234, 38793]
    }
}
EOF
is($hash->{Image}->{Width},  800);
is($hash->{Image}->{Height}, 600);
is($hash->{Image}->{Title},  'View from 15th Floor');
is( $hash->{Image}->{Thumbnail}->{Url},
    'http://www.example.com/image/481989943'
);
is($hash->{Image}->{Thumbnail}->{Height}, 125);
is($hash->{Image}->{Thumbnail}->{Width},  100);
is($hash->{Image}->{IDs}->[0],            116);
is($hash->{Image}->{IDs}->[1],            943);
is($hash->{Image}->{IDs}->[2],            234);
is($hash->{Image}->{IDs}->[3],            38793);

# Encode array
my $string = $json->encode([]);
is($string, '[]');
$string = $json->encode([[]]);
is($string, '[[]]');
$string = $json->encode([[], []]);
is($string, '[[],[]]');
$string = $json->encode([[], [[]], []]);
is($string, '[[],[[]],[]]');

# Encode string
$string = $json->encode(['foo']);
is($string, '["foo"]');
$string = $json->encode(["hello\nworld!"]);
is($string, '["hello\nworld!"]');
$string = $json->encode(["hello\t\"world!"]);
is($string, '["hello\t\"world!"]');
$string = $json->encode(["hello\x{0003}\x{0152}world\x{0152}!"]);
is(b($string)->decode('UTF-8'), "[\"hello\\u0003\x{0152}world\x{0152}!\"]");
$string = $json->encode(["123abc"]);
is($string, '["123abc"]');

# Encode object
$string = $json->encode({});
is($string, '{}');
$string = $json->encode({foo => {}});
is($string, '{"foo":{}}');
$string = $json->encode({foo => 'bar'});
is($string, '{"foo":"bar"}');
$string = $json->encode({foo => []});
is($string, '{"foo":[]}');
$string = $json->encode({foo => ['bar']});
is($string, '{"foo":["bar"]}');

# Encode name
$string = $json->encode([$json->true]);
is($string, '[true]');
$string = $json->encode([undef]);
is($string, '[null]');
$string = $json->encode([$json->true, $json->false]);
is($string, '[true,false]');

# Encode number
$string = $json->encode([1]);
is($string, '[1]');
$string = $json->encode(['-122.026020']);
is($string, '[-122.026020]');
$string = $json->encode([1, -2]);
is($string, '[1,-2]');
$string = $json->encode(['10e12', [2]]);
is($string, '[10e12,[2]]');
$string = $json->encode([37.7668, [20]]);
is($string, '[37.7668,[20]]');

# Faihu roundtrip
$string = $json->encode(["\x{10346}"]);
is(b($string)->decode('UTF-8'), "[\"\x{10346}\"]");
$array = $json->decode($string);
is_deeply($array, ["\x{10346}"]);

# Decode UTF-16LE
$array = $json->decode(b("\x{feff}[true]")->encode('UTF-16LE'));
is_deeply($array, [$json->true]);

# Decode UTF-16LE with faihu surrogate pair
$array = $json->decode(b("\x{feff}[\"\\ud800\\udf46\"]")->encode('UTF-16LE'));
is_deeply($array, ["\x{10346}"]);

# Decode UTF-16BE with faihu surrogate pair
$array = $json->decode(b("\x{feff}[\"\\ud800\\udf46\"]")->encode('UTF-16BE'));
is_deeply($array, ["\x{10346}"]);

# Decode UTF-32LE
$array = $json->decode(b("\x{feff}[true]")->encode('UTF-32LE'));
is_deeply($array, [$json->true]);

# Decode UTF-32BE
$array = $json->decode(b("\x{feff}[true]")->encode('UTF-32BE'));
is_deeply($array, [$json->true]);

# Decode UTF-16LE without BOM
$array = $json->decode(b("[\"\\ud800\\udf46\"]")->encode('UTF-16LE'));
is_deeply($array, ["\x{10346}"]);

# Decode UTF-16BE without BOM
$array = $json->decode(b("[\"\\ud800\\udf46\"]")->encode('UTF-16BE'));
is_deeply($array, ["\x{10346}"]);

# Decode UTF-32LE without BOM
$array = $json->decode(b("[\"\\ud800\\udf46\"]")->encode('UTF-32LE'));
is_deeply($array, ["\x{10346}"]);

# Decode UTF-32BE without BOM
$array = $json->decode(b("[\"\\ud800\\udf46\"]")->encode('UTF-32BE'));
is_deeply($array, ["\x{10346}"]);

# Complicated roudtrips
$string = '[null,false,true,"",0,1]';
$array  = $json->decode($string);
isa_ok($array, 'ARRAY');
is($json->encode($array), $string);
$array = [undef, 0, 1, '', $json->true, $json->false];
$string = $json->encode($array);
ok($string);
is_deeply($json->decode($string), $array);

# Errors
is($json->decode('[[]'),    undef);
is($json->error,            'Missing right square bracket near end of file.');
is($json->decode('{{}'),    undef);
is($json->error,            'Missing right curly bracket near end of file.');
is($json->decode('[[]...'), undef);
is($json->error,            'Syntax error near "...".');
is($json->decode('{{}...'), undef);
is($json->error,            'Syntax error near "...".');
is($json->decode('[nan]'),  undef);
is($json->error,            'Syntax error near "nan]".');
is($json->decode('["foo]'), undef);
is($json->error,            'Syntax error near ""foo]".');
is($json->decode('false'),  undef);
is($json->error,      'JSON text has to be a serialized object or array.');
is($json->decode(''), undef);
is($json->error,      'JSON text has to be a serialized object or array.');
