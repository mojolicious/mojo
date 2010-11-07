#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More tests => 35;

use FindBin;
use lib "$FindBin::Bin/lib";

# I heard you went off and became a rich doctor.
# I've performed a few mercy killings.
package TestApp;

use Mojolicious::Lite;

# GET /hello (embedded)
get '/hello' => sub {
    my $self = shift;
    my $name = $self->stash('name');
    $self->render_text("Hello from the $name app!");
};

# Morbo will now introduce the candidates - Puny Human Number One,
# Puny Human Number Two, and Morbo's good friend Richard Nixon.
# How's the family, Morbo?
# Belligerent and numerous.
package MyTestApp::Test1;

use Mojolicious::Lite;

get '/yada' => sub {
    my $self = shift;
    my $name = $self->stash('name');
    $self->render(text => "yada $name works!");
};

# GET /bye (embedded)
get '/bye' => sub {
    my $self  = shift;
    my $name  = $self->stash('name');
    my $async = '';
    $self->client->async->get(
        '/hello/hello' => sub {
            my $client = shift;
            $self->render_text($client->res->body . "$name! $async");
        }
    )->start;
    $async .= 'success!';
};

package Mojolicious::Plugin::MyEmbeddedApp;
use base 'Mojolicious::Plugin';

sub register {
    my ($self, $app) = @_;
    $app->routes->route('/foo')
      ->detour(Mojolicious::Plugin::MyEmbeddedApp::App::app());
}

package Mojolicious::Plugin::MyEmbeddedApp::App;
use Mojolicious::Lite;

# GET /bar
get '/bar' => {text => 'plugin works!'};

package MyTestApp::Test2;

use Mojolicious::Lite;

# GET / (embedded)
get '/' => sub {
    my $self = shift;
    my $name = $self->param('name');
    my $url  = $self->url_for;
    $self->render_text("Bye from the $name app! $url!");
};

package MyTestApp::Basic;

use base 'Mojo';

sub handler {
    my ($self, $c) = @_;
    $c->res->code(200);
    my $test = $c->param('test');
    $c->res->body("Hello $test!");
    $c->rendered;
}

package main;

use Mojolicious::Lite;
use Test::Mojo;

# /foo/* (plugin app)
plugin 'my_embedded_app';

app->routes->namespace('MyTestApp');

# GET /hello
get '/hello' => 'works';

# /bye/* (dispatch to embedded app)
get('/bye' => {name => 'second embedded'})->detour('MyTestApp::Test1');

# /bar/* (dispatch to embedded app)
get('/bar' => {name => 'third embedded'})->detour(app => 'MyTestApp::Test1');

# /baz/* (dispatch to embedded app)
get('/baz')->detour('test1#', name => 'fourth embedded');

# /yada (dispatch to embedded app)
get('/yada')->to('test1#', name => 'fifth embedded');

# /yada/yada/yada (dispatch to embedded app)
get('/yada/yada/yada')
  ->to('test1#', path => '/yada', name => 'sixth embedded');

# /basic (dispatch to embedded app)
get('/basic')->detour(MyTestApp::Basic->new, test => 'lalala');

# /third/* (dispatch to embedded app)
get '/third/(*path)' =>
  {app => 'MyTestApp::Test2', name => 'third embedded', path => '/'};

# /hello/* (dispatch to embedded app)
app->routes->route('/hello')->detour(TestApp::app())->to(name => 'embedded');

# /just/* (external embedded app)
get('/just' => {name => 'working'})->detour('EmbeddedTestApp');

my $t = Test::Mojo->new;

# GET /foo/bar (plugin app)
$t->get_ok('/foo/bar')->status_is(200)->content_is('plugin works!');

# GET /hello (from main app)
$t->get_ok('/hello')->status_is(200)
  ->content_is("Hello from the main app!\n");

# GET /hello/hello (from embedded app)
$t->get_ok('/hello/hello')->status_is(200)
  ->content_is('Hello from the embedded app!');

# GET /bye/bye (from embedded app)
$t->get_ok('/bye/bye')->status_is(200)
  ->content_is('Hello from the embedded app!second embedded! success!');

# GET /bar/bye (from embedded app)
$t->get_ok('/bar/bye')->status_is(200)
  ->content_is('Hello from the embedded app!third embedded! success!');

# GET /baz/bye (from embedded app)
$t->get_ok('/baz/bye')->status_is(200)
  ->content_is('Hello from the embedded app!fourth embedded! success!');

# GET /yada (from embedded app)
$t->get_ok('/yada')->status_is(200)->content_is('yada fifth embedded works!');

# GET /yada/yada (404 from embedded app)
$t->get_ok('/yada/yada')->status_is(404);

# GET /yada/yada/yada (from embedded app)
$t->get_ok('/yada/yada/yada')->status_is(200)
  ->content_is('yada sixth embedded works!');

# GET /basic (from embedded app)
$t->get_ok('/basic')->status_is(200)->content_is('Hello lalala!');

# GET /third/ (from embedded app)
$t->get_ok('/third')->status_is(200)
  ->content_is('Bye from the third embedded app! /third!');

# GET /just/works (from external embedded app)
$t->get_ok('/just/works')->status_is(200)->content_is("It is working!\n");

__DATA__
@@ works.html.ep
Hello from the main app!
