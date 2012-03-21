use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor';
}

use Test::More;
plan skip_all => 'set TEST_CACHING to enable this test (developer only!)'
  unless $ENV{TEST_CACHING};
plan tests => 21;

# "I want to see the edge of the universe.
#  Ooh, that sounds cool.
#  It's funny, you live in the universe, but you never get to do this things
#  until someone comes to visit."
use Mojolicious::Lite;
use Test::Mojo;

# GET /memorized
get '/memorized' => 'memorized';

# GET /memorized
my $t = Test::Mojo->new;
$t->get_ok('/memorized')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/\d+a\d+b\d+c\d+\nd\d+\ne\d+/);
my $memorized = $t->tx->res->body;

# GET /memorized
$t->get_ok('/memorized')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is($memorized);

# GET /memorized
$t->get_ok('/memorized')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is($memorized);

# GET /memorized (expired)
sleep 2;
$t->get_ok('/memorized')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/\d+a\d+b\d+c\d+\nd\d+\ne\d+/)->content_isnt($memorized);

__DATA__

@@ memorized.html.ep
<%= memorize begin =%>
<%= time =%>
<% end =%>
<%= memorize begin =%>
    <%= 'a' . time =%>
<% end =%><%= memorize begin =%>
<%= 'b' . time =%>
<% end =%>
<%= memorize test => begin =%>
<%= 'c' . time =%>
<% end =%>
<%= memorize expiry => {expires => time + 1} => begin %>
<%= 'd' . time =%>
<% end =%>
<%= memorize {expires => time + 1} => begin %>
<%= 'e' . time =%>
<% end =%>
