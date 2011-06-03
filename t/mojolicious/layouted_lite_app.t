#!/usr/bin/env perl

use strict;
use warnings;

# Disable IPv6, epoll and kqueue
BEGIN { $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1 }

use Test::More tests => 27;

# "We're certainly not building anything sinster, if that's what you mean.
#  Now come on, something sinister won't build itself."
use Mojolicious::Lite;
use Test::Mojo;

app->renderer->root(app->home->rel_dir('does_not_exist'));

# Default layout for whole application
app->defaults(layout => 'default');

# GET /works
get '/works';

# GET /doenotexist
get '/doesnotexist';

# GET /dies
get '/dies' => sub {die};

my $t = Test::Mojo->new;

# GET /works
$t->get_ok('/works')->status_is(200)
  ->content_is("DefaultJust worksThis template just works!\n\n");

# GET /works (different layout)
$t->get_ok('/works?green=1')->status_is(200)
  ->content_is("GreenJust worksThis template just works!\n\n");

# GET /works (extended)
$t->get_ok('/works?blue=1')->status_is(200)
  ->content_is("BlueJust worksThis template just works!\n\n");

# GET /doesnotexist
$t->get_ok('/doesnotexist')->status_is(404)
  ->content_is("DefaultNot found happenedNot found happened!\n\n");

# GET /doesnotexist (different layout)
$t->get_ok('/doesnotexist?green=1')->status_is(404)
  ->content_is("GreenNot found happenedNot found happened!\n\n");

# GET /doesnotexist (extended)
$t->get_ok('/doesnotexist?blue=1')->status_is(404)
  ->content_is("BlueNot found happenedNot found happened!\n\n");

# GET /dies
$t->get_ok('/dies')->status_is(500)
  ->content_is("DefaultException happenedException happened!\n\n");

# GET /dies (different layout)
$t->get_ok('/dies?green=1')->status_is(500)
  ->content_is("GreenException happenedException happened!\n\n");

# GET /dies (extended)
$t->get_ok('/dies?blue=1')->status_is(500)
  ->content_is("BlueException happenedException happened!\n\n");

__DATA__
@@ layouts/default.html.ep
Default<%= title %><%= content %>

@@ layouts/green.html.ep
Green<%= title %><%= content %>

@@ blue.html.ep
Blue<%= title %><%= content %>

@@ works.html.ep
% title 'Just works';
% layout 'green' if param 'green';
% extends 'blue' if param 'blue';
This template just works!

@@ exception.html.ep
% title 'Exception happened';
% layout 'green' if param 'green';
% extends 'blue' if param 'blue';
Exception happened!

@@ not_found.html.ep
% title 'Not found happened';
% layout 'green' if param 'green';
% extends 'blue' if param 'blue';
Not found happened!
