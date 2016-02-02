use Mojo::Base -strict;

use Test::More;

plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};
plan skip_all => 'Test::Pod::Coverage 1.04+ required for this test!'
  unless eval 'use Test::Pod::Coverage 1.04; 1';

my %RULES = ('Mojo::Transaction::WebSocket' =>
    {also_private => [qw(build_frame parse_frame)]},);
pod_coverage_ok($_, $RULES{$_} || {}) for all_modules();

done_testing();
