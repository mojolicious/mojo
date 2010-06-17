#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan tests => 12;

# I heard you went off and became a rich doctor.
# I've performed a few mercy killings.
package EmbeddedTestApp;

use Mojolicious::Lite;

# GET /hello (embedded)
get '/hello' => sub {
    my $self = shift;
    my $name = $self->stash('name');
    my $url  = $self->url_for;
    $self->render_text("Hello from the $name app! $url!");
};

# Morbo will now introduce the candidates - Puny Human Number One,
# Puny Human Number Two, and Morbo's good friend Richard Nixon.
# How's the family, Morbo?
# Belligerent and numerous.
package MyTestApp::Test1;

use Mojolicious::Lite;

# GET /bye (embedded)
get '/bye' => sub {
    my $self = shift;
    my $name = $self->stash('name');
    my $url  = $self->url_for;
    $self->render_text("Bye from the $name app! $url!");
};

package MyTestApp::Test2;

use Mojolicious::Lite;

# GET / (embedded)
get '/' => sub {
    my $self = shift;
    my $name = $self->stash('name');
    my $url  = $self->url_for;
    $self->render_text("Bye from the $name app! $url!");
};

package main;

use Mojolicious::Lite;
use Test::Mojo;

# Silence
app->log->level('error');

# GET /hello
get '/hello' => sub { shift->render_text('Hello from the main app!') };

# /bye/* (dispatch to embedded app)
my $bye = get '/bye' => {name => 'second embedded'};
$bye->detour('MyTestApp::Test1');

# /third/* (dispatch to embedded app)
my $third = get '/third' => {name => 'third embedded'};
$third->detour('MyTestApp::Test2');

# /hello/* (dispatch to embedded app)
app->routes->route('/hello')->to(name => 'embedded')
  ->detour(EmbeddedTestApp::app());

my $t = Test::Mojo->new;

# GET /hello (from main app)
$t->get_ok('/hello')->status_is(200)->content_is('Hello from the main app!');

# GET /hello/hello (from embedded app)
$t->get_ok('/hello/hello')->status_is(200)
  ->content_is('Hello from the embedded app! /hello/hello!');

# GET /bye/bye (from embedded app)
$t->get_ok('/bye/bye')->status_is(200)
  ->content_is('Bye from the second embedded app! /bye/bye!');

# GET /third (from embedded app)
$t->get_ok('/third')->status_is(200)
  ->content_is('Bye from the third embedded app! /third!');
