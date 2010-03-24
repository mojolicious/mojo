#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan tests => 6;

# Morbo will now introduce the candidates - Puny Human Number One,
# Puny Human Number Two, and Morbo's good friend Richard Nixon.
# How's the family, Morbo?
# Belligerent and numerous.
package MyTestApp::Test1;

use Mojolicious::Lite;

# Silence
app->log->level('error');

# GET /hello (embedded)
get '/hello' => sub {
    my $self = shift;
    my $name = $self->stash('name');
    $self->render_text("Hello from the $name app!");
};

package main;

use Mojolicious::Lite;
use Test::Mojo;

# Silence
app->log->level('error');

# GET /hello
get '/hello' => sub { shift->render_text('Hello from the main app!') };

# /hello/* (dispatch to embedded app)
app->routes->route('/hello/(*path)')
  ->to(app => 'MyTestApp::Test1', name => 'embedded');

my $t = Test::Mojo->new;

# GET /hello (from main app)
$t->get_ok('/hello')->status_is(200)->content_is('Hello from the main app!');

# GET /hello (from embedded app)
$t->get_ok('/hello/hello')->status_is(200)
  ->content_is('Hello from the embedded app!');
