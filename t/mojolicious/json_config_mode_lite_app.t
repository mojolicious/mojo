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

# Ahhh, what an awful dream.
# Ones and zeroes everywhere... and I thought I saw a two.
use Mojolicious::Lite;
use Test::Mojo;

# Load plugin
plugin 'json_config';

# GET /
get '/' => 'index';

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_like(qr/bazfoo/);

__DATA__
@@ index.html.ep
<%= $config->{foo} %><%= $config->{bar} %>
