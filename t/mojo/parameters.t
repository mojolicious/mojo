use Mojo::Base -strict;

use utf8;

use Test::More tests => 75;

# "Now that's a wave of destruction that's easy on the eyes."
use Mojo::Parameters;

# Basics with custom pair separator
my $params = Mojo::Parameters->new('foo=b%3Bar&baz=23');
my $params2 = Mojo::Parameters->new('x', 1, 'y', 2);
is $params->pair_separator, '&',                 'right pair separator';
is $params->to_string,      'foo=b%3Bar&baz=23', 'right format';
is $params2->to_string,     'x=1&y=2',           'right format';
is $params->to_string,      'foo=b%3Bar&baz=23', 'right format';
is_deeply $params->params, ['foo', 'b;ar', 'baz', 23], 'right structure';
$params->pair_separator(';');
is $params->to_string, 'foo=b%3Bar;baz=23', 'right format';
is "$params", 'foo=b%3Bar;baz=23', 'right format';

# Append
is_deeply $params->params, ['foo', 'b;ar', 'baz', 23], 'right structure';
$params->append('a', 4, 'a', 5, 'b', 6, 'b', 7);
is $params->to_string, "foo=b%3Bar;baz=23;a=4;a=5;b=6;b=7", 'right format';

# Clone
my $clone = $params->clone;
is "$params", "$clone", 'equal results';

# Merge
$params->merge($params2);
is $params->to_string, 'foo=b%3Bar;baz=23;a=4;a=5;b=6;b=7;x=1;y=2',
  'right format';
is $params2->to_string, 'x=1&y=2', 'right format';

# Param
is_deeply $params->param('foo'), 'b;ar', 'right structure';
is_deeply [$params->param('a')], [4, 5], 'right structure';
$params->param(foo => 'bar');
is_deeply [$params->param('foo')], ['bar'], 'right structure';
$params->param(foo => qw/baz yada/);
is_deeply [$params->param('foo')], [qw/baz yada/], 'right structure';

# Parse with ";" separator
$params->parse('q=1;w=2;e=3;e=4;r=6;t=7');
is $params->to_string, 'q=1;w=2;e=3;e=4;r=6;t=7', 'right format';

# Remove
$params->remove('r');
is $params->to_string, 'q=1;w=2;e=3;e=4;t=7', 'right format';
$params->remove('e');
is $params->to_string, 'q=1;w=2;t=7', 'right format';

# Hash
is_deeply $params->to_hash, {q => 1, w => 2, t => 7}, 'right structure';

# List names
is_deeply [$params->param], [qw/q t w/], 'right structure';

# Append
$params->append('a', 4, 'a', 5, 'b', 6, 'b', 7);
is_deeply $params->to_hash,
  {a => [4, 5], b => [6, 7], q => 1, w => 2, t => 7}, 'right structure';
$params = Mojo::Parameters->new(foo => undef, bar => 'bar');
is $params->to_string, 'foo=&bar=bar', 'right format';
$params = Mojo::Parameters->new(bar => 'bar', foo => undef);
is $params->to_string, 'bar=bar&foo=', 'right format';

# 0 value
$params = Mojo::Parameters->new(foo => 0);
is_deeply $params->param('foo'), 0, 'right structure';
is $params->to_string, 'foo=0', 'right format';
$params = Mojo::Parameters->new($params->to_string);
is_deeply $params->param('foo'), 0, 'right structure';
is $params->to_hash->{foo}, 0, 'right value';
is_deeply $params->to_hash, {foo => 0}, 'right structure';
is $params->to_string, 'foo=0', 'right format';

# Semicolon
$params = Mojo::Parameters->new('foo=bar;baz');
is $params->pair_separator, '&',           'right pair separator';
is $params->to_string,      'foo=bar;baz', 'right format';
is_deeply $params->params, [foo => 'bar', baz => ''], 'right structure';
is_deeply $params->to_hash, {foo => 'bar', baz => ''}, 'right structure';
is $params->pair_separator, ';',            'right pair separator';
is $params->to_string,      'foo=bar;baz=', 'right format';
$params = Mojo::Parameters->new('foo=bar%3Bbaz');
is $params->pair_separator, '&', 'right pair separator';
is_deeply $params->params, [foo => 'bar;baz'], 'right structure';
is_deeply $params->to_hash, {foo => 'bar;baz'}, 'right structure';
is $params->to_string, 'foo=bar%3Bbaz', 'right format';

# Reconstruction
$params = Mojo::Parameters->new('foo=bar&baz=23');
is "$params", 'foo=bar&baz=23', 'right format';
$params = Mojo::Parameters->new('foo=bar;baz=23');
is "$params", 'foo=bar;baz=23', 'right format';

# Undefined params
$params = Mojo::Parameters->new;
$params->append('c',   undef);
$params->append(undef, 'c');
$params->append(undef, undef);
is $params->to_string, "c=&=c&=", 'right format';
is_deeply $params->to_hash, {c => '', '' => ['c', '']}, 'right structure';
$params->remove('c');
is $params->to_string, "=c&=", 'right format';
$params->remove(undef);
ok !$params->to_string, 'empty';
$params->parse('');
ok !$params->to_string, 'empty';
is_deeply $params->to_hash, {}, 'right structure';

# Empty params
$params = Mojo::Parameters->new('c=');
is $params->to_hash->{c}, '', 'right value';
is_deeply $params->to_hash, {c => ''}, 'right structure';
$params = Mojo::Parameters->new('c=&d=');
is $params->to_hash->{c}, '', 'right value';
is $params->to_hash->{d}, '', 'right value';
is_deeply $params->to_hash, {c => '', d => ''}, 'right structure';
$params = Mojo::Parameters->new('c=&d=0&e=');
is $params->to_hash->{c}, '', 'right value';
is $params->to_hash->{d}, 0,  'right value';
is $params->to_hash->{e}, '', 'right value';
is_deeply $params->to_hash, {c => '', d => 0, e => ''}, 'right structure';

# +
$params = Mojo::Parameters->new('foo=%2B');
is $params->param('foo'), '+', 'right value';
is_deeply $params->to_hash, {foo => '+'}, 'right structure';
$params->param('foo ' => 'a');
is $params->to_string, "foo=%2B&foo+=a", 'right format';
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
$params->append(foo => [qw/bar baz/], a => 'b', bar => [qw/bas test/]);
is_deeply [$params->param('foo')], [qw/bar baz/], 'right values';
is $params->param('a'), 'b', 'right value';
is_deeply [$params->param('bar')], [qw/bas test/], 'right values';
is_deeply $params->to_hash,
  {
  foo => ['bar', 'baz'],
  a   => 'b',
  bar => ['bas', 'test']
  },
  'right structure';

# Unicode
$params = Mojo::Parameters->new;
$params->parse('input=say%20%22%C2%AB%22;');
is $params->params->[1], 'say "«"', 'right value';
is $params->param('input'), 'say "«"', 'right value';
is "$params", 'input=say+%22%C2%AB%22', 'right result';

# Reparse
$params = Mojo::Parameters->new('foo=bar&baz=23');
$params->parse('foo=bar&baz=23');
is "$params", 'foo=bar&baz=23', 'right result';
