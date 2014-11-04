use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

# Load plugin
plugin 'JSONConfig';

get '/' => 'index';

my $t = Test::Mojo->new;

# Template with config information
$t->get_ok('/')->status_is(200)->content_like(qr/bazfoo/);

done_testing();

__DATA__
@@ index.html.ep
<%= $config->{foo} %><%= $config->{bar} %>
