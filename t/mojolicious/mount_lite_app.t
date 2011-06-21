#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

# Disable IPv6, epoll and kqueue
BEGIN {
  $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1;
  $ENV{MOJO_MODE} = 'testing';
}

use Test::More tests => 3;
use Mojolicious::Lite;
use Test::Mojo;

plugin mount => {
  '/prefix'               => './mount1.pl',
  'futurama.com/gonads'   => './mount2.pl',
  '*.futurama.com/nutsso' => './mount2.pl',
};

# GET /
get '/' => 'index';

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_like(qr/Welcome to Mojolicious/);
$t->get_ok('/prefix')->status_is(200)->content_like(qr/Welcome to Mounted 1 Mojolicious/);
$t->get_ok('/gonads', {HOST => 'futurama.com'})->status_is(200)->content_like(qr/Welcome to Mounted 2 Mojolicious/);
$t->get_ok('/nutsso', {HOST => 'futurama.com'})->status_is(200)->content_like(qr/Welcome to Mounted 2 Mojolicious/);

__DATA__

@@ index.html.ep
% layout 'default';
% title 'Welcome';
Welcome to Mojolicious!

@@ layouts/default.html.ep
<!doctype html><html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
