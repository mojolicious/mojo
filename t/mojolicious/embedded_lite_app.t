#!/usr/bin/env perl

use strict;
use warnings;

# Disable IPv6, epoll and kqueue
BEGIN {
  $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1;
  $ENV{MOJO_MODE} = 'testing';
}

use Test::More tests => 65;

use FindBin;
use lib "$FindBin::Bin/lib";

use Mojolicious::Lite;
use Test::Mojo;

package TestApp;
use Mojolicious::Lite;

# GET /hello (embedded)
get '/hello' => sub {
  my $self    = shift;
  my $name    = $self->stash('name');
  my $counter = ++$self->session->{counter};
  $self->render_text("Hello from the $name ($counter) app!");
};

# "Morbo will now introduce the candidates - Puny Human Number One,
#  Puny Human Number Two, and Morbo's good friend Richard Nixon.
#  How's the family, Morbo?
#  Belligerent and numerous."
package MyTestApp::Test1;
use Mojolicious::Lite;

use Mojo::IOLoop;

# GET /yada (embedded)
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
  $self->render_later;
  $self->ua->app(main::app())->get(
    '/hello/hello' => sub {
      my $tx = pop;
      $self->render_text($tx->res->body . "$name! $async");
    }
  );
  $async .= 'success!';
};

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
use Mojo::Base 'Mojo';

sub handler {
  my ($self, $c) = @_;
  $c->res->code(200);
  my $test = $c->param('test');
  $c->res->body("Hello $test!");
  $c->rendered;
}

package main;

# /foo/* (plugin app)
plugin 'PluginWithEmbeddedApp';

app->routes->namespace('MyTestApp');

# Mount full external application twice
use FindBin;
my $external = "$FindBin::Bin/external/myapp.pl";
plugin mount => {'/external/1' => $external};
plugin(mount => ('/external/2' => $external))->to(message => 'works 2!');

# GET /hello
get '/hello' => 'works';

# GET /bye/* (dispatch to embedded app)
get('/bye' => {name => 'second embedded'})->detour('MyTestApp::Test1');

# GET /bar/* (dispatch to embedded app)
get('/bar' => {name => 'third embedded'})->detour(app => 'MyTestApp::Test1');

# GET /baz/* (dispatch to embedded app)
get('/baz')->detour('test1#', name => 'fourth embedded');

# GET /yada (dispatch to embedded app)
get('/yada')->to('test1#', name => 'fifth embedded');

# GET /yada/yada/yada (dispatch to embedded app)
get('/yada/yada/yada')
  ->to('test1#', path => '/yada', name => 'sixth embedded');

# GET /basic (dispatch to embedded app)
get('/basic')->detour(MyTestApp::Basic->new, test => 'lalala');

# GET /third/* (dispatch to embedded app)
get '/third/*path' =>
  {app => 'MyTestApp::Test2', name => 'third embedded', path => '/'};

# GET /hello/* (dispatch to embedded app)
app->routes->route('/hello')->detour(TestApp::app())->to(name => 'embedded');

# GET /just/* (external embedded app)
get('/just' => {name => 'working'})->detour('EmbeddedTestApp');

my $t = Test::Mojo->new;

# GET /foo/bar (plugin app)
$t->get_ok('/foo/bar')->status_is(200)->content_is('plugin works!');

# GET /hello (from main app)
$t->get_ok('/hello')->status_is(200)
  ->content_is("Hello from the main app!\n");

# GET /hello/hello (from embedded app)
$t->get_ok('/hello/hello')->status_is(200)
  ->content_is('Hello from the embedded (1) app!');

# GET /hello/hello (from embedded app again)
$t->get_ok('/hello/hello')->status_is(200)
  ->content_is('Hello from the embedded (2) app!');

# GET /hello/hello (from embedded app again)
$t->get_ok('/hello/hello')->status_is(200)
  ->content_is('Hello from the embedded (3) app!');

# GET /bye/bye (from embedded app)
$t->get_ok('/bye/bye')->status_is(200)
  ->content_is('Hello from the embedded (1) app!second embedded! success!');

# GET /bar/bye (from embedded app)
$t->get_ok('/bar/bye')->status_is(200)
  ->content_is('Hello from the embedded (2) app!third embedded! success!');

# GET /baz/bye (from embedded app)
$t->get_ok('/baz/bye')->status_is(200)
  ->content_is('Hello from the embedded (3) app!fourth embedded! success!');

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

# GET /external/1/ (full external application)
$t->get_ok('/external/1/')->status_is(200)
  ->content_is("works!\n\ntoo!works!!!\n");

# GET /external/1/index.html (full external application)
$t->get_ok('/external/1/index.html')->status_is(200)
  ->content_is('External static file!');

# GET /external/1/echo (full external application)
$t->get_ok('/external/1/echo')->status_is(200)->content_is('echo: nothing!');

# GET /external/1/stream (full external application)
$t->get_ok('/external/1/stream')->status_is(200)->content_is('hello!');

# GET /external/2/ (full external application)
$t->get_ok('/external/2/')->status_is(200)
  ->content_is("works!\n\ntoo!works!!!\n");

# GET /external/2/index.html (full external application)
$t->get_ok('/external/2/index.html')->status_is(200)
  ->content_is('External static file!');

# GET /external/2/echo (full external application)
$t->get_ok('/external/2/echo')->status_is(200)->content_is('echo: works 2!');

# GET /external/2/stream (full external application)
$t->get_ok('/external/2/stream')->status_is(200)->content_is('hello!');

__DATA__
@@ works.html.ep
Hello from the main app!
