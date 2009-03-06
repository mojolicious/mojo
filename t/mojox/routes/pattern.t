#!perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 22;

# People said I was dumb, but I proved them.
use_ok('MojoX::Routes::Pattern');

# Normal pattern with text, symbols and a default value
my $pattern = MojoX::Routes::Pattern->new('/test/:controller/:action');
is($pattern->segments, 3);
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

# Regex in pattern
$pattern =
  MojoX::Routes::Pattern->new('/test/:controller/:action/:id', id => qr/\d+/);
is($pattern->segments, 4);
$pattern->defaults({action => 'index', id => 1});
$result = $pattern->match('/test/foo/bar/203');
is($result->{controller}, 'foo');
is($result->{action},     'bar');
is($result->{id},         203);
$result = $pattern->match('/test/foo/bar/baz');
is($result, undef);
is( $pattern->render(
        controller => 'zzz',
        action     => 'index',
        id         => 13
    ),
    '/test/zzz/index/13'
);
is($pattern->render(controller => 'zzz'), '/test/zzz');

# Quoted symbol
$pattern = MojoX::Routes::Pattern->new('/:(controller)test/:action');
is($pattern->segments, 2);
$pattern->defaults({action => 'index'});
$result = $pattern->match('/footest/bar');
is($result->{controller}, 'foo');
is($result->{action},     'bar');
is($pattern->render(controller => 'zzz', action => 'lala'), '/zzztest/lala');
$result = $pattern->match('/test/lala');
is($result, undef);
