#!/usr/bin/env perl

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

use Test::More tests => 41;

use Mojo;
use Mojo::Transaction::HTTP;
use MojoX::Dispatcher::Routes;
use MojoX::Dispatcher::Routes::Controller;

my $c = MojoX::Dispatcher::Routes::Controller->new;

# Set
$c->stash(foo => 'bar');
is $c->stash('foo'), 'bar', 'set and return a stash value';

# Ref value
my $stash = $c->stash;
is_deeply $stash, {foo => 'bar'}, 'return a hashref';

# Replace
$c->stash(foo => 'baz');
is $c->stash('foo'), 'baz', 'replace and return a stash value';

# Set 0
$c->stash(zero => 0);
is $c->stash('zero'), 0, 'set and return 0 value';

# Replace with 0
$c->stash(foo => 0);
is $c->stash('foo'), 0, 'replace and return 0 value';

# Use 0 as key
$c->stash(0 => 'boo');
is $c->stash('0'), 'boo', 'set and get with 0 as key';

# Delete
$stash = $c->stash;
delete $stash->{foo};
delete $stash->{0};
delete $stash->{zero};
is_deeply $stash, {}, 'elements can be deleted';
$c->stash('foo' => 'zoo');
delete $c->stash->{foo};
is_deeply $c->stash, {}, 'elements can be deleted';

# Set via hash
$c->stash({a => 1, b => 2});
$stash = $c->stash;
is_deeply $stash, {a => 1, b => 2}, 'set via hashref';

$c = Test::Controller->new(app => Mojo->new);
$c->app->log->path(undef);
$c->app->log->level('fatal');
my $d = MojoX::Dispatcher::Routes->new;
ok $d, 'initialized';

$d->namespace('Test');
$d->route('/')->to(controller => 'foo', action => 'home');
$d->route('/foo/(capture)')->to(controller => 'foo', action => 'bar');

# 404 clean stash
$c->reset_state;
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/not_found');
$c->tx($tx);
is $d->dispatch($c), 1, 'dispatched';
is_deeply $c->stash, {}, 'empty stash';
ok !$c->render_called, 'nothing rendered';

# No escaping
$c->reset_state;
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/foo/hello');
$c->tx($tx);
$c->stash(test => 23);
is $d->dispatch($c), undef, 'dispatched';
is $c->stash->{controller}, 'foo',   'right value';
is $c->stash->{action},     'bar',   'right value';
is $c->stash->{capture},    'hello', 'right value';
is $c->stash->{test},       23,      'right value';
is ref $c->stash->{'mojo.captures'}, 'HASH', 'right captures';
is $c->param('controller'), 'foo',   'right value';
is $c->param('action'),     'bar',   'right value';
is $c->param('capture'),    'hello', 'right value';
ok $c->render_called, 'rendered';

# Escaping
$c->reset_state;
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo/hello%20there');
$c->tx($tx);
is $d->dispatch($c), undef, 'dispatched';
is $c->stash->{controller}, 'foo',         'right value';
is $c->stash->{action},     'bar',         'right value';
is $c->stash->{capture},    'hello there', 'right value';
is ref $c->stash->{'mojo.captures'}, 'HASH', 'right captures';
is $c->param('controller'), 'foo',         'right value';
is $c->param('action'),     'bar',         'right value';
is $c->param('capture'),    'hello there', 'right value';
ok $c->render_called, 'rendered';

# Escaping utf8
$c->reset_state;
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82');
$c->tx($tx);
is $d->dispatch($c), undef, 'dispatched';
is $c->stash->{controller}, 'foo',          'right value';
is $c->stash->{action},     'bar',          'right value';
is $c->stash->{capture},    'привет', 'right value';
is ref $c->stash->{'mojo.captures'}, 'HASH', 'right captures';
is $c->param('controller'), 'foo',          'right value';
is $c->param('action'),     'bar',          'right value';
is $c->param('capture'),    'привет', 'right value';
ok $c->render_called, 'rendered';
