#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 130;

use Mojo::Transaction::Single;

# They're not very heavy, but you don't hear me not complaining.
use_ok('MojoX::Routes');

# Routes
my $r = MojoX::Routes->new;

# /clean
$r->route('/clean')->to(clean => 1);

# /clean/too
$r->route('/clean/too')->to(something => 1);

# /*/test
my $test = $r->route('/:controller/test')->to(action => 'test');

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
$r->route('/wildcards/1/(*wildcard)', wildcard => qr/(.*)/)
  ->to(controller => 'wild', action => 'card');

# /wildcards/2/*
$r->route('/wildcards/2/(*wildcard)')
  ->to(controller => 'card', action => 'wild');

# /wildcards/3/*/foo
$r->route('/wildcards/3/(*wildcard)/foo')
  ->to(controller => 'very', action => 'dangerous');

# /format
# /format.html
$r->route('/format')
  ->to(controller => 'hello', action => 'you', format => 'html');

# /format2.html
$r->route('/format2.html')->to(controller => 'you', action => 'hello');

# /format2.json
$r->route('/format2.json')->to(controller => 'you', action => 'hello_json');

# /format3/*.html
$r->route('/format3/:foo.html')->to(controller => 'me', action => 'bye');

# /format3/*.json
$r->route('/format3/:foo.json')->to(controller => 'me', action => 'bye_json');

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
my $wp = $articles->waypoint('/:id')->to(
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

# GET /method/get
$r->route('/method/get')->via('GET')
  ->to(controller => 'method', action => 'get');

# POST /method/post
$r->route('/method/post')->via('post')
  ->to(controller => 'method', action => 'post');

# POST|GET /method/post_get
$r->route('/method/post_get')->via(qw/POST get/)
  ->to(controller => 'method', action => 'post_get');

# Make sure stash stays clean
my $tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/clean');
my $match = $r->match($tx);
is($match->stack->[0]->{clean},     1);
is($match->stack->[0]->{something}, undef);
is($match->url_for,                 '/clean');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/clean/too');
$match = $r->match($tx);
is($match->stack->[0]->{clean},     undef);
is($match->stack->[0]->{something}, 1);
is($match->url_for,                 '/clean/too');

# Real world example using most features at once
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/articles.html');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'articles');
is($match->stack->[0]->{action},     'index');
is($match->stack->[0]->{format},     'html');
is($match->url_for,                  '/articles.html');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/articles/1.html');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'articles');
is($match->stack->[0]->{action},     'load');
is($match->stack->[0]->{id},         '1');
is($match->stack->[0]->{format},     'html');
is($match->url_for,                  '/articles/1.html');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/articles/1/edit');
$match = $r->match($tx);
is($match->stack->[1]->{controller}, 'articles');
is($match->stack->[1]->{action},     'edit');
is($match->stack->[1]->{format},     'html');
is($match->url_for,                  '/articles/1/edit.html');
is($match->url_for('articles_delete', format => undef), '/articles/1/delete');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/articles/1/delete');
$match = $r->match($tx);
is($match->stack->[1]->{controller}, 'articles');
is($match->stack->[1]->{action},     'delete');
is($match->stack->[1]->{format},     undef);
is($match->url_for,                  '/articles/1/delete');

# Root
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/');
$match = $r->match($tx);
is($match->captures->{controller},   'hello');
is($match->captures->{action},       'world');
is($match->stack->[0]->{controller}, 'hello');
is($match->stack->[0]->{action},     'world');
is($match->url_for,                  '/');

# Path and captures
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo/test/edit');
$match = $r->match($tx);
is($match->captures->{controller},   'foo');
is($match->captures->{action},       'edit');
is($match->stack->[0]->{controller}, 'foo');
is($match->stack->[0]->{action},     'edit');
is($match->url_for,                  '/foo/test/edit');

# Optional captures in sub route with requirement
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/bar/test/delete/22');
$match = $r->match($tx);
is($match->captures->{controller},   'bar');
is($match->captures->{action},       'delete');
is($match->captures->{id},           22);
is($match->stack->[0]->{controller}, 'bar');
is($match->stack->[0]->{action},     'delete');
is($match->stack->[0]->{id},         22);
is($match->url_for,                  '/bar/test/delete/22');

# Defaults in sub route
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/bar/test/delete');
$match = $r->match($tx);
is($match->captures->{controller},   'bar');
is($match->captures->{action},       'delete');
is($match->captures->{id},           23);
is($match->stack->[0]->{controller}, 'bar');
is($match->stack->[0]->{action},     'delete');
is($match->stack->[0]->{id},         23);
is($match->url_for,                  '/bar/test/delete');

# Chained routes
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/test2/foo');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'test2');
is($match->stack->[1]->{controller}, 'index');
is($match->stack->[2]->{controller}, 'baz');
is($match->captures->{controller},   'baz');
is($match->url_for,                  '/test2/foo');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/test2/bar');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'test2');
is($match->stack->[1]->{controller}, 'index');
is($match->stack->[2]->{controller}, 'lalala');
is($match->captures->{controller},   'lalala');
is($match->url_for,                  '/test2/bar');

# Waypoints
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/test3');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 's');
is($match->stack->[0]->{action},     'l');
is($match->url_for,                  '/test3');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/test3/');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 's');
is($match->stack->[0]->{action},     'l');
is($match->url_for,                  '/test3');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/test3/edit');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 's');
is($match->stack->[0]->{action},     'edit');
is($match->url_for,                  '/test3/edit');

# Named url_for
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/test3');
$match = $r->match($tx);
is($match->url_for, '/test3');
is($match->url_for('test_edit', controller => 'foo'), '/foo/test/edit');
is($match->url_for('test_edit', {controller => 'foo'}), '/foo/test/edit');

# Wildcards
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/wildcards/1/hello/there');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'wild');
is($match->stack->[0]->{action},     'card');
is($match->stack->[0]->{wildcard},   'hello/there');
is($match->url_for,                  '/wildcards/1/hello/there');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/wildcards/2/hello/there');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'card');
is($match->stack->[0]->{action},     'wild');
is($match->stack->[0]->{wildcard},   'hello/there');
is($match->url_for,                  '/wildcards/2/hello/there');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/wildcards/3/hello/there/foo');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'very');
is($match->stack->[0]->{action},     'dangerous');
is($match->stack->[0]->{wildcard},   'hello/there');
is($match->url_for,                  '/wildcards/3/hello/there/foo');

# Format
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/format');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'hello');
is($match->stack->[0]->{action},     'you');
is($match->stack->[0]->{format},     'html');
is($match->url_for,                  '/format.html');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/format.html');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'hello');
is($match->stack->[0]->{action},     'you');
is($match->stack->[0]->{format},     'html');
is($match->url_for,                  '/format.html');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/format2.html');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'you');
is($match->stack->[0]->{action},     'hello');
is($match->stack->[0]->{format},     'html');
is($match->url_for,                  '/format2.html');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/format2.json');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'you');
is($match->stack->[0]->{action},     'hello_json');
is($match->stack->[0]->{format},     'json');
is($match->url_for,                  '/format2.json');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/format3/baz.html');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'me');
is($match->stack->[0]->{action},     'bye');
is($match->stack->[0]->{format},     'html');
is($match->stack->[0]->{foo},        'baz');
is($match->url_for,                  '/format3/baz.html');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/format3/baz.json');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'me');
is($match->stack->[0]->{action},     'bye_json');
is($match->stack->[0]->{format},     'json');
is($match->stack->[0]->{foo},        'baz');
is($match->url_for,                  '/format3/baz.json');

# Request methods
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/method/get.html');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'method');
is($match->stack->[0]->{action},     'get');
is($match->stack->[0]->{format},     'html');
is($match->url_for,                  '/method/get.html');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('POST');
$tx->req->url->parse('/method/post');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'method');
is($match->stack->[0]->{action},     'post');
is($match->stack->[0]->{format},     undef);
is($match->url_for,                  '/method/post');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/method/post_get');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'method');
is($match->stack->[0]->{action},     'post_get');
is($match->stack->[0]->{format},     undef);
is($match->url_for,                  '/method/post_get');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('POST');
$tx->req->url->parse('/method/post_get');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, 'method');
is($match->stack->[0]->{action},     'post_get');
is($match->stack->[0]->{format},     undef);
is($match->url_for,                  '/method/post_get');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('DELETE');
$tx->req->url->parse('/method/post_get');
$match = $r->match($tx);
is($match->stack->[0]->{controller}, undef);
is($match->stack->[0]->{action},     undef);
is($match->stack->[0]->{format},     undef);
is($match->url_for,                  '');

# Not found
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/not_found');
$match = $r->match($tx);
is($match->url_for('test_edit', controller => 'foo'), '/foo/test/edit');
