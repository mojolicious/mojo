#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

# Disable IPv6, epoll and kqueue
BEGIN {
  $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1;
  $ENV{MOJO_MODE} = 'testing';
}

use Test::More tests => 15;
use Mojolicious::Lite;
use Test::Mojo;

plugin mount => {
  '/prefix'               => './mount1.pl',
  'futurama.com/gonads'   => './mount2.pl',
  '*.futurama.com/nutsso' => './mount2.pl',
  '*.zaboomafoo.com'      => './mount3.pl',
};

my $t = Test::Mojo->new;

# virtual-host serving
$t->get_ok('/prefix')->status_is(200)->content_like(qr/Welcome to Mounted 1 Mojolicious/);
$t->get_ok('/gonads', {HOST => 'futurama.com'})->status_is(200)->content_like(qr/Welcome to Mounted 2 Mojolicious/);
$t->get_ok('/nutsso', {HOST => 'futurama.com'})->status_is(200)->content_like(qr/Welcome to Mounted 2 Mojolicious/);
$t->get_ok('/nutsso', {HOST => 'www.futurama.com'})->status_is(200)->content_like(qr/Welcome to Mounted 2 Mojolicious/);
$t->get_ok('/', {HOST => 'zaboomafoo.com'})->status_is(200)->content_like(qr/Welcome to Mounted 3 Mojolicious/);

