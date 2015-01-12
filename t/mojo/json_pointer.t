use Mojo::Base -strict;

use Test::More;
use Mojo::JSON::Pointer;

# "contains" (hash)
my $pointer = Mojo::JSON::Pointer->new({foo => 23});
ok $pointer->contains(''),     'contains ""';
ok $pointer->contains('/foo'), 'contains "/foo"';
ok !$pointer->contains('/bar'), 'does not contains "/bar"';
ok $pointer->new({foo => {bar => undef}})->contains('/foo/bar'),
  'contains "/foo/bar"';

# "contains" (mixed)
$pointer = Mojo::JSON::Pointer->new({foo => [0, 1, 2]});
ok $pointer->contains(''),       'contains ""';
ok $pointer->contains('/foo/0'), 'contains "/foo/0"';
ok !$pointer->contains('/foo/9'),   'does not contain "/foo/9"';
ok !$pointer->contains('/foo/bar'), 'does not contain "/foo/bar"';
ok !$pointer->contains('/0'),       'does not contain "/0"';

# "get" (hash)
$pointer = Mojo::JSON::Pointer->new({foo => 'bar'});
is_deeply $pointer->get(''), {foo => 'bar'}, '"" is "{foo => "bar"}"';
is $pointer->get('/foo'), 'bar', '"/foo" is "bar"';
is $pointer->new({foo => {bar => 42}})->get('/foo/bar'), 42,
  '"/foo/bar" is "42"';
is_deeply $pointer->new({foo => {23 => {baz => 0}}})->get('/foo/23'),
  {baz => 0}, '"/foo/23" is "{baz => 0}"';

# "get" (mixed)
is_deeply $pointer->new({foo => {bar => [1, 2, 3]}})->get('/foo/bar'),
  [1, 2, 3], '"/foo/bar" is "[1, 2, 3]"';
$pointer = Mojo::JSON::Pointer->new({foo => {bar => [0, undef, 3]}});
is $pointer->get('/foo/bar/0'), 0,     '"/foo/bar/0" is "0"';
is $pointer->get('/foo/bar/1'), undef, '"/foo/bar/1" is "undef"';
is $pointer->get('/foo/bar/2'), 3,     '"/foo/bar/2" is "3"';
is $pointer->get('/foo/bar/6'), undef, '"/foo/bar/6" is "undef"';

# "get" (encoded)
is $pointer->new([{'foo/bar' => 'bar'}])->get('/0/foo~1bar'), 'bar',
  '"/0/foo~1bar" is "bar"';
is $pointer->new([{'foo/bar/baz' => 'yada'}])->get('/0/foo~1bar~1baz'),
  'yada', '"/0/foo~1bar~1baz" is "yada"';
is $pointer->new([{'foo~/bar' => 'bar'}])->get('/0/foo~0~1bar'), 'bar',
  '"/0/foo~0~1bar" is "bar"';
is $pointer->new([{'f~o~o~/b~' => {'a~' => {'r' => 'baz'}}}])
  ->get('/0/f~0o~0o~0~1b~0/a~0/r'), 'baz',
  '"/0/f~0o~0o~0~1b~0/a~0/r" is "baz"';
is $pointer->new({'~1' => 'foo'})->get('/~01'), 'foo', '"/~01" is "foo"';

# Unicode
is $pointer->new({'☃' => 'snowman'})->get('/☃'), 'snowman',
  'found the snowman';
is $pointer->new->data({'☃' => ['snowman']})->get('/☃/0'), 'snowman',
  'found the snowman';

# RFC 6901
my $hash = {
  foo    => ['bar', 'baz'],
  ''     => 0,
  'a/b'  => 1,
  'c%d'  => 2,
  'e^f'  => 3,
  'g|h'  => 4,
  'i\\j' => 5,
  'k"l'  => 6,
  ' '    => 7,
  'm~n'  => 8
};
$pointer = Mojo::JSON::Pointer->new($hash);
is_deeply $pointer->get(''), $hash, 'empty pointer is whole document';
is_deeply $pointer->get('/foo'), ['bar', 'baz'], '"/foo" is "["bar", "baz"]"';
is $pointer->get('/foo/0'), 'bar', '"/foo/0" is "bar"';
is $pointer->get('/'),      0,     '"/" is 0';
is $pointer->get('/a~1b'),  1,     '"/a~1b" is 1';
is $pointer->get('/c%d'),   2,     '"/c%d" is 2';
is $pointer->get('/e^f'),   3,     '"/e^f" is 3';
is $pointer->get('/g|h'),   4,     '"/g|h" is 4';
is $pointer->get('/i\\j'),  5,     '"/i\\\\j" is 5';
is $pointer->get('/k"l'),   6,     '"/k\\"l" is 6';
is $pointer->get('/ '),     7,     '"/ " is 7';
is $pointer->get('/m~0n'),  8,     '"/m~0n" is 8';

done_testing();
