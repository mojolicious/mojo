use Mojo::Base -strict;

use Test::More;

plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};
plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!'
  unless eval 'use Test::Pod::Coverage 1.04; 1';

# DEPRECATED in Rainbow!
my @rainbow = (
  qw(build_form_tx build_json_tx end form json post_form post_form_ok),
  qw(post_json post_json_ok)
);

# False positive constants
all_pod_coverage_ok({also_private => [@rainbow, qw(IPV6 TLS)]});
