#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 6;

# I heard you went off and became a rich doctor.
# I've performed a few mercy killings.
package EmbeddedTestApp;

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
  ->to(app => EmbeddedTestApp::app(), name => 'embedded');

my $t = Test::Mojo->new;

# GET /hello (from main app)
$t->get_ok('/hello')->status_is(200)->content_is('Hello from the main app!');

# GET /hello (from embedded app)
$t->get_ok('/hello/hello')->status_is(200)
  ->content_is('Hello from the embedded app!');
