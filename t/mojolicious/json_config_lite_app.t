#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

# Disable IPv6, epoll and kqueue
BEGIN { $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1 }

use Test::More tests => 16;

# "Oh, I always feared he might run off like this.
#  Why, why, why didn't I break his legs?"
use Mojolicious::Lite;
use Test::Mojo;

# Load plugin
my $config =
  plugin json_config => {default => {foo => 'baz', hello => 'there'}};
is $config->{foo},   'bar',    'right value';
is $config->{hello}, 'there',  'right value';
is $config->{utf},   'утф', 'right value';
is app->config->{foo},   'bar',    'right value';
is app->config->{hello}, 'there',  'right value';
is app->config->{utf},   'утф', 'right value';
is app->config('foo'),   'bar',    'right value';
is app->config('hello'), 'there',  'right value';
is app->config('utf'),   'утф', 'right value';

# GET /
get '/' => 'index';

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_is("barbarbar\n");

# No config file, default only
$config =
  plugin json_config => {file => 'nonexisted', default => {foo => 'qux'}};
is $config->{foo}, 'qux', 'right value';
is app->config->{foo}, 'qux', 'right value';
is app->config('foo'), 'qux', 'right value';

# No config file, no default
ok !(eval { plugin json_config => {file => 'nonexisted'} }), 'no config file';

__DATA__
@@ index.html.ep
<%= $config->{foo} %><%= config->{foo} %><%= config 'foo' %>
