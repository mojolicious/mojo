use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;

use Mojolicious::Lite;
use Test::Mojo;

# More paths with higher precedence
unshift @{app->renderer->paths}, app->home->rel_dir('templates2');
unshift @{app->static->paths},   app->home->rel_dir('public2');

# GET /twenty_three
get '/twenty_three' => '23';

# GET /fourty_two
get '/fourty_two' => '42';

# GET /yada
get '/yada' => {template => 'foo/yada'};

my $t = Test::Mojo->new;

# GET /twenty_three (templates)
$t->get_ok('/twenty_three')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is("23\n");

# GET /fourty_two (templates2)
$t->get_ok('/fourty_two')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("The answer is 42.\n");

# GET /hello.txt (public2)
$t->get_ok('/hello.txt')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Also higher precedence!\n");

# GET /hello2.txt (public)
$t->get_ok('/hello2.txt')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is("X");

# GET /hello3.txt (public2)
$t->get_ok('/hello3.txt')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Hello Mojo from... ALL GLORY TO THE HYPNOTOAD!\n");

# GET /yada (templates2)
$t->get_ok('/yada')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Higher precedence!\n");

done_testing();
