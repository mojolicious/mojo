use Mojo::Base -strict;

use utf8;

use Test::More;
use Mojo::JSON::Pointer;

# "contains" (hash)
my $pointer = Mojo::JSON::Pointer->new;
ok $pointer->contains({foo => 23}, ''),     'contains ""';
ok $pointer->contains({foo => 23}, '/foo'), 'contains "/foo"';
ok !$pointer->contains({foo => 23}, '/bar'), 'does not contains "/bar"';
ok $pointer->contains({foo => {bar => undef}}, '/foo/bar'),
  'contains "/foo/bar"';

# "contains" (mixed)
ok $pointer->contains({foo => [0, 1, 2]}, ''),       'contains ""';
ok $pointer->contains({foo => [0, 1, 2]}, '/foo/0'), 'contains "/foo/0"';
ok !$pointer->contains({foo => [0, 1, 2]}, '/foo/9'),
  'does not contain "/foo/9"';
ok !$pointer->contains({foo => [0, 1, 2]}, '/foo/bar'),
  'does not contain "/foo/bar"';
ok !$pointer->contains({foo => [0, 1, 2]}, '/0'), 'does not contain "/0"';

# "get" (hash)
is_deeply $pointer->get({foo => 'bar'}, ''), {foo => 'bar'},
  '"" is "{foo => "bar"}"';
is $pointer->get({foo => 'bar'}, '/foo'), 'bar', '"/foo" is "bar"';
is $pointer->get({foo => {bar => 42}}, '/foo/bar'), 42, '"/foo/bar" is "42"';
is_deeply $pointer->get({foo => {23 => {baz => 0}}}, '/foo/23'), {baz => 0},
  '"/foo/23" is "{baz => 0}"';

# "get" (mixed)
is_deeply $pointer->get({foo => {bar => [1, 2, 3]}}, '/foo/bar'), [1, 2, 3],
  '"/foo/bar" is "[1, 2, 3]"';
is $pointer->get({foo => {bar => [0, undef, 3]}}, '/foo/bar/0'), 0,
  '"/foo/bar/0" is "0"';
is $pointer->get({foo => {bar => [0, undef, 3]}}, '/foo/bar/1'), undef,
  '"/foo/bar/1" is "undef"';
is $pointer->get({foo => {bar => [0, undef, 3]}}, '/foo/bar/2'), 3,
  '"/foo/bar/2" is "3"';
is $pointer->get({foo => {bar => [0, undef, 3]}}, '/foo/bar/6'), undef,
  '"/foo/bar/6" is "undef"';

# "get" (encoded)
is $pointer->get({'♥' => [0, 1]}, '/%E2%99%A5/0'), 0,
  '"/%E2%99%A5/0" is "0"';
is $pointer->get([{'^foob ar' => 'foo'}], '/0/^foob ar'), 'foo',
  '"/0/^foob ar" is "foo"';
is $pointer->get([{'foob ar' => 'foo'}], '/0/foob%20ar'), 'foo',
  '"/0/foob%20ar" is "foo"';
is $pointer->get([{'foo/bar' => 'bar'}], '/0/foo%2Fbar'), undef,
  '"/0/foo%2Fbar" is "undef"';
is $pointer->get([{'foo/bar' => 'bar'}], '/0/foo~1bar'), 'bar',
  '"/0/foo~1bar" is "bar"';
is $pointer->get([{'foo/bar/baz' => 'yada'}], '/0/foo~1bar~1baz'), 'yada',
  '"/0/foo~1bar~1baz" is "yada"';
is $pointer->get([{'foo~/bar' => 'bar'}], '/0/foo~0~1bar'), 'bar',
  '"/0/foo~0~1bar" is "bar"';
is $pointer->get([{'foo~/bar' => 'bar'}], '/0/foo%7E%30%7E%31bar'), 'bar',
  '"/0/foo%7E%30%7E%31bar" is "bar"';
is $pointer->get(
  [{'f~o~o~/b~' => {'a~' => {'r' => 'baz'}}}] => '/0/f~0o~0o~0~1b~0/a~0/r'),
  'baz', '"/0/f~0o~0o~0~1b~0/a~0/r" is "baz"';

done_testing();
