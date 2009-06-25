#!perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 89;

use Mojo::Transaction;

# They're not very heavy, but you don't hear me not complaining.
use_ok('MojoX::Routes');

# Routes
my $r = MojoX::Routes->new;

# /*/test
my $test = $r->route('/(controller)/test')->to(action => 'test');

# /*/test/edit
$test->route('/edit')->to(action => 'edit')->name('test_edit');

# /*/test/delete/*
$test->route('/delete/(id)', id => qr/\d+/)->to(action => 'delete', id => 23);

# /test2
my $test2 = $r->bridge('/test2')->to(controller => 'test2');

# /test2 (inline)
my $test4 = $test2->bridge->to(controller => 'index');

# /test2/foo
$test4->route('/foo')->to(controller => 'baz');

# /test2/bar
$test4->route('/bar')->to(controller => 'lalala');

# /test3
my $test3 = $r->waypoint('/test3')->to(controller => 's', action => 'l');

# /test3/edit
$test3->route('/edit')->to(action => 'edit');

# /
$r->route('/')->to(controller => 'hello', action => 'world');

# /wildcards/1/*
$r->route('/wildcards/1/(((wildcard)))', wildcard => qr/(.*)/)
  ->to(controller => 'wild', action => 'card');

# /wildcards/2/*
$r->route('/wildcards/2/(((wildcard)))')
  ->to(controller => 'card', action => 'wild');

# /wildcards/3/*/foo
$r->route('/wildcards/3/(((wildcard)))/foo')
  ->to(controller => 'very', action => 'dangerous');

# /format
# /format.html
$r->route('/format')
  ->to(controller => 'hello', action => 'you', format => 'html');

# /format2.html
$r->route('/format2.html')->to(controller => 'you', action => 'hello');

# /articles
# /articles.html
# /articles/1
# /articles/1.html
# /articles/1/edit
# /articles/1/delete
my $articles = $r->waypoint('/articles')->to(
    controller => 'articles',
    action     => 'index',
    format     => 'html'
);
my $wp = $articles->waypoint('/(id)')->to(
    controller => 'articles',
    action     => 'load',
    format     => 'html'
);
my $bridge = $wp->bridge->to(
    controller => 'articles',
    action     => 'load',
    format     => 'html'
);
$bridge->route('/edit')->to(controller => 'articles', action => 'edit');
$bridge->route('/delete')->to(
    controller => 'articles',
    action     => 'delete',
    format     => undef
)->name('articles_delete');

# Real world example using most features at once
my $match = $r->match('/articles.html');
is($match->stack->[0]->{controller}, 'articles');
is($match->stack->[0]->{action},     'index');
is($match->stack->[0]->{format},     'html');
is($match->url_for,                  '/articles.html');
$match = $r->match('/articles/1.html');
is($match->stack->[0]->{controller}, 'articles');
is($match->stack->[0]->{action},     'load');
is($match->stack->[0]->{id},         '1');
is($match->stack->[0]->{format},     'html');
is($match->url_for,                  '/articles/1.html');
$match = $r->match('/articles/1/edit');
is($match->stack->[1]->{controller}, 'articles');
is($match->stack->[1]->{action},     'edit');
is($match->stack->[1]->{format},     'html');
is($match->url_for,                  '/articles/1/edit.html');
is($match->url_for('articles_delete', format => undef), '/articles/1/delete');
$match = $r->match('/articles/1/delete');
is($match->stack->[1]->{controller}, 'articles');
is($match->stack->[1]->{action},     'delete');
is($match->stack->[1]->{format},     undef);
is($match->url_for,                  '/articles/1/delete');

# Root
$match = $r->match('/');
is($match->captures->{controller},   'hello');
is($match->captures->{action},       'world');
is($match->stack->[0]->{controller}, 'hello');
is($match->stack->[0]->{action},     'world');
is($match->url_for,                  '/');

# Path and captures
$match = $r->match('/foo/test/edit');
is($match->captures->{controller},   'foo');
is($match->captures->{action},       'edit');
is($match->stack->[0]->{controller}, 'foo');
is($match->stack->[0]->{action},     'edit');
is($match->url_for,                  '/foo/test/edit');

# Optional captures in sub route with requirement
$match = $r->match('/bar/test/delete/22');
is($match->captures->{controller},   'bar');
is($match->captures->{action},       'delete');
is($match->captures->{id},           22);
is($match->stack->[0]->{controller}, 'bar');
is($match->stack->[0]->{action},     'delete');
is($match->stack->[0]->{id},         22);
is($match->url_for,                  '/bar/test/delete/22');

# Defaults in sub route
$match = $r->match('/bar/test/delete');
is($match->captures->{controller},   'bar');
is($match->captures->{action},       'delete');
is($match->captures->{id},           23);
is($match->stack->[0]->{controller}, 'bar');
is($match->stack->[0]->{action},     'delete');
is($match->stack->[0]->{id},         23);
is($match->url_for,                  '/bar/test/delete');

# Chained routes
$match = $r->match('/test2/foo');
is($match->stack->[0]->{controller}, 'test2');
is($match->stack->[1]->{controller}, 'index');
is($match->stack->[2]->{controller}, 'baz');
is($match->captures->{controller},   'baz');
is($match->url_for,                  '/test2/foo');
$match = $r->match('/test2/bar');
is($match->stack->[0]->{controller}, 'test2');
is($match->stack->[1]->{controller}, 'index');
is($match->stack->[2]->{controller}, 'lalala');
is($match->captures->{controller},   'lalala');
is($match->url_for,                  '/test2/bar');

# Waypoints
$match = $r->match('/test3');
is($match->stack->[0]->{controller}, 's');
is($match->stack->[0]->{action},     'l');
is($match->url_for,                  '/test3');
$match = $r->match('/test3/');
is($match->stack->[0]->{controller}, 's');
is($match->stack->[0]->{action},     'l');
is($match->url_for,                  '/test3');
$match = $r->match('/test3/edit');
is($match->stack->[0]->{controller}, 's');
is($match->stack->[0]->{action},     'edit');
is($match->url_for,                  '/test3/edit');

# Named url_for
$match = $r->match('/test3');
is($match->url_for, '/test3');
is($match->url_for('test_edit', controller => 'foo'), '/foo/test/edit');
is($match->url_for('test_edit', {controller => 'foo'}), '/foo/test/edit');

# Wildcards
$match = $r->match('/wildcards/1/hello/there');
is($match->stack->[0]->{controller}, 'wild');
is($match->stack->[0]->{action},     'card');
is($match->stack->[0]->{wildcard},   'hello/there');
is($match->url_for,                  '/wildcards/1/hello/there');
$match = $r->match('/wildcards/2/hello/there');
is($match->stack->[0]->{controller}, 'card');
is($match->stack->[0]->{action},     'wild');
is($match->stack->[0]->{wildcard},   'hello/there');
is($match->url_for,                  '/wildcards/2/hello/there');
$match = $r->match('/wildcards/3/hello/there/foo');
is($match->stack->[0]->{controller}, 'very');
is($match->stack->[0]->{action},     'dangerous');
is($match->stack->[0]->{wildcard},   'hello/there');
is($match->url_for,                  '/wildcards/3/hello/there/foo');

# Format
$match = $r->match('/format');
is($match->stack->[0]->{controller}, 'hello');
is($match->stack->[0]->{action},     'you');
is($match->stack->[0]->{format},     'html');
is($match->url_for,                  '/format.html');
$match = $r->match('/format.html');
is($match->stack->[0]->{controller}, 'hello');
is($match->stack->[0]->{action},     'you');
is($match->stack->[0]->{format},     'html');
is($match->url_for,                  '/format.html');
$match = $r->match('/format2.html');
is($match->stack->[0]->{controller}, 'you');
is($match->stack->[0]->{action},     'hello');
is($match->stack->[0]->{format},     'html');
is($match->url_for,                  '/format2.html');
