#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 30;

use Mojo::Transaction;

# They're not very heavy, but you don't hear me not complaining.
use_ok('MojoX::Routes');

# Routes
my $r = MojoX::Routes->new;

# /*/test
my $test = $r->route('/:controller/test')->to(action => 'test');

# /*/test/edit
$test->route('/edit')->to(action => 'edit');

# /*/test/delete/*
$test->route('/delete/:id', id => qr/\d+/)->to(action => 'delete', id => 23);

# /test2
my $test2 = $r->gate('/test2')->to(controller => 'test2');

# /test2 (inline)
$test2->gate->to(controller => 'index');

# /test2/foo
$test2->gate('/foo')->to(controller => 'baz');

# /test2/bar
$test2->route('/bar')->to(controller => 'lalala');

# Path and captures
my $match = $r->match(_tx('/foo/test/edit'));
is($match->captures->{controller}, 'foo');
is($match->captures->{action}, 'edit');
is($match->stack->[0]->{controller}, 'foo');
is($match->stack->[0]->{action}, 'edit');
is($match->url_for, '/foo/test/edit');

# Optional captures in sub route with requirement
$match = $r->match(_tx('/bar/test/delete/22'));
is($match->captures->{controller}, 'bar');
is($match->captures->{action}, 'delete');
is($match->captures->{id}, 22);
is($match->stack->[0]->{controller}, 'bar');
is($match->stack->[0]->{action}, 'delete');
is($match->stack->[0]->{id}, 22);
is($match->url_for, '/bar/test/delete/22');

# Defaults in sub route
$match = $r->match(_tx('/bar/test/delete'));
is($match->captures->{controller}, 'bar');
is($match->captures->{action}, 'delete');
is($match->captures->{id}, 23);
is($match->stack->[0]->{controller}, 'bar');
is($match->stack->[0]->{action}, 'delete');
is($match->stack->[0]->{id}, 23);
is($match->url_for, '/bar/test/delete');

# Chained routes
$match = $r->match(_tx('/test2/foo'));
is($match->stack->[0]->{controller}, 'test2');
is($match->stack->[1]->{controller}, 'index');
is($match->stack->[2]->{controller}, 'baz');
is($match->captures->{controller}, 'baz');
is($match->url_for, '');
$match = $r->match(_tx('/test2/bar'));
is($match->stack->[0]->{controller}, 'test2');
is($match->stack->[1]->{controller}, 'index');
is($match->stack->[2]->{controller}, 'lalala');
is($match->captures->{controller}, 'lalala');
is($match->url_for, '/test2/bar');

# Helper
sub _tx {
    my $tx = Mojo::Transaction->new_post;
    $tx->req->url->path->parse(@_);
    return $tx;
}