#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 38;

# People said I was dumb, but I proved them.
use_ok 'MojoX::Routes::Pattern';

# Normal pattern with text, symbols and a default value
my $pattern = MojoX::Routes::Pattern->new('/test/(controller)/:action');
$pattern->defaults({action => 'index'});
my $result = $pattern->match('/test/foo/bar');
is $result->{controller}, 'foo', 'right value';
is $result->{action},     'bar', 'right value';
$result = $pattern->match('/test/foo');
is $result->{controller}, 'foo',   'right value';
is $result->{action},     'index', 'right value';
$result = $pattern->match('/test/foo/');
is $result->{controller}, 'foo',   'right value';
is $result->{action},     'index', 'right value';
$result = $pattern->match('/test/');
is $result, undef, 'no result';
is $pattern->render({controller => 'foo'}), '/test/foo', 'right result';

# Root
$pattern = MojoX::Routes::Pattern->new('/');
$pattern->defaults({action => 'index'});
$result = $pattern->match('/test/foo/bar');
is $result, undef, 'no result';
$result = $pattern->match('/');
is $result->{action}, 'index', 'right value';
is $pattern->render, '/', 'right result';

# Regex in pattern
$pattern =
  MojoX::Routes::Pattern->new('/test/(controller)/:action/(id)', id => '\d+');
$pattern->defaults({action => 'index', id => 1});
$result = $pattern->match('/test/foo/bar/203');
is $result->{controller}, 'foo', 'right value';
is $result->{action},     'bar', 'right value';
is $result->{id},         203,   'right value';
$result = $pattern->match('/test/foo/bar/baz');
is_deeply $result, undef, 'no result';
is $pattern->render({controller => 'zzz', action => 'index', id => 13}),
  '/test/zzz/index/13', 'right result';
is $pattern->render({controller => 'zzz'}), '/test/zzz', 'right result';

# Quoted symbol
$pattern = MojoX::Routes::Pattern->new('/(:controller)test/(action)');
$pattern->defaults({action => 'index'});
$result = $pattern->match('/footest/bar');
is $result->{controller}, 'foo', 'right value';
is $result->{action},     'bar', 'right value';
is $pattern->render({controller => 'zzz', action => 'lala'}), '/zzztest/lala',
  'right result';
$result = $pattern->match('/test/lala');
is $result, undef, 'no result';

# Format
$pattern = MojoX::Routes::Pattern->new('/(controller)test/(action)');
is $pattern->format, undef, 'no value';
$pattern = MojoX::Routes::Pattern->new('/(:controller)test/:action.html');
is $pattern->format, 'html', 'right value';
$pattern = MojoX::Routes::Pattern->new('/index.cgi');
is $pattern->format, 'cgi', 'right value';

# Relaxed
$pattern = MojoX::Routes::Pattern->new('/test/(.controller)/:action');
$result  = $pattern->match('/test/foo.bar/baz');
is $result->{controller}, 'foo.bar', 'right value';
is $result->{action},     'baz',     'right value';
is $pattern->render({controller => 'foo.bar', action => 'baz'}),
  '/test/foo.bar/baz', 'right result';
$pattern = MojoX::Routes::Pattern->new('/test/(.groovy)');
$result  = $pattern->match('/test/foo.bar');
is $pattern->format, undef, 'no value';
is $result->{groovy}, 'foo.bar', 'right value';
is $result->{format}, undef,     'no value';
is $pattern->render({groovy => 'foo.bar'}), '/test/foo.bar', 'right result';

# Wildcard
$pattern = MojoX::Routes::Pattern->new('/test/(:controller)/(*action)');
$result  = $pattern->match('/test/foo/bar.baz/yada');
is $result->{controller}, 'foo',          'right value';
is $result->{action},     'bar.baz/yada', 'right value';
is $pattern->render({controller => 'foo', action => 'bar.baz/yada'}),
  '/test/foo/bar.baz/yada', 'right result';

# Render false value
$pattern = MojoX::Routes::Pattern->new('/:id');
is $pattern->render({id => 0}), '/0', 'right result';

# Regex in path
$pattern = MojoX::Routes::Pattern->new('/:test');
$result  = $pattern->match('/test(test)(\Qtest\E)(');
is $result->{test}, 'test(test)(\Qtest\E)(', 'right value';
is $pattern->render({test => '23'}), '/23', 'right result';
