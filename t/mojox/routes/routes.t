#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 184;

use Mojo::Transaction::HTTP;

# They're not very heavy, but you don't hear me not complaining.
use_ok('MojoX::Routes');
use_ok('MojoX::Routes::Match');

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

# /test2/baz
$test2->route('/baz')->to('just#works');

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

# /simple/form
$r->route('/simple/form')->to('test-test#test');

# Make sure stash stays clean
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/clean');
my $m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{clean},     1);
is($m->stack->[0]->{something}, undef);
is($m->url_for,                 '/clean');
is(@{$m->stack},                1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/clean/too');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{clean},     undef);
is($m->stack->[0]->{something}, 1);
is($m->url_for,                 '/clean/too');
is(@{$m->stack},                1);

# Real world example using most features at once
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/articles.html');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'articles');
is($m->stack->[0]->{action},     'index');
is($m->stack->[0]->{format},     'html');
is($m->url_for,                  '/articles.html');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/articles/1.html');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'articles');
is($m->stack->[0]->{action},     'load');
is($m->stack->[0]->{id},         '1');
is($m->stack->[0]->{format},     'html');
is($m->url_for,                  '/articles/1.html');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/articles/1/edit');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[1]->{controller}, 'articles');
is($m->stack->[1]->{action},     'edit');
is($m->stack->[1]->{format},     'html');
is($m->url_for,                  '/articles/1/edit.html');
is($m->url_for('articles_delete', format => undef), '/articles/1/delete');
is(@{$m->stack}, 2);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/articles/1/delete');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[1]->{controller}, 'articles');
is($m->stack->[1]->{action},     'delete');
is($m->stack->[1]->{format},     undef);
is($m->url_for,                  '/articles/1/delete');
is(@{$m->stack},                 2);

# Root
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->captures->{controller},   'hello');
is($m->captures->{action},       'world');
is($m->stack->[0]->{controller}, 'hello');
is($m->stack->[0]->{action},     'world');
is($m->url_for,                  '/');
is(@{$m->stack},                 1);

# Path and captures
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo/test/edit');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->captures->{controller},   'foo');
is($m->captures->{action},       'edit');
is($m->stack->[0]->{controller}, 'foo');
is($m->stack->[0]->{action},     'edit');
is($m->url_for,                  '/foo/test/edit');
is(@{$m->stack},                 1);

# Optional captures in sub route with requirement
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/bar/test/delete/22');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->captures->{controller},   'bar');
is($m->captures->{action},       'delete');
is($m->captures->{id},           22);
is($m->stack->[0]->{controller}, 'bar');
is($m->stack->[0]->{action},     'delete');
is($m->stack->[0]->{id},         22);
is($m->url_for,                  '/bar/test/delete/22');
is(@{$m->stack},                 1);

# Defaults in sub route
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/bar/test/delete');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->captures->{controller},   'bar');
is($m->captures->{action},       'delete');
is($m->captures->{id},           23);
is($m->stack->[0]->{controller}, 'bar');
is($m->stack->[0]->{action},     'delete');
is($m->stack->[0]->{id},         23);
is($m->url_for,                  '/bar/test/delete');
is(@{$m->stack},                 1);

# Chained routes
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/test2/foo');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'test2');
is($m->stack->[1]->{controller}, 'index');
is($m->stack->[2]->{controller}, 'baz');
is($m->captures->{controller},   'baz');
is($m->url_for,                  '/test2/foo');
is(@{$m->stack},                 3);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/test2/bar');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'test2');
is($m->stack->[1]->{controller}, 'index');
is($m->stack->[2]->{controller}, 'lalala');
is($m->captures->{controller},   'lalala');
is($m->url_for,                  '/test2/bar');
is(@{$m->stack},                 3);
$tx->req->url->parse('/test2/baz');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'test2');
is($m->stack->[1]->{controller}, 'just');
is($m->stack->[1]->{action},     'works');
is($m->stack->[2],               undef);
is($m->captures->{controller},   'just');
is($m->url_for,                  '/test2/baz');
is(@{$m->stack},                 2);

# Waypoints
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/test3');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 's');
is($m->stack->[0]->{action},     'l');
is($m->url_for,                  '/test3');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/test3/');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 's');
is($m->stack->[0]->{action},     'l');
is($m->url_for,                  '/test3');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/test3/edit');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 's');
is($m->stack->[0]->{action},     'edit');
is($m->url_for,                  '/test3/edit');
is(@{$m->stack},                 1);

# Named url_for
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/test3');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->url_for, '/test3');
is($m->url_for('test_edit', controller => 'foo'), '/foo/test/edit');
is($m->url_for('test_edit', {controller => 'foo'}), '/foo/test/edit');
is(@{$m->stack}, 1);

# Wildcards
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/wildcards/1/hello/there');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'wild');
is($m->stack->[0]->{action},     'card');
is($m->stack->[0]->{wildcard},   'hello/there');
is($m->url_for,                  '/wildcards/1/hello/there');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/wildcards/2/hello/there');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'card');
is($m->stack->[0]->{action},     'wild');
is($m->stack->[0]->{wildcard},   'hello/there');
is($m->url_for,                  '/wildcards/2/hello/there');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/wildcards/3/hello/there/foo');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'very');
is($m->stack->[0]->{action},     'dangerous');
is($m->stack->[0]->{wildcard},   'hello/there');
is($m->url_for,                  '/wildcards/3/hello/there/foo');
is(@{$m->stack},                 1);

# Escaped
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/wildcards/1/http://www.google.com');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'wild');
is($m->stack->[0]->{action},     'card');
is($m->stack->[0]->{wildcard},   'http:/www.google.com');
is($m->url_for,                  '/wildcards/1/http:/www.google.com');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/wildcards/1/http%3A%2F%2Fwww.google.com');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'wild');
is($m->stack->[0]->{action},     'card');
is($m->stack->[0]->{wildcard},   'http://www.google.com');
is($m->url_for,                  '/wildcards/1/http:/www.google.com');
is(@{$m->stack},                 1);

# Format
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/format');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'hello');
is($m->stack->[0]->{action},     'you');
is($m->stack->[0]->{format},     'html');
is($m->url_for,                  '/format.html');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/format.html');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'hello');
is($m->stack->[0]->{action},     'you');
is($m->stack->[0]->{format},     'html');
is($m->url_for,                  '/format.html');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/format2.html');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'you');
is($m->stack->[0]->{action},     'hello');
is($m->stack->[0]->{format},     'html');
is($m->url_for,                  '/format2.html');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/format2.json');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'you');
is($m->stack->[0]->{action},     'hello_json');
is($m->stack->[0]->{format},     'json');
is($m->url_for,                  '/format2.json');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/format3/baz.html');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'me');
is($m->stack->[0]->{action},     'bye');
is($m->stack->[0]->{format},     'html');
is($m->stack->[0]->{foo},        'baz');
is($m->url_for,                  '/format3/baz.html');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/format3/baz.json');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'me');
is($m->stack->[0]->{action},     'bye_json');
is($m->stack->[0]->{format},     'json');
is($m->stack->[0]->{foo},        'baz');
is($m->url_for,                  '/format3/baz.json');
is(@{$m->stack},                 1);

# Request methods
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/method/get.html');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'method');
is($m->stack->[0]->{action},     'get');
is($m->stack->[0]->{format},     'html');
is($m->url_for,                  '/method/get.html');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/method/post');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'method');
is($m->stack->[0]->{action},     'post');
is($m->stack->[0]->{format},     undef);
is($m->url_for,                  '/method/post');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/method/post_get');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'method');
is($m->stack->[0]->{action},     'post_get');
is($m->stack->[0]->{format},     undef);
is($m->url_for,                  '/method/post_get');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/method/post_get');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'method');
is($m->stack->[0]->{action},     'post_get');
is($m->stack->[0]->{format},     undef);
is($m->url_for,                  '/method/post_get');
is(@{$m->stack},                 1);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('DELETE');
$tx->req->url->parse('/method/post_get');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, undef);
is($m->stack->[0]->{action},     undef);
is($m->stack->[0]->{format},     undef);
is($m->url_for,                  '');
is(@{$m->stack},                 1);

# Not found
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/not_found');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->url_for('test_edit', controller => 'foo'), '/foo/test/edit');
is(@{$m->stack}, 0);

# Simplified form
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/simple/form');
$m = MojoX::Routes::Match->new($tx)->match($r);
is($m->stack->[0]->{controller}, 'test-test');
is($m->stack->[0]->{action},     'test');
is($m->stack->[0]->{format},     undef);
is($m->url_for,                  '/simple/form');
is(@{$m->stack},                 1);
