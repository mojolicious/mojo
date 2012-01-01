use Mojo::Base -strict;

use Test::More;

plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!'
  unless eval 'use Test::Pod::Coverage 1.04; 1';
plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};

# DEPRECATED in Leaf Fluttering In Wind!
my @leaf = (
  qw/add_hook comment connect connection_timeout is_done keep_alive_timeout/,
  qw/listen max_redirects on_close on_error on_finish on_lock on_process/,
  qw/on_read on_unlock port run_hook run_hook_reverse timeout version write/
);

# "Marge, I'm going to miss you so much. And it's not just the sex.
#  It's also the food preparation."
all_pod_coverage_ok({also_private => [@leaf]});
