#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

eval "use Test::Pod::Coverage 1.04";
plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!' if $@;
plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};

# DEPRECATED in Smiling Cat Face With Heart-Shaped Eyes!
my @smiling_cat = qw/async/;

# DEPRECATED in Hot Beverage!
my @hot_beverage = qw/handler helper session/;

# "Marge, I'm going to miss you so much. And it's not just the sex.
#  It's also the food preparation."
all_pod_coverage_ok({also_private => [@smiling_cat, @hot_beverage]});
