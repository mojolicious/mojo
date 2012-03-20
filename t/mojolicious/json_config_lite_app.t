use Mojo::Base -strict;

use utf8;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor';
}

use Test::More tests => 20;

# "Oh, I always feared he might run off like this.
#  Why, why, why didn't I break his legs?"
use Mojolicious::Lite;
use Test::Mojo;

# Default
app->config(it => 'works');
is_deeply app->config, {it => 'works'}, 'right value';

# Load plugin
my $config =
  plugin j_s_o_n_config => {default => {foo => 'baz', hello => 'there'}};
is $config->{foo},   'bar',    'right value';
is $config->{hello}, 'there',  'right value';
is $config->{utf},   'утф', 'right value';
is app->config->{foo},   'bar',    'right value';
is app->config->{hello}, 'there',  'right value';
is app->config->{utf},   'утф', 'right value';
is app->config('foo'),   'bar',    'right value';
is app->config('hello'), 'there',  'right value';
is app->config('utf'),   'утф', 'right value';
is app->config('it'),    'works',  'right value';

# GET /
get '/' => 'index';

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_is("barbarbar\n");

# No config file, default only
$config =
  plugin JSONConfig => {file => 'nonexistent', default => {foo => 'qux'}};
is $config->{foo}, 'qux', 'right value';
is app->config->{foo}, 'qux', 'right value';
is app->config('foo'), 'qux',   'right value';
is app->config('it'),  'works', 'right value';

# No config file, no default
{
  ok !(eval { plugin JSONConfig => {file => 'nonexistent'} }),
    'no config file';
  local $ENV{MOJO_CONFIG} = 'nonexistent';
  ok !(eval { plugin 'JSONConfig' }), 'no config file';
}

__DATA__
@@ index.html.ep
<%= $config->{foo} %><%= config->{foo} %><%= config 'foo' %>
