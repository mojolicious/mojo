use Mojo::Base -strict;

use utf8;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_MODE}       = 'testing';
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR}    = 'Mojo::Reactor::Poll';
}

use Test::More tests => 39;

# "I wax my rocket every day!"
use Mojolicious::Lite;
use Test::Mojo;

# Mount full external application a few times
use FindBin;
my $external = "$FindBin::Bin/external/script/my_app";
plugin Mount => {'/x/1' => $external};
plugin(Mount => ('/x/♥' => $external));
plugin Mount => {'MOJOLICIO.US/' => $external};
plugin(Mount => ('*.foo-bar.de/♥/123' => $external));

# GET /hello
get '/hello' => 'works';

my $t = Test::Mojo->new;

# GET /hello
$t->get_ok('/hello')->status_is(200)
  ->content_is("Hello from the main app!\n");

# GET /x/1 (external app)
$t->get_ok('/x/1')->status_is(200)->content_is('too!');

# GET /x/1/index.html (external app)
$t->get_ok('/x/1/index.html')->status_is(200)
  ->content_is("External static file!\n");

# GET /x/1/test (external app)
$t->get_ok('/x/1/test')->status_is(200)->content_is('works!');

# GET /x/♥ (external app)
$t->get_ok('/x/♥')->status_is(200)->content_is('too!');

# GET /x/♥/index.html (external app)
$t->get_ok('/x/♥/index.html')->status_is(200)
  ->content_is("External static file!\n");

# GET /x/♥/test (external app)
$t->get_ok('/x/♥/test')->status_is(200)->content_is('works!');

# GET / (external app with domain)
$t->get_ok('/' => {Host => 'mojolicio.us'})->status_is(200)
  ->content_is('too!');

# GET /index.html (external app with domain)
$t->get_ok('/index.html' => {Host => 'mojolicio.us'})->status_is(200)
  ->content_is("External static file!\n");

# GET /test (external app with domain)
$t->get_ok('/test' => {Host => 'mojolicio.us'})->status_is(200)
  ->content_is('works!');

# GET /♥/123/ (external app with a bit of everything)
$t->get_ok('/♥/123/' => {Host => 'test.foo-bar.de'})->status_is(200)
  ->content_is('too!');

# GET /♥/123/index.html (external app with a bit of everything)
$t->get_ok('/♥/123/index.html' => {Host => 'test.foo-bar.de'})
  ->status_is(200)->content_is("External static file!\n");

# GET /♥/123/test (external app with a bit of everything)
$t->get_ok('/♥/123/test' => {Host => 'test.foo-bar.de'})->status_is(200)
  ->content_is('works!');

__DATA__

@@ works.html.ep
Hello from the main app!
