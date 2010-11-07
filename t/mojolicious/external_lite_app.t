#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

# Disable epoll, kqueue and IPv6
BEGIN {
    $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1;
    $ENV{MOJO_MODE} = 'testing';
}

# Who are you, and why should I care?
use Test::More tests => 3;

# Of all the parasites I've had over the years,
# these worms are among the best.
use FindBin;
$ENV{MOJO_HOME} = $FindBin::Bin;
require "$ENV{MOJO_HOME}/external_lite_app.pl";
use Test::Mojo;

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_is("works!\n");
