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

# Silence
app->log->level('error');

# GET /hello (embedded)
get '/hello' => sub {
    my $self = shift;
    my $name = $self->stash('name');
    $self->render_text("Hello from the $name app!");
};

# Morbo will now introduce the candidates - Puny Human Number One,
# Puny Human Number Two, and Morbo's good friend Richard Nixon.
# How's the family, Morbo?
# Belligerent and numerous.
package MyTestApp::Test1;

use Mojolicious::Lite;

# Silence
app->log->level('error');

# GET /hello (embedded)
get '/bye' => sub {
    my $self = shift;
    my $name = $self->stash('name');
    $self->pause;
    my $async = '';
    $self->client->async->get(
        '/hello/hello' => sub {
            my $client = shift;
            $self->render_text($client->res->body . "$name! $async");
            $self->finish;
        }
    )->process;
    $async .= 'success!';
};

package MyTestApp::Test2;

use Mojolicious::Lite;

# Silence
app->log->level('error');

# GET / (embedded)
get '/' => sub {
    my $self = shift;
    my $name = $self->stash('name');
    $self->render_text("Bye from the $name app!");
};

package main;

use Mojolicious::Lite;
use Test::Mojo;

# Silence
app->log->level('error');

# GET /hello
get '/hello' => sub { shift->render_text('Hello from the main app!') };

# /bye/* (dispatch to embedded app)
get '/bye/(*path)' => {app => 'MyTestApp::Test1', name => 'second embedded'};

# /third/* (dispatch to embedded app)
get '/third/(*path)' =>
  {app => 'MyTestApp::Test2', name => 'third embedded', path => '/'};

# /hello/* (dispatch to embedded app)
app->routes->route('/hello/(*path)')
  ->to(app => EmbeddedTestApp::app(), name => 'embedded');

my $t = Test::Mojo->new;

# GET /hello (from main app)
$t->get_ok('/hello')->status_is(200)->content_is('Hello from the main app!');

# GET /hello/hello (from embedded app)
$t->get_ok('/hello/hello')->status_is(200)
  ->content_is('Hello from the embedded app!');

# GET /bye/bye (from embedded app)
$t->get_ok('/bye/bye')->status_is(200)
  ->content_is('Hello from the embedded app!second embedded! success!');

# GET /third/ (from embedded app)
$t->get_ok('/third')->status_is(200)
  ->content_is('Bye from the third embedded app!');
