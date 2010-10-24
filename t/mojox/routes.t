#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 205;

use Mojo::Transaction::HTTP;

# They're not very heavy, but you don't hear me not complaining.
use_ok 'MojoX::Routes';
use_ok 'MojoX::Routes::Match';

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

# /edge/gift
my $edge = $r->route('/edge');
my $auth = $edge->bridge('/auth')->to('auth#check');
$auth->route('/about/')->to('pref#about');
$auth->bridge->to('album#allow')->route('/album/create/')->to('album#create');
$auth->route('/gift/')->to('gift#index')->name('gift');

# Make sure stash stays clean
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/clean');
my $m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{clean},     1,     'right value';
is $m->stack->[0]->{something}, undef, 'no value';
is $m->url_for, '/clean', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/clean/too');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{clean},     undef, 'no value';
is $m->stack->[0]->{something}, 1,     'right value';
is $m->url_for, '/clean/too', 'right URL';
is @{$m->stack}, 1, 'right number of elements';

# Real world example using most features at once
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/articles.html');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'articles', 'right value';
is $m->stack->[0]->{action},     'index',    'right value';
is $m->stack->[0]->{format},     'html',     'right value';
is $m->url_for, '/articles', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/articles/1.html');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'articles', 'right value';
is $m->stack->[0]->{action},     'load',     'right value';
is $m->stack->[0]->{id},         '1',        'right value';
is $m->stack->[0]->{format},     'html',     'right value';
is $m->url_for(format => 'html'), '/articles/1.html', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/articles/1/edit');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[1]->{controller}, 'articles', 'right value';
is $m->stack->[1]->{action},     'edit',     'right value';
is $m->stack->[1]->{format},     'html',     'right value';
is $m->url_for, '/articles/1/edit', 'right URL';
is $m->url_for(format => 'html'), '/articles/1/edit.html', 'right URL';
is $m->url_for('articles_delete', format => undef), '/articles/delete',
  'right URL';
is $m->url_for('articles_delete'), '/articles/delete', 'right URL';
is $m->url_for('articles_delete', id => 12), '/articles/12/delete',
  'right URL';
is @{$m->stack}, 2, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/articles/1/delete');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[1]->{controller}, 'articles', 'right value';
is $m->stack->[1]->{action},     'delete',   'right value';
is $m->stack->[1]->{format},     undef,      'no value';
is $m->url_for, '/articles/1/delete', 'right URL';
is @{$m->stack}, 2, 'right number of elements';

# Root
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->captures->{controller}, 'hello', 'right value';
is $m->captures->{action},     'world', 'right value';
is $m->stack->[0]->{controller}, 'hello', 'right value';
is $m->stack->[0]->{action},     'world', 'right value';
is $m->url_for, '/', 'right URL';
is @{$m->stack}, 1, 'right number of elements';

# Path and captures
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo/test/edit');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->captures->{controller}, 'foo',  'right value';
is $m->captures->{action},     'edit', 'right value';
is $m->stack->[0]->{controller}, 'foo',  'right value';
is $m->stack->[0]->{action},     'edit', 'right value';
is $m->url_for, '/foo/test/edit', 'right URL';
is @{$m->stack}, 1, 'right number of elements';

# Optional captures in sub route with requirement
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/bar/test/delete/22');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->captures->{controller}, 'bar',    'right value';
is $m->captures->{action},     'delete', 'right value';
is $m->captures->{id},         22,       'right value';
is $m->stack->[0]->{controller}, 'bar',    'right value';
is $m->stack->[0]->{action},     'delete', 'right value';
is $m->stack->[0]->{id},         22,       'right value';
is $m->url_for, '/bar/test/delete/22', 'right URL';
is @{$m->stack}, 1, 'right number of elements';

# Defaults in sub route
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/bar/test/delete');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->captures->{controller}, 'bar',    'right value';
is $m->captures->{action},     'delete', 'right value';
is $m->captures->{id},         23,       'right value';
is $m->stack->[0]->{controller}, 'bar',    'right value';
is $m->stack->[0]->{action},     'delete', 'right value';
is $m->stack->[0]->{id},         23,       'right value';
is $m->url_for, '/bar/test/delete', 'right URL';
is @{$m->stack}, 1, 'right number of elements';

# Chained routes
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/test2/foo');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'test2', 'right value';
is $m->stack->[1]->{controller}, 'index', 'right value';
is $m->stack->[2]->{controller}, 'baz',   'right value';
is $m->captures->{controller}, 'baz', 'right value';
is $m->url_for, '/test2/foo', 'right URL';
is @{$m->stack}, 3, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/test2/bar');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'test2',  'right value';
is $m->stack->[1]->{controller}, 'index',  'right value';
is $m->stack->[2]->{controller}, 'lalala', 'right value';
is $m->captures->{controller}, 'lalala', 'right value';
is $m->url_for, '/test2/bar', 'right URL';
is @{$m->stack}, 3, 'right number of elements';
$tx->req->url->parse('/test2/baz');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'test2', 'right value';
is $m->stack->[1]->{controller}, 'just',  'right value';
is $m->stack->[1]->{action},     'works', 'right value';
is $m->stack->[2], undef, 'no value';
is $m->captures->{controller}, 'just', 'right value';
is $m->url_for, '/test2/baz', 'right URL';
is @{$m->stack}, 2, 'right number of elements';

# Waypoints
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/test3');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 's', 'right value';
is $m->stack->[0]->{action},     'l', 'right value';
is $m->url_for, '/test3', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/test3/');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 's', 'right value';
is $m->stack->[0]->{action},     'l', 'right value';
is $m->url_for, '/test3', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/test3/edit');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 's',    'right value';
is $m->stack->[0]->{action},     'edit', 'right value';
is $m->url_for, '/test3/edit', 'right URL';
is @{$m->stack}, 1, 'right number of elements';

# Named url_for
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/test3');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->url_for, '/test3', 'right URL';
is $m->url_for('test_edit', controller => 'foo'), '/foo/test/edit',
  'right URL';
is $m->url_for('test_edit', {controller => 'foo'}), '/foo/test/edit',
  'right URL';
is @{$m->stack}, 1, 'right number of elements';

# Wildcards
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/wildcards/1/hello/there');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'wild',        'right value';
is $m->stack->[0]->{action},     'card',        'right value';
is $m->stack->[0]->{wildcard},   'hello/there', 'right value';
is $m->url_for, '/wildcards/1/hello/there', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/wildcards/2/hello/there');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'card',        'right value';
is $m->stack->[0]->{action},     'wild',        'right value';
is $m->stack->[0]->{wildcard},   'hello/there', 'right value';
is $m->url_for, '/wildcards/2/hello/there', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/wildcards/3/hello/there/foo');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'very',        'right value';
is $m->stack->[0]->{action},     'dangerous',   'right value';
is $m->stack->[0]->{wildcard},   'hello/there', 'right value';
is $m->url_for, '/wildcards/3/hello/there/foo', 'right URL';
is @{$m->stack}, 1, 'right number of elements';

# Escaped
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/wildcards/1/http://www.google.com');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'wild',                  'right value';
is $m->stack->[0]->{action},     'card',                  'right value';
is $m->stack->[0]->{wildcard},   'http://www.google.com', 'right value';
is $m->url_for, '/wildcards/1/http://www.google.com', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/wildcards/1/http%3A%2F%2Fwww.google.com');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'wild',                  'right value';
is $m->stack->[0]->{action},     'card',                  'right value';
is $m->stack->[0]->{wildcard},   'http://www.google.com', 'right value';
is $m->url_for, '/wildcards/1/http://www.google.com', 'right URL';
is @{$m->stack}, 1, 'right number of elements';

# Format
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/format');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'hello', 'right value';
is $m->stack->[0]->{action},     'you',   'right value';
is $m->stack->[0]->{format},     'html',  'right value';
is $m->url_for, '/format', 'right URL';
is $m->url_for(format => undef),  '/format',      'right URL';
is $m->url_for(format => 'html'), '/format.html', 'right URL';
is $m->url_for(format => 'txt'),  '/format.txt',  'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/format.html');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'hello', 'right value';
is $m->stack->[0]->{action},     'you',   'right value';
is $m->stack->[0]->{format},     'html',  'right value';
is $m->url_for, '/format', 'right URL';
is $m->url_for(format => undef),  '/format',      'right URL';
is $m->url_for(format => 'html'), '/format.html', 'right URL';
is $m->url_for(format => 'txt'),  '/format.txt',  'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/format2.html');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'you',   'right value';
is $m->stack->[0]->{action},     'hello', 'right value';
is $m->stack->[0]->{format},     'html',  'right value';
is $m->url_for, '/format2.html', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/format2.json');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'you',        'right value';
is $m->stack->[0]->{action},     'hello_json', 'right value';
is $m->stack->[0]->{format},     'json',       'right value';
is $m->url_for, '/format2.json', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/format3/baz.html');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'me',   'right value';
is $m->stack->[0]->{action},     'bye',  'right value';
is $m->stack->[0]->{format},     'html', 'right value';
is $m->stack->[0]->{foo},        'baz',  'right value';
is $m->url_for, '/format3/baz.html', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/format3/baz.json');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'me',       'right value';
is $m->stack->[0]->{action},     'bye_json', 'right value';
is $m->stack->[0]->{format},     'json',     'right value';
is $m->stack->[0]->{foo},        'baz',      'right value';
is $m->url_for, '/format3/baz.json', 'right URL';
is @{$m->stack}, 1, 'right number of elements';

# Request methods
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/method/get.html');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'method', 'right value';
is $m->stack->[0]->{action},     'get',    'right value';
is $m->stack->[0]->{format},     'html',   'right value';
is $m->url_for, '/method/get', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/method/post');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'method', 'right value';
is $m->stack->[0]->{action},     'post',   'right value';
is $m->stack->[0]->{format},     undef,    'no value';
is $m->url_for, '/method/post', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/method/post_get');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'method',   'right value';
is $m->stack->[0]->{action},     'post_get', 'right value';
is $m->stack->[0]->{format},     undef,      'no value';
is $m->url_for, '/method/post_get', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/method/post_get');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'method',   'right value';
is $m->stack->[0]->{action},     'post_get', 'right value';
is $m->stack->[0]->{format},     undef,      'no value';
is $m->url_for, '/method/post_get', 'right URL';
is @{$m->stack}, 1, 'right number of elements';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('DELETE');
$tx->req->url->parse('/method/post_get');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, undef, 'no value';
is $m->stack->[0]->{action},     undef, 'no value';
is $m->stack->[0]->{format},     undef, 'no value';
is $m->url_for, '', 'no URL';
is @{$m->stack}, 1, 'right number of elements';

# Not found
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/not_found');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->url_for('test_edit', controller => 'foo'), '/foo/test/edit',
  'right URL';
is @{$m->stack}, 0, 'no elements';

# Simplified form
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/simple/form');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'test-test', 'right value';
is $m->stack->[0]->{action},     'test',      'right value';
is $m->stack->[0]->{format},     undef,       'no value';
is $m->url_for, '/simple/form', 'right URL';
is $m->url_for('current'), '/simple/form', 'right URL';
is @{$m->stack}, 1, 'right number of elements';

# Special edge case with nested bridges
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/edge/auth/gift');
$m = MojoX::Routes::Match->new($tx)->match($r);
is $m->stack->[0]->{controller}, 'auth',  'right value';
is $m->stack->[0]->{action},     'check', 'right value';
is $m->stack->[0]->{format},     undef,   'no value';
is $m->stack->[1]->{controller}, 'gift',  'right value';
is $m->stack->[1]->{action},     'index', 'right value';
is $m->stack->[1]->{format},     undef,   'no value';
is $m->stack->[2], undef, 'no value';
is $m->url_for, '/edge/auth/gift', 'right URL';
is $m->url_for('gift'),    '/edge/auth/gift', 'right URL';
is $m->url_for('current'), '/edge/auth/gift', 'right URL';
is @{$m->stack}, 2, 'right number of elements';
