use Mojo::Base -strict;

use Test::More;

plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!'
  unless eval 'use Test::Pod::Coverage 1.04; 1';
plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};

# DEPRECATED in Leaf Fluttering In Wind!
my @leaf = (
  qw/comment connect connection_timeout keep_alive_timeout listen/,
  qw/max_redirects on_close on_error on_lock on_process on_read on_unlock/,
  qw/port prepare_ioloop timeout version write x_forwarded_for/
);

# "Marge, I'm going to miss you so much. And it's not just the sex.
#  It's also the food preparation."
all_pod_coverage_ok({also_private => [@leaf]});
