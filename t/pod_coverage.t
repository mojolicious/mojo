#!/usr/bin/env perl
use Mojo::Base -strict;

use Test::More;

eval "use Test::Pod::Coverage 1.04";
plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!' if $@;
plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};

# DEPRECATED in Smiling Face With Sunglasses!
my @sunglasses = (
  qw/add_after add_before append inner_xml on_finish on_message on_progress/,
  qw/on_read on_request on_resume on_start on_upgrade render_inner/,
  qw/replace_inner/
);

# "Marge, I'm going to miss you so much. And it's not just the sex.
#  It's also the food preparation."
all_pod_coverage_ok({also_private => ['inet_pton', @sunglasses]});
