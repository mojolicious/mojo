#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

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

use Test::More tests => 31;

use Mojo;
use Mojo::Transaction::HTTP;
use MojoX::Dispatcher::Routes;

my $c = Test::Controller->new(app => Mojo->new);

# Silence
$c->app->log->path(undef);
$c->app->log->level('error');

my $d = MojoX::Dispatcher::Routes->new;
ok($d, 'initialized');

$d->namespace('Test');
$d->route('/')->to(controller => 'foo', action => 'home');
$d->route('/foo/(capture)')->to(controller => 'foo', action => 'bar');

# 404 clean stash
$c->reset_state;
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/not_found');
$c->tx($tx);
is($d->dispatch($c), 1, 'dispatched');
is_deeply($c->stash, {}, 'empty stash');
ok(!$c->render_called, 'nothing rendered');

# No escaping
$c->reset_state;
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/foo/hello');
$c->tx($tx);
is($d->dispatch($c),               '',                 'dispatched');
is($c->stash->{controller},        'foo',              'right value');
is($c->stash->{action},            'bar',              'right value');
is($c->stash->{capture},           'hello',            'right value');
is(ref $c->stash->{'mojo.params'}, 'Mojo::Parameters', 'right parameters');
is($c->param('controller'),        'foo',              'right value');
is($c->param('action'),            'bar',              'right value');
is($c->param('capture'),           'hello',            'right value');
ok($c->render_called, 'rendered');

# Escaping
$c->reset_state;
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo/hello%20there');
$c->tx($tx);
is($d->dispatch($c),               '',                 'dispatched');
is($c->stash->{controller},        'foo',              'right value');
is($c->stash->{action},            'bar',              'right value');
is($c->stash->{capture},           'hello there',      'right value');
is(ref $c->stash->{'mojo.params'}, 'Mojo::Parameters', 'right parameters');
is($c->param('controller'),        'foo',              'right value');
is($c->param('action'),            'bar',              'right value');
is($c->param('capture'),           'hello there',      'right value');
ok($c->render_called, 'rendered');

# Escaping utf8
$c->reset_state;
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82');
$c->tx($tx);
is($d->dispatch($c),               '',                 'dispatched');
is($c->stash->{controller},        'foo',              'right value');
is($c->stash->{action},            'bar',              'right value');
is($c->stash->{capture},           'привет',     'right value');
is(ref $c->stash->{'mojo.params'}, 'Mojo::Parameters', 'right parameters');
is($c->param('controller'),        'foo',              'right value');
is($c->param('action'),            'bar',              'right value');
is($c->param('capture'),           'привет',     'right value');
ok($c->render_called, 'rendered');
