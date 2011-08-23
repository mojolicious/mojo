#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER}  = 'Mojo::IOWatcher';
  $ENV{MOJO_MODE}       = 'development';
}

use Test::More tests => 3;

use Mojolicious::Lite;
use Test::Mojo;

app->renderer->root(app->home->rel_dir('does_not_exist'));
app->defaults('format' => 'json');

# GET /dead_template
get '/dead_template';

package main;

my $t = Test::Mojo->new;

# GET /does_not_exist ("not_found.development.html.ep" route suggestion)
$t->get_ok('/does_not_exist')->status_is(404)
  ->json_content_is({ status => 0, message => 'Resource not found.' });
  
__DATA__
@@ not_found.json.ep
{"status":false,"message":"Resource not found."}

@@ not_found.xml.ep
<status>false</status><message>Resource not found.</message>