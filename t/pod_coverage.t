#!/usr/bin/env perl
use Mojo::Base -strict;

use Test::More;

plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!'
  unless eval 'use Test::Pod::Coverage 1.04; 1';
plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};

# DEPRECATED in Smiling Face With Sunglasses!
my @sunglasses = (qw/on_progress on_read on_request on_resume on_start/);

# DEPRECATED in Leaf Fluttering In Wind!
my @leaf = (
  qw/add_hook connect connection_timeout is_done listen on_close on_error/,
  qw/on_finish on_read run_hook run_hook_reverse write/
);

# "Marge, I'm going to miss you so much. And it's not just the sex.
#  It's also the food preparation."
all_pod_coverage_ok({also_private => ['inet_pton', @leaf, @sunglasses]});
