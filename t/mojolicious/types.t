use Mojo::Base -strict;

use Test::More tests => 13;

# "Your mistletoe is no match for my *tow* missile."
use_ok 'Mojolicious::Types';

# Basics
my $t = Mojolicious::Types->new;
is $t->type('json'), 'application/json', 'right type';
is $t->type('foo'), undef, 'no type';
$t->type(foo => 'foo/bar');
is $t->type('foo'), 'foo/bar', 'right type';

# Detection
is_deeply $t->detect('text/html'),       ['htm', 'html'], 'right formats';
is_deeply $t->detect('text/html;q=0.9'), ['htm', 'html'], 'right formats';
is_deeply $t->detect('text/html,*/*'),             [], 'no formats';
is_deeply $t->detect('text/html;q=0.9,*/*'),       [], 'no formats';
is_deeply $t->detect('text/html,*/*;q=0.9'),       [], 'no formats';
is_deeply $t->detect('text/html;q=0.8,*/*;q=0.9'), [], 'no formats';
is_deeply $t->detect('application/octet-stream'), ['bin'],  'right formats';
is_deeply $t->detect('application/x-font-woff'),  ['woff'], 'right formats';
is_deeply $t->detect('application/atom+xml'),     ['atom'], 'right formats';
