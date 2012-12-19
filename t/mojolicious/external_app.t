use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;

use FindBin;
use lib "$FindBin::Bin/external/lib";

use Test::Mojo;

my $t = Test::Mojo->new('MyApp');

# GET /
$t->get_ok('/')->status_is(200)->content_is('too%21');

# GET /index.html
$t->get_ok('/index.html')->status_is(200)
  ->content_is("External static file!\n");

# GET /test
$t->get_ok('/test')->status_is(200)->content_is('works%21');

done_testing();
