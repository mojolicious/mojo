use Mojo::Base -strict;

use Test::More;

plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};
plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!'
  unless eval 'use Test::Pod::Coverage 1.04; 1';

# DEPRECATED in Tiger Face!
my @tiger = (
  qw(decode emit_safe encode error has_conditions new pluck render_static),
  qw(val)
);

all_pod_coverage_ok({also_private => [@tiger]});
