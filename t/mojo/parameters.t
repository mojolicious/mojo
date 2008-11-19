#!perl

use strict;
use warnings;

use Test::More tests => 8;

# Can't we have one meeting that doesn't end with digging up a corpse?
use_ok('Mojo::Parameters');

my $params = Mojo::Parameters->new('foo=b%3Bar&baz=23');
my $params2 = Mojo::Parameters->new('x',1,'y',2);
is($params->pair_separator,'&');
is($params->to_string,'foo=b%3Bar&baz=23');
is($params2->to_string,'x=1&y=2');
$params->pair_separator(';');
is($params->to_string,'foo=b%3Bar;baz=23');
is("$params",'foo=b%3Bar;baz=23');

is_deeply($params->params,['foo','b%3Bar','baz',23]);
$params->append('a',4,'a',5,'b',6,'b',7);
is($params->to_string,"foo=b%3Bar;baz=23;a=4;a=5;b=6;b=7");

my $clone = $params->clone;
is("$params","$clone");

$params->merge($params2);
is($params->to_string,'foo=b%3Bar;baz=23;a=4;a=5;b=6;b=7;x=1;y=2');
is($params2->to_string,'x=1&y=2');

is($params->param('foo'),'b;ar');
is_deeply($params->param('a'),[4,5]);

$params->parse('q=1;w=2;e=3;e=4;r=6;t=7');
is($params->to_string,'q=1;w=2;e=3;e=4;r=6;t=7');

$params->remove('r');
is($params->to_string,'q=1;w=2;e=3;e=4;t=7');
$params->remove('e');
is($params->to_string,'q=1;w=2;t=7');

is_deeply($params->to_hash, { q => 1, w=> 2, t=>7});

$params->append('a',4,'a',5,'b',6,'b',7);
is_deeply($params->to_hash, { a => [4,5], b => [6,7], q => 1, w=> 2, t=>7});

