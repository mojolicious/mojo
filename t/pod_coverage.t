use Mojo::Base -strict;

use Test::More;

plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};
plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!'
  unless eval 'use Test::Pod::Coverage 1.04; 1';

# DEPRECATED in Tiger Face!
my @tiger = (qw(emit_safe has_conditions render_static));

# False positive constants
all_pod_coverage_ok({also_private => [qw(IPV6 TLS), @tiger]});
