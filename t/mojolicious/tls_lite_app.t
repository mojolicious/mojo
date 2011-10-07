#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More;
use Mojo::IOLoop::Server;
use Mojo::IOLoop::Stream;
plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.37 required for this test!'
  unless Mojo::IOLoop::Server::TLS;
plan tests => 18;

# "Look at these low, low prices on famous brand-name electronics!
#  Don't be a sap, Dad. These are just crappy knockoffs.
#  Pfft. I know a genuine Panaphonics when I see it.
#  And look, there's a Magnetbox and Sorny."
use Mojo::IOLoop;
use Mojo::UserAgent;
use Mojolicious::Lite;
use Test::Mojo;

# Silence
app->log->level('fatal');

# Secure sessions
app->sessions->secure(1);

# GET /login
get '/login' => sub {
  my $self = shift;
  my $name = $self->param('name');
  $self->session(name => $name);
  $self->render_text("Welcome $name!");
};

get '/again' => sub {
  my $self = shift;
  my $name = $self->session('name') || 'anonymous';
  $self->render_text("Welcome back $name!");
};

my $t = Test::Mojo->new;

# Use HTTPS
$t->test_server('https');

# GET /login
$t->get_ok('/login?name=sri')->status_is(200)->content_is('Welcome sri!');

# GET /again
$t->get_ok('/again')->status_is(200)->content_is('Welcome back sri!');

# Use HTTP
$t->test_server('http');

# GET /login
$t->get_ok('/login?name=sri')->status_is(200)->content_is('Welcome sri!');

# GET /again
$t->get_ok('/again')->status_is(200)->content_is('Welcome back anonymous!');

# Use HTTPS again
$t->test_server('https');

# GET /login
$t->get_ok('/login?name=sri')->status_is(200)->content_is('Welcome sri!');

# GET /again
$t->get_ok('/again')->status_is(200)->content_is('Welcome back sri!');
