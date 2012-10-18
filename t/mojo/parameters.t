use Mojo::Base -strict;

use utf8;

use Test::More tests => 98;

use Mojo::Parameters;

# Basic functionality
my $p = Mojo::Parameters->new('foo=b%3Bar&baz=23');
my $p2 = Mojo::Parameters->new('x', 1, 'y', 2);
is $p->pair_separator, '&',                 'right pair separator';
is $p->to_string,      'foo=b%3Bar&baz=23', 'right format';
is $p2->to_string,     'x=1&y=2',           'right format';
is $p->to_string,      'foo=b%3Bar&baz=23', 'right format';
is_deeply $p->params, ['foo', 'b;ar', 'baz', 23], 'right structure';
$p->pair_separator(';');
is $p->to_string, 'foo=b%3Bar;baz=23', 'right format';
is "$p", 'foo=b%3Bar;baz=23', 'right format';

# Append
is_deeply $p->params, ['foo', 'b;ar', 'baz', 23], 'right structure';
$p->append('a', 4, 'a', 5, 'b', 6, 'b', 7);
is $p->to_string, "foo=b%3Bar;baz=23;a=4;a=5;b=6;b=7", 'right format';

# Clone
my $clone = $p->clone;
is "$p", "$clone", 'equal results';

# Merge
$p->merge($p2);
is $p->to_string, 'foo=b%3Bar;baz=23;a=4;a=5;b=6;b=7;x=1;y=2', 'right format';
is $p2->to_string, 'x=1&y=2', 'right format';

# Param
is_deeply $p->param('foo'), 'b;ar', 'right structure';
is_deeply [$p->param('a')], [4, 5], 'right structure';
$p->param(foo => 'bar');
is_deeply [$p->param('foo')], ['bar'], 'right structure';
$p->param(foo => qw(baz yada));
is_deeply [$p->param('foo')], [qw(baz yada)], 'right structure';

# Parse with ";" separator
$p->parse('q=1;w=2;e=3;e=4;r=6;t=7');
is $p->to_string, 'q=1;w=2;e=3;e=4;r=6;t=7', 'right format';

# Remove
is $p->remove('r')->to_string, 'q=1;w=2;e=3;e=4;t=7', 'right format';
$p->remove('e');
is $p->to_string, 'q=1;w=2;t=7', 'right format';

# Hash
is_deeply $p->to_hash, {q => 1, w => 2, t => 7}, 'right structure';

# List names
is_deeply [$p->param], [qw(q t w)], 'right structure';

# Append
$p->append('a', 4, 'a', 5, 'b', 6, 'b', 7);
is_deeply $p->to_hash, {a => [4, 5], b => [6, 7], q => 1, w => 2, t => 7},
  'right structure';
$p = Mojo::Parameters->new(foo => undef, bar => 'bar');
is $p->to_string, 'foo=&bar=bar', 'right format';
$p = Mojo::Parameters->new(bar => 'bar', foo => undef);
is $p->to_string, 'bar=bar&foo=', 'right format';

# 0 value
$p = Mojo::Parameters->new(foo => 0);
is_deeply $p->param('foo'), 0, 'right structure';
is $p->to_string, 'foo=0', 'right format';
$p = Mojo::Parameters->new($p->to_string);
is_deeply $p->param('foo'), 0, 'right structure';
is $p->to_hash->{foo}, 0, 'right value';
is_deeply $p->to_hash, {foo => 0}, 'right structure';
is $p->to_string, 'foo=0', 'right format';

# Semicolon
$p = Mojo::Parameters->new('foo=bar;baz');
is $p->pair_separator, '&',           'right pair separator';
is $p->to_string,      'foo=bar;baz', 'right format';
is_deeply $p->params, [foo => 'bar', baz => ''], 'right structure';
is_deeply $p->to_hash, {foo => 'bar', baz => ''}, 'right structure';
is $p->pair_separator, ';',            'right pair separator';
is $p->to_string,      'foo=bar;baz=', 'right format';
$p = Mojo::Parameters->new('foo=bar%3Bbaz');
is $p->pair_separator, '&', 'right pair separator';
is_deeply $p->params, [foo => 'bar;baz'], 'right structure';
is_deeply $p->to_hash, {foo => 'bar;baz'}, 'right structure';
is $p->to_string, 'foo=bar%3Bbaz', 'right format';

# Reconstruction
$p = Mojo::Parameters->new('foo=bar&baz=23');
is "$p", 'foo=bar&baz=23', 'right format';
$p = Mojo::Parameters->new('foo=bar;baz=23');
is "$p", 'foo=bar;baz=23', 'right format';

# Undefined params
$p = Mojo::Parameters->new;
$p->append('c',   undef);
$p->append(undef, 'c');
$p->append(undef, undef);
is $p->to_string, "c=&=c&=", 'right format';
is_deeply $p->to_hash, {c => '', '' => ['c', '']}, 'right structure';
$p->remove('c');
is $p->to_string, "=c&=", 'right format';
$p->remove(undef);
ok !$p->to_string, 'empty';
$p->parse('');
ok !$p->to_string, 'empty';
is_deeply $p->to_hash, {}, 'right structure';

# Empty params
$p = Mojo::Parameters->new('c=');
is $p->to_hash->{c}, '', 'right value';
is_deeply $p->to_hash, {c => ''}, 'right structure';
$p = Mojo::Parameters->new('c=&d=');
is $p->to_hash->{c}, '', 'right value';
is $p->to_hash->{d}, '', 'right value';
is_deeply $p->to_hash, {c => '', d => ''}, 'right structure';
$p = Mojo::Parameters->new('c=&d=0&e=');
is $p->to_hash->{c}, '', 'right value';
is $p->to_hash->{d}, 0,  'right value';
is $p->to_hash->{e}, '', 'right value';
is_deeply $p->to_hash, {c => '', d => 0, e => ''}, 'right structure';

# +
$p = Mojo::Parameters->new('foo=%2B');
is $p->param('foo'), '+', 'right value';
is_deeply $p->to_hash, {foo => '+'}, 'right structure';
$p->param('foo ' => 'a');
is $p->to_string, "foo=%2B&foo+=a", 'right format';
$p->remove('foo ');
is_deeply $p->to_hash, {foo => '+'}, 'right structure';
$p->append('1 2', '3+3');
is $p->param('1 2'), '3+3', 'right value';
is_deeply $p->to_hash, {foo => '+', '1 2' => '3+3'}, 'right structure';
$p = Mojo::Parameters->new('a=works+too');
is "$p", 'a=works+too', 'right format';
is_deeply $p->to_hash, {a => 'works too'}, 'right structure';
is $p->param('a'), 'works too', 'right value';
is "$p", 'a=works+too', 'right format';

# Array values
$p = Mojo::Parameters->new;
$p->append(foo => [qw(bar baz)], bar => [qw(bas test)], a => 'b');
is_deeply [$p->param('foo')], [qw(bar baz)], 'right values';
is $p->param('a'), 'b', 'right value';
is_deeply [$p->param('bar')], [qw(bas test)], 'right values';
is_deeply $p->to_hash,
  {foo => ['bar', 'baz'], a => 'b', bar => ['bas', 'test']}, 'right structure';
$p = Mojo::Parameters->new(foo => ['ba;r', 'b;az']);
is_deeply $p->to_hash, {foo => ['ba;r', 'b;az']}, 'right structure';
$p->append(foo => ['bar'], foo => ['baz', 'yada']);
is_deeply $p->to_hash, {foo => ['ba;r', 'b;az', 'bar', 'baz', 'yada']},
  'right structure';
is $p->param('foo'), 'ba;r', 'right value';
is_deeply [$p->param('foo')], [qw(ba;r b;az bar baz yada)], 'right values';
$p = Mojo::Parameters->new(foo => ['ba;r', 'b;az'], bar => 23);
is_deeply $p->to_hash, {foo => ['ba;r', 'b;az'], bar => 23}, 'right structure';
is $p->param('foo'), 'ba;r', 'right value';
is_deeply [$p->param('foo')], [qw(ba;r b;az)], 'right values';

# Unicode
$p = Mojo::Parameters->new;
$p->parse('input=say%20%22%C2%AB~%22;');
is $p->params->[1], 'say "«~"', 'right value';
is $p->param('input'), 'say "«~"', 'right value';
is "$p", 'input=say+%22%C2%AB~%22', 'right result';
$p = Mojo::Parameters->new('♥=☃');
is $p->params->[0], '♥', 'right value';
is $p->params->[1], '☃', 'right value';
is $p->param('♥'), '☃', 'right value';
is "$p", '%E2%99%A5=%E2%98%83', 'right result';
$p = Mojo::Parameters->new('%E2%99%A5=%E2%98%83');
is $p->params->[0], '♥', 'right value';
is $p->params->[1], '☃', 'right value';
is $p->param('♥'), '☃', 'right value';
is "$p", '%E2%99%A5=%E2%98%83', 'right result';

# Reparse
$p = Mojo::Parameters->new('foo=bar&baz=23');
$p->parse('foo=bar&baz=23');
is "$p", 'foo=bar&baz=23', 'right result';

# Query string
$p = Mojo::Parameters->new('%AZaz09-._~&;=+!$\'()*,%:@/?');
is "$p", '%AZaz09-._~&;=+!$\'()*,%:@/?', 'right result';
$p = Mojo::Parameters->new('foo{}bar');
is "$p", 'foo%7B%7Dbar', 'right result';

# "%"
$p = Mojo::Parameters->new;
$p->param('%foo%' => '%');
is "$p", '%25foo%25=%25', 'right result';

# Special characters
$p = Mojo::Parameters->new('!$\'()*,:@/foo?=!$\'()*,:@/?&bar=23');
is $p->param('!$\'()*,:@/foo?'), '!$\'()*,:@/?', 'right value';
is $p->param('bar'),             23,             'right value';
is "$p", '!$\'()*,:@/foo?=!$\'()*,:@/?&bar=23', 'right result';

# No charset
$p = Mojo::Parameters->new('foo=%E2%98%83')->charset(undef);
is $p->param('foo'), "\xe2\x98\x83", 'right value';
is "$p", 'foo=%E2%98%83', 'right result';
