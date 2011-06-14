#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

# Disable IPv6, epoll and kqueue
BEGIN {
  $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1;
  $ENV{MOJO_MODE} = 'testing';
}

# "Who are you, and why should I care?"
use Test::More tests => 6;

# "Of all the parasites I've had over the years,
#  these worms are among the best."
use FindBin;
require "$FindBin::Bin/external/myapp.pl";
use Test::Mojo;

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_is("works!\n\ntoo!works!!!\n");

# GET /index.html
$t->get_ok('/index.html')->status_is(200)
  ->content_is('External static file!');
