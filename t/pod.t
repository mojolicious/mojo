use Mojo::Base -strict;

use Test::More;
plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};
plan skip_all => 'Test::Pod 1.14 required for this test!'
  unless eval 'use Test::Pod 1.14; 1';

# "Marge, it takes two to lie. One to lie and one to listen."
all_pod_files_ok();
