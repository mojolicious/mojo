#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

package Test::Foo;

use strict;
use warnings;

use base 'MojoX::Dispatcher::Routes::Controller';

sub bar  {1}
sub home {1}

package Test::Controller;

use strict;
use warnings;

use base 'MojoX::Dispatcher::Routes::Controller';

__PACKAGE__->attr('render_called');

sub render { shift->render_called(1) }

sub reset_state {
    my $self = shift;
    $self->render_called(0);
    my $stash = $self->stash;
    delete $stash->{$_} for keys %$stash;
}

# I was all of history's greatest acting robots -- Acting Unit 0.8,
# Thespomat, David Duchovny!
package main;

use strict;
use warnings;

use utf8;

use Test::More tests => 13;

use Mojo;
use Mojo::Transaction::Single;
use MojoX::Dispatcher::Routes;

my $c = Test::Controller->new(app => Mojo->new);

# Silence
$c->app->log->path(undef);
$c->app->log->level('error');

my $d = MojoX::Dispatcher::Routes->new;
ok($d);

$d->namespace('Test');
$d->route('/')->to(controller => 'foo', action => 'home');
$d->route('/foo/(capture)')->to(controller => 'foo', action => 'bar');

# 404 clean stash
$c->reset_state;
my $tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/not_found');
$c->tx($tx);
is($d->dispatch($c), 1);
is_deeply($c->stash, {});
ok(!$c->render_called);

# No escaping
$c->reset_state;
$tx = Mojo::Transaction::Single->new;
$tx->req->method('POST');
$tx->req->url->parse('/foo/hello');
$c->tx($tx);
is($d->dispatch($c), '');
is_deeply($c->stash,
    {controller => 'foo', action => 'bar', capture => 'hello'});
ok($c->render_called);

# Escaping
$c->reset_state;
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo/hello%20there');
$c->tx($tx);
is($d->dispatch($c), '');
is_deeply($c->stash,
    {controller => 'foo', action => 'bar', capture => 'hello there'});
ok($c->render_called);

# Escaping utf8
$c->reset_state;
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82');
$c->tx($tx);
is($d->dispatch($c), '');
is_deeply($c->stash,
    {controller => 'foo', action => 'bar', capture => 'привет'});
ok($c->render_called);
