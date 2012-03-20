use Mojo::Base -strict;

use utf8;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_MODE}       = 'testing';
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR}    = 'Mojo::Reactor';
}

# "Who are you, and why should I care?"
use Test::More tests => 3;

# "Ahhh, what an awful dream.
#  Ones and zeroes everywhere... and I thought I saw a two."
use Mojolicious::Lite;
use Test::Mojo;

# Load plugin
plugin 'JSONConfig';

# GET /
get '/' => 'index';

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_like(qr/bazfoo/);

__DATA__
@@ index.html.ep
<%= $config->{foo} %><%= $config->{bar} %>
