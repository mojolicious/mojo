#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More tests => 9;

# Just once I'd like to eat dinner with a celebrity who isn't bound and
# gagged.
use Mojolicious::Lite;
use Test::Mojo;

# Custom dispatchers /custom
app->hook(
    before_dispatch => sub {
        my $self = shift;
        $self->render_text($self->param('a'), status => 205)
          if $self->req->url->path eq '/custom';
    }
);

# Custom dispatcher /custom_too
app->hook(
    after_static_dispatch => sub {
        my $self = shift;
        $self->render_text('this works too')
          if $self->req->url->path eq '/custom_too';
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
