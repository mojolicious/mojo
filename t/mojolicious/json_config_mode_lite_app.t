use Mojo::Base -strict;

use utf8;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

# Load plugin
plugin 'JSONConfig';

# GET /
get '/' => 'index';

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_like(qr/bazfoo/);

done_testing();

__DATA__
@@ index.html.ep
<%= $config->{foo} %><%= $config->{bar} %>
