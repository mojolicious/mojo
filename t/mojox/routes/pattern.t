#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 35;

# People said I was dumb, but I proved them.
use_ok('MojoX::Routes::Pattern');

# Normal pattern with text, symbols and a default value
my $pattern = MojoX::Routes::Pattern->new('/test/(controller)/:action');
$pattern->defaults({action => 'index'});
my $result = $pattern->match('/test/foo/bar');
is($result->{controller}, 'foo');
is($result->{action},     'bar');
$result = $pattern->match('/test/foo');
is($result->{controller}, 'foo');
is($result->{action},     'index');
$result = $pattern->match('/test/foo/');
is($result->{controller}, 'foo');
is($result->{action},     'index');
$result = $pattern->match('/test/');
is($result, undef);
is($pattern->render(controller => 'foo'), '/test/foo');

# Root
$pattern = MojoX::Routes::Pattern->new('/');
$pattern->defaults({action => 'index'});
$result = $pattern->match('/test/foo/bar');
is($result, undef);
$result = $pattern->match('/');
is($result->{action}, 'index');
is($pattern->render,  '/');

# Regex in pattern
$pattern =
  MojoX::Routes::Pattern->new('/test/(controller)/:action/(id)', id => '\d+');
$pattern->defaults({action => 'index', id => 1});
$result = $pattern->match('/test/foo/bar/203');
is($result->{controller}, 'foo');
is($result->{action},     'bar');
is($result->{id},         203);
$result = $pattern->match('/test/foo/bar/baz');
is_deeply($result, undef);
is( $pattern->render(
        controller => 'zzz',
        action     => 'index',
        id         => 13
    ),
    '/test/zzz/index/13'
);
is($pattern->render(controller => 'zzz'), '/test/zzz');

# Quoted symbol
$pattern = MojoX::Routes::Pattern->new('/(:controller)test/(action)');
$pattern->defaults({action => 'index'});
$result = $pattern->match('/footest/bar');
is($result->{controller}, 'foo');
is($result->{action},     'bar');
is($pattern->render(controller => 'zzz', action => 'lala'), '/zzztest/lala');
$result = $pattern->match('/test/lala');
is($result, undef);

# Format
$pattern = MojoX::Routes::Pattern->new('/(controller)test/(action)');
is($pattern->format, undef);
$pattern = MojoX::Routes::Pattern->new('/(:controller)test/:action.html');
is($pattern->format, 'html');
$pattern = MojoX::Routes::Pattern->new('/index.cgi');
is($pattern->format, 'cgi');

# Relaxed
$pattern = MojoX::Routes::Pattern->new('/test/(.controller)/:action');
$result  = $pattern->match('/test/foo.bar/baz');
is($result->{controller}, 'foo.bar');
is($result->{action},     'baz');
is($pattern->render(controller => 'foo.bar', action => 'baz'),
    '/test/foo.bar/baz');
$pattern = MojoX::Routes::Pattern->new('/test/(.groovy)');
$result  = $pattern->match('/test/foo.bar');
is($pattern->format,  undef);
is($result->{groovy}, 'foo.bar');
is($result->{format}, undef);
is($pattern->render(groovy => 'foo.bar'), '/test/foo.bar');

# Wildcard
$pattern = MojoX::Routes::Pattern->new('/test/(:controller)/(*action)');
$result  = $pattern->match('/test/foo/bar.baz/yada');
is($result->{controller}, 'foo');
is($result->{action},     'bar.baz/yada');
is($pattern->render(controller => 'foo', action => 'bar.baz/yada'),
    '/test/foo/bar.baz/yada');
