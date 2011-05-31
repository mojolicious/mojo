#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

eval "use Test::Pod::Coverage 1.04";
plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!' if $@;
plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};

# DEPRECATED in Smiling Face With Sunglasses!
my @sunglasses =
  qw/add_after add_before inner_xml render_inner replace_inner/;

# "Marge, I'm going to miss you so much. And it's not just the sex.
#  It's also the food preparation."
all_pod_coverage_ok({also_private => ['inet_pton', @sunglasses]});
