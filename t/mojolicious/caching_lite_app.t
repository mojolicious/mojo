use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;

plan skip_all => 'set TEST_CACHING to enable this test (developer only!)'
  unless $ENV{TEST_CACHING};

use Mojolicious::Lite;
use Test::Mojo;

get '/memorized' => 'memorized';

# Normal request
my $t = Test::Mojo->new;
$t->get_ok('/memorized')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/\d+a\d+b\d+c\d+\nd\d+\ne\d+/);
my $memorized = $t->tx->res->body;

# Memorized
$t->get_ok('/memorized')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is($memorized);

# Again
$t->get_ok('/memorized')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is($memorized);

# Expired
sleep 2;
$t->get_ok('/memorized')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/\d+a\d+b\d+c\d+\nd\d+\ne\d+/)->content_isnt($memorized);

done_testing();

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
