#!perl

# Copyright (C) 2008-2009, Sebastian Riedel.

package Test::Foo;
use base 'MojoX::Dispatcher::Routes::Controller';

sub bar {
    return 1;
}


package main;

use strict;
use warnings;

use Test::More tests => 5;

use Mojo;
use MojoX::Dispatcher::Routes;
use MojoX::Dispatcher::Routes::Context;

my $c = MojoX::Dispatcher::Routes::Context->new(app => Mojo->new);
$c->app->log->path(undef);

my $d = MojoX::Dispatcher::Routes->new;
ok($d);

$d->namespace('Test');
$d->route('/foo/:capture')->to(controller => 'foo', action => 'bar');

$c->tx(_tx('/foo/hello'));
is($d->dispatch($c), 1);
is_deeply($c->stash, {controller => 'foo', action => 'bar', capture => 'hello'});

$c->tx(_tx('/foo/hello%20there'));
is($d->dispatch($c), 1);
is_deeply($c->stash, {controller => 'foo', action => 'bar', capture => 'hello there'});

# Helper
sub _tx {
    my $tx = Mojo::Transaction->new_post;
    $tx->req->url->path->parse(@_);
    return $tx;
}
