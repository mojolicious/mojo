#!perl

# Copyright (C) 2008-2009, Sebastian Riedel.

package Test::Foo;

use strict;
use warnings;

use base 'MojoX::Dispatcher::Routes::Controller';

sub bar  { return 1 }
sub home { return 1 }

package Test::Context;

use strict;
use warnings;

use base 'MojoX::Dispatcher::Routes::Context';

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

use Test::More tests => 10;

use Mojo;
use MojoX::Dispatcher::Routes;
use MojoX::Dispatcher::Routes::Context;

my $c = Test::Context->new(app => Mojo->new);

# Silence
$c->app->log->path(undef);
$c->app->log->level('error');

my $d = MojoX::Dispatcher::Routes->new;
ok($d);

$d->namespace('Test');
$d->route('/')->to(controller => 'foo', action => 'home');
$d->route('/foo/:capture')->to(controller => 'foo', action => 'bar');

# 404 clean stash
$c->reset_state;
$c->tx(_tx('/not_found'));
is($d->dispatch($c), 0);
is_deeply($c->stash, {});
ok(!$c->render_called);

# No escaping
$c->reset_state;
$c->tx(_tx('/foo/hello'));
is($d->dispatch($c), 1);
is_deeply($c->stash,
    {controller => 'foo', action => 'bar', capture => 'hello'});
ok($c->render_called);

# Escaping
$c->reset_state;
$c->tx(_tx('/foo/hello%20there'));
is($d->dispatch($c), 1);
is_deeply($c->stash,
    {controller => 'foo', action => 'bar', capture => 'hello there'});
ok($c->render_called);

# Helper
sub _tx {
    my $tx = Mojo::Transaction->new_post;
    $tx->req->url->path->parse(@_);
    return $tx;
}
