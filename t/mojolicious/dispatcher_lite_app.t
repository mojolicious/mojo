#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan tests => 9;

# Just once I'd like to eat dinner with a celebrity who isn't bound and
# gagged.
use Mojolicious::Lite;
use Test::Mojo;

# Custom dispatchers /custom
app->plugins->add_hook(
    before_dispatch => sub {
        my ($self, $c) = @_;
        $c->render_text($c->param('a'), status => 205)
          if $c->req->url->path eq '/custom';
    }
);

# Custom dispatcher /custom_too
app->plugins->add_hook(
    after_static_dispatch => sub {
        my ($self, $c) = @_;
        $c->render_text('this works too')
          if $c->req->url->path eq '/custom_too';
    }
);

# GET /
get '/' => sub { shift->render_text('works') };

# GET /custom (never called if custom dispatchers work)
get '/custom' => sub { shift->render_text('does not work') };

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_is('works');

# GET /custom
$t->get_ok('/custom?a=works+too')->status_is(205)->content_is('works too');

# GET /custom_too
$t->get_ok('/custom_too')->status_is(200)->content_is('this works too');
