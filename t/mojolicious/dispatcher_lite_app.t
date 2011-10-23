#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 12;

# "Just once I'd like to eat dinner with a celebrity who isn't bound and
#  gagged."
use Mojolicious::Lite;
use Test::Mojo;

# Wrap whole application
my $next = app->on_process;
app->on_process(
  sub {
    my ($self, $c) = @_;
    return $c->render(text => 'Wrapped!')
      if $c->req->url->path->contains('/wrap');
    $self->$next($c);
  }
);

# Custom dispatchers /custom
app->hook(
  before_dispatch => sub {
    my $self = shift;
    $self->render_text($self->param('a'), status => 205)
      if $self->req->url->path->contains('/custom');
  }
);

# Custom dispatcher /custom_too
app->hook(
  after_static_dispatch => sub {
    my $self = shift;
    $self->render_text('this works too')
      if $self->req->url->path->contains('/custom_too');
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

# GET /wrap
$t->get_ok('/wrap')->status_is(200)->content_is('Wrapped!');
