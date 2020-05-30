use Mojo::Base -strict;

use Test::More;

plan skip_all => 'set TEST_POD to enable this test (developer only!)' unless $ENV{TEST_POD} || $ENV{TEST_ALL};
plan skip_all => 'Test::Pod::Coverage 1.04+ required for this test!'  unless eval 'use Test::Pod::Coverage 1.04; 1';

# async/await hooks
my @await = (
  qw(AWAIT_CLONE AWAIT_DONE AWAIT_FAIL AWAIT_GET AWAIT_IS_CANCELLED),
  qw(AWAIT_IS_READY AWAIT_NEW_DONE AWAIT_NEW_FAIL AWAIT_ON_CANCEL),
  qw(AWAIT_ON_READY)
);

all_pod_coverage_ok({also_private => ['BUILD_DYNAMIC', @await, 'success']});
