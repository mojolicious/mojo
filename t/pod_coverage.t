use Mojo::Base -strict;

use Test::More;

plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!'
  unless eval 'use Test::Pod::Coverage 1.04; 1';
plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};

# DEPRECATED in Leaf Fluttering In Wind!
my @leaf = (
  qw/default_static_class default_template_class max_redirects/,
  qw/prepare_ioloop root unsubscribe x_forwarded_for/
);

# "Marge, I'm going to miss you so much. And it's not just the sex.
#  It's also the food preparation."
all_pod_coverage_ok({also_private => [@leaf]});
