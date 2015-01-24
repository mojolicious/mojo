use Mojo::Base -strict;

use Test::More;
use Mojo::Parameters;

# Basic functionality
my $params = Mojo::Parameters->new('foo=b%3Bar&baz=23');
my $params2 = Mojo::Parameters->new('x', 1, 'y', 2);
is $params->to_string,  'foo=b%3Bar&baz=23', 'right format';
is $params2->to_string, 'x=1&y=2',           'right format';
is $params->to_string,  'foo=b%3Bar&baz=23', 'right format';
is_deeply $params->params, ['foo', 'b;ar', 'baz', 23], 'right structure';
$params->append(a => 4, a => 5, b => 6, b => 7);
is $params->to_string, 'foo=b%3Bar&baz=23&a=4&a=5&b=6&b=7', 'right format';
push @$params, c => 'f;oo';
is $params->to_string, 'foo=b%3Bar&baz=23&a=4&a=5&b=6&b=7&c=f%3Boo',
  'right format';
is $params->remove('a')->to_string, 'foo=b%3Bar&baz=23&b=6&b=7&c=f%3Boo',
  'right format';

# Clone
my $clone = $params->clone;
is "$params", "$clone", 'equal parameters';
push @$clone, c => 9;
isnt "$params", "$clone", 'unequal parameters';

# Merge
$params = Mojo::Parameters->new('foo=b%3Bar&baz=23&a=4&a=5&b=6&b=7&c=f%3Boo');
$params->merge($params2);
is $params->to_string, 'foo=b%3Bar&baz=23&a=4&a=5&b=6&b=7&c=f%3Boo&x=1&y=2',
  'right format';
is $params2->to_string, 'x=1&y=2', 'right format';
is $params->merge(baz => undef)->to_string,
  'foo=b%3Bar&a=4&a=5&b=6&b=7&c=f%3Boo&x=1&y=2', 'right format';
is $params->merge(y => 3, z => [4, 5])->to_string,
  'foo=b%3Bar&a=4&a=5&b=6&b=7&c=f%3Boo&x=1&y=3&z=4&z=5', 'right format';
is $params->merge(Mojo::Parameters->new(z => 6))->to_string,
  'foo=b%3Bar&a=4&a=5&b=6&b=7&c=f%3Boo&x=1&y=3&z=6', 'right format';

# Param
$params
  = Mojo::Parameters->new('foo=b%3Bar&a=4&a=5&b=6&b=7&c=f%3Boo&x=1&y=3&z=6');
is_deeply $params->param('foo'), 'b;ar', 'right structure';
is_deeply $params->every_param('foo'), ['b;ar'], 'right structure';
is_deeply $params->every_param('a'), [4, 5], 'right structure';
is_deeply [$params->param(['a'])], [5], 'right structure';
is_deeply [$params->param([qw(a foo)])], [5, 'b;ar'], 'right structure';
$params->param(foo => 'bar');
is_deeply [$params->param('foo')], ['bar'], 'right structure';
is_deeply $params->param(foo => qw(baz yada))->every_param('foo'),
  [qw(baz yada)], 'right structure';
is_deeply [$params->param], [qw(a b c foo x y z)], 'right structure';

# Append
$params = Mojo::Parameters->new('q=1');
$params->append(a => 4, a => 5, b => 6, b => 7);
is_deeply $params->to_hash, {a => [4, 5], b => [6, 7], q => 1},
  'right structure';
is_deeply [$params->param], [qw(a b q)], 'right structure';
$params = Mojo::Parameters->new(foo => '', bar => 'bar');
is $params->to_string, 'foo=&bar=bar', 'right format';
$params = Mojo::Parameters->new(bar => 'bar', foo => '');
is $params->to_string, 'bar=bar&foo=', 'right format';
is $params->append($params2)->to_string, 'bar=bar&foo=&x=1&y=2',
  'right format';
is $params2->to_string, 'x=1&y=2', 'right format';

# "0"
$params = Mojo::Parameters->new(0 => 0);
is $params->param(0), 0, 'right value';
is_deeply $params->every_param(0), [0], 'right value';
is_deeply $params->every_param('foo'), [], 'no values';
is $params->to_string, '0=0', 'right format';
$params = Mojo::Parameters->new($params->to_string);
is $params->param(0), 0, 'right value';
is_deeply $params->every_param(0), [0], 'right value';
is $params->to_hash->{0}, 0, 'right value';
is_deeply $params->to_hash, {0 => 0}, 'right structure';
is $params->to_string, '0=0', 'right format';

# Semicolon
$params = Mojo::Parameters->new('foo=bar;baz');
is $params->to_string, 'foo=bar;baz', 'right format';
is_deeply $params->params, [foo => 'bar;baz'], 'right structure';
is_deeply $params->to_hash, {foo => 'bar;baz'}, 'right structure';
is $params->to_string, 'foo=bar%3Bbaz', 'right format';
$params = Mojo::Parameters->new($params->to_string);
is_deeply $params->params, [foo => 'bar;baz'], 'right structure';
is_deeply $params->to_hash, {foo => 'bar;baz'}, 'right structure';
is $params->to_string, 'foo=bar%3Bbaz', 'right format';

# Reconstruction
$params = Mojo::Parameters->new('foo=bar&baz=23');
is "$params", 'foo=bar&baz=23', 'right format';
$params = Mojo::Parameters->new('foo=bar;baz=23');
is "$params", 'foo=bar;baz=23', 'right format';

# Empty params
$params = Mojo::Parameters->new('c=');
is $params->to_hash->{c}, '', 'right value';
is_deeply $params->to_hash, {c => ''}, 'right structure';
$params = Mojo::Parameters->new('c=&c=&d');
is_deeply $params->to_hash->{c}, ['', ''], 'right values';
is $params->to_hash->{d}, '', 'right value';
is_deeply $params->to_hash, {c => ['', ''], d => ''}, 'right structure';
$params = Mojo::Parameters->new('c&d=0&e=');
is $params->to_hash->{c}, '', 'right value';
is $params->to_hash->{d}, 0,  'right value';
is $params->to_hash->{e}, '', 'right value';
is_deeply $params->to_hash, {c => '', d => 0, e => ''}, 'right structure';

# "+"
$params = Mojo::Parameters->new('foo=%2B');
is $params->param('foo'), '+', 'right value';
is_deeply $params->to_hash, {foo => '+'}, 'right structure';
$params->param('foo ' => 'a');
is $params->to_string, 'foo=%2B&foo+=a', 'right format';
$params->remove('foo ');
is_deeply $params->to_hash, {foo => '+'}, 'right structure';
$params->append('1 2', '3+3');
is $params->param('1 2'), '3+3', 'right value';
is_deeply $params->to_hash, {foo => '+', '1 2' => '3+3'}, 'right structure';
$params = Mojo::Parameters->new('a=works+too');
is "$params", 'a=works+too', 'right format';
is_deeply $params->to_hash, {a => 'works too'}, 'right structure';
is $params->param('a'), 'works too', 'right value';
is "$params", 'a=works+too', 'right format';

# Array values
$params = Mojo::Parameters->new;
$params->append(foo => [qw(bar baz)], bar => [qw(bas test)], a => 'b');
is_deeply $params->every_param('foo'), [qw(bar baz)], 'right values';
is $params->param('a'), 'b', 'right value';
is_deeply $params->every_param('bar'), [qw(bas test)], 'right values';
is_deeply $params->to_hash,
  {foo => ['bar', 'baz'], a => 'b', bar => ['bas', 'test']}, 'right structure';
$params = Mojo::Parameters->new(foo => ['ba;r', 'b;az']);
is_deeply $params->to_hash, {foo => ['ba;r', 'b;az']}, 'right structure';
$params->append(foo => ['bar'], foo => ['baz', 'yada']);
is_deeply $params->to_hash, {foo => ['ba;r', 'b;az', 'bar', 'baz', 'yada']},
  'right structure';
is $params->param('foo'), 'yada', 'right value';
is_deeply $params->every_param('foo'), [qw(ba;r b;az bar baz yada)],
  'right values';
$params = Mojo::Parameters->new(foo => ['ba;r', 'b;az'], bar => 23);
is_deeply $params->to_hash, {foo => ['ba;r', 'b;az'], bar => 23},
  'right structure';
is $params->param('foo'), 'b;az', 'right value';
is_deeply $params->every_param('foo'), [qw(ba;r b;az)], 'right values';
$params = Mojo::Parameters->new;
is $params->param(foo => ['ba;r', 'baz'])->to_string, 'foo=ba%3Br&foo=baz',
  'right format';

# Unicode
$params = Mojo::Parameters->new;
$params->parse('input=say%20%22%C2%AB~%22;');
is_deeply $params->params, ['input', 'say "«~";'], 'right structure';
is $params->param('input'), 'say "«~";', 'right value';
is "$params", 'input=say+%22%C2%AB~%22%3B', 'right result';
$params = Mojo::Parameters->new('♥=☃');
is_deeply $params->params, ['♥', '☃'], 'right structure';
is $params->param('♥'), '☃', 'right value';
is "$params", '%E2%99%A5=%E2%98%83', 'right result';
$params = Mojo::Parameters->new('%E2%99%A5=%E2%98%83');
is_deeply $params->params, ['♥', '☃'], 'right structure';
is $params->param('♥'), '☃', 'right value';
is "$params", '%E2%99%A5=%E2%98%83', 'right result';

# Reparse
$params = Mojo::Parameters->new('foo=bar&baz=23');
$params->parse('foo=bar&baz=23');
is "$params", 'foo=bar&baz=23', 'right result';

# Replace
$params = Mojo::Parameters->new('a=1&b=2');
$params->params([a => 2, b => 3]);
is $params->to_string, 'a=2&b=3', 'right result';

# Query string
$params = Mojo::Parameters->new('%AZaz09-._~&;=+!$\'()*,%:@/?');
is "$params", '%AZaz09-._~&;=+!$\'()*,%:@/?', 'right result';
$params = Mojo::Parameters->new('foo{}bar');
is "$params", 'foo%7B%7Dbar', 'right result';

# "%"
$params = Mojo::Parameters->new;
$params->param('%foo%' => '%');
is "$params", '%25foo%25=%25', 'right result';

# Special characters
$params = Mojo::Parameters->new('!$\'()*,:@/foo?=!$\'()*,:@/?&bar=23');
is $params->param('!$\'()*,:@/foo?'), '!$\'()*,:@/?', 'right value';
is $params->param('bar'),             23,             'right value';
is "$params", '!$\'()*,:@/foo?=!$\'()*,:@/?&bar=23', 'right result';

# No charset
$params = Mojo::Parameters->new('%E5=%E4')->charset(undef);
is $params->param("\xe5"), "\xe4", 'right value';
is "$params", '%E5=%E4', 'right result';
is $params->clone->to_string, '%E5=%E4', 'right result';

done_testing();
