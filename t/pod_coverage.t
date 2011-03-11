#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

eval "use Test::Pod::Coverage 1.04";
plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!' if $@;
plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};

# DEPRECATED in Smiling Cat Face With Heart-Shaped Eyes!
my @smiling_cat = (
  qw/async build_form_tx build_tx build_websocket_tx client clone delete/,
  qw/detect_proxy finish get head need_proxy on_finish on_message/,
  qw/post post_form put queue req res send_message singleton start/,
  qw/test_server websocket/
);

# DEPRECATED in Hot Beverage!
my @hot_beverage = qw/handler helper session/;

# "Marge, I'm going to miss you so much. And it's not just the sex.
#  It's also the food preparation."
all_pod_coverage_ok(
  {also_private => ['inet_pton', @smiling_cat, @hot_beverage]});
