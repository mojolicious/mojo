#!/usr/bin/env perl
use Mojo::Base -strict;

use Test::More;

plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!'
  unless eval 'use Test::Pod::Coverage 1.04; 1';
plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};

# DEPRECATED in Smiling Face With Sunglasses!
my @sunglasses = (
  qw/add_after add_before append del inner_xml on_progress on_read/,
  qw/on_request on_resume on_start render_inner replace_inner/,
);

# DEPRECATED in Leaf Fluttering In Wind!
my @leaf = (qw/on_finish is_done/);

# "Marge, I'm going to miss you so much. And it's not just the sex.
#  It's also the food preparation."
all_pod_coverage_ok({also_private => ['inet_pton', @leaf, @sunglasses]});
