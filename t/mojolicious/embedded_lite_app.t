use Mojo::Base -strict;

use utf8;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_MODE}       = 'testing';
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR}    = 'Mojo::Reactor::Poll';
}

use Test::More tests => 133;

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

# GET /yada (embedded)
get '/yada' => sub {
  my $self = shift;
  my $name = $self->stash('name');
  $self->render(text => "yada $name works!");
};

# GET /bye (embedded)
get '/bye' => sub {
  my $self = shift;
  my $name = $self->stash('name');
  my $nb   = '';
  $self->render_later;
  $self->ua->app(main::app())->get(
    '/hello/hello' => sub {
      my $tx = pop;
      $self->render_text($tx->res->body . "$name! $nb");
    }
  );
  $nb .= 'success!';
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

# Mount full external application a few times
my $external = "$FindBin::Bin/external/myapp.pl";
plugin Mount => {'/x/1' => $external};
plugin(Mount => ('/x/♥' => $external))->to(message => 'works 2!');
plugin Mount => {'mojolicious.org' => $external};
plugin Mount => {'MOJOLICIO.US/'   => $external};
plugin Mount => {'*.kraih.com'     => $external};
plugin(Mount => ('*.foo-bar.de/♥/123' => $external))
  ->to(message => 'works 3!');

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

get '/host' => {text => 'main application!'};

my $t = Test::Mojo->new;

# GET /foo/bar (plugin app)
$t->get_ok('/foo/bar')->status_is(200)->content_is('plugin works!');

# GET /hello (from main app)
$t->get_ok('/hello')->status_is(200)->content_is("Hello from the main app!\n");

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

# GET /just/works/too (from external embedded app)
$t->get_ok('/just/works/too')->status_is(200)->content_is("It just works!\n");

# GET /x/1/ (full external application)
$t->get_ok('/x/1/')->status_is(200)->content_is(<<'EOF');
works!Insecure!Insecure!

too!works!!!
<form action="/x/1/%E2%98%83">
  <input type="submit" value="☃" />
</form>
EOF

# GET /x/1/index.html (full external application)
$t->get_ok('/x/1/index.html')->status_is(200)
  ->content_is("External static file!\n");

# GET /x/1/echo (full external application)
$t->get_ok('/x/1/echo')->status_is(200)->content_is('echo: nothing!');

# GET /x/1/stream (full external application)
$t->get_ok('/x/1/stream')->status_is(200)->content_is('hello!');

# GET /x/1/url/☃ (full external application)
$t->get_ok('/x/1/url/☃')->status_is(200)
  ->content_is('/x/1/url/%E2%98%83 -> /x/1/%E2%98%83/stream!');

# GET /x/♥/ (full external application)
$t->get_ok('/x/♥/')->status_is(200)->content_is(<<'EOF');
works!Insecure!Insecure!

too!works!!!
<form action="/x/%E2%99%A5/%E2%98%83">
  <input type="submit" value="☃" />
</form>
EOF

# GET /x/♥/index.html (full external application)
$t->get_ok('/x/♥/index.html')->status_is(200)
  ->content_is("External static file!\n");

# GET /x/♥/echo (full external application)
$t->get_ok('/x/♥/echo')->status_is(200)->content_is('echo: works 2!');

# GET /x/♥/stream (full external application)
$t->get_ok('/x/♥/stream')->status_is(200)->content_is('hello!');

# GET /x/♥/url/☃ (full external application)
$t->get_ok('/x/♥/url/☃')->status_is(200)
  ->content_is('/x/%E2%99%A5/url/%E2%98%83 -> /x/%E2%99%A5/%E2%98%83/stream!');

# GET /host (main application)
$t->get_ok('/host')->status_is(200)->content_is('main application!');

# GET / (full external application with domain)
$t->get_ok('/' => {Host => 'mojolicious.org'})->status_is(200)
  ->content_is(<<'EOF');
works!Insecure!Insecure!

too!works!!!
<form action="/%E2%98%83">
  <input type="submit" value="☃" />
</form>
EOF

# GET /host (full external application with domain)
$t->get_ok('/host' => {Host => 'mojolicious.org'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('mojolicious.org');

# GET / (full external application with domain)
$t->get_ok('/' => {Host => 'mojolicio.us'})->status_is(200)
  ->content_is(<<'EOF');
works!Insecure!Insecure!

too!works!!!
<form action="/%E2%98%83">
  <input type="submit" value="☃" />
</form>
EOF

# GET /host (full external application with domain)
$t->get_ok('/host' => {Host => 'mojolicio.us'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('mojolicio.us');

# GET / (full external application with domain)
$t->get_ok('/' => {Host => 'kraih.com'})->status_is(200)->content_is(<<'EOF');
works!Insecure!Insecure!

too!works!!!
<form action="/%E2%98%83">
  <input type="submit" value="☃" />
</form>
EOF

# GET /host (full external application with domain)
$t->get_ok('/host' => {Host => 'KRaIH.CoM'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('kraih.com');

# GET /host (full external application with wildcard domain)
$t->get_ok('/host' => {Host => 'www.kraih.com'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('www.kraih.com');

# GET /host (full external application with wildcard domain)
$t->get_ok('/host' => {Host => 'foo.bar.kraih.com'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('foo.bar.kraih.com');

# GET /♥/123/ (full external application with a bit of everything)
$t->get_ok('/♥/123/' => {Host => 'foo-bar.de'})->status_is(200)
  ->content_is(<<'EOF');
works!Insecure!Insecure!

too!works!!!
<form action="/%E2%99%A5/123/%E2%98%83">
  <input type="submit" value="☃" />
</form>
EOF

# GET /♥/123/host (full external application with a bit of everything)
$t->get_ok('/♥/123/host' => {Host => 'foo-bar.de'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('foo-bar.de');

# GET /♥/123/echo (full external application with a bit of everything)
$t->get_ok('/♥/123/echo' => {Host => 'foo-bar.de'})->status_is(200)
  ->content_is('echo: works 3!');

# GET /♥/123/host (full external application with a bit of everything)
$t->get_ok('/♥/123/host' => {Host => 'www.foo-bar.de'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('www.foo-bar.de');

# GET /♥/123/echo (full external application with a bit of everything)
$t->get_ok('/♥/123/echo' => {Host => 'www.foo-bar.de'})->status_is(200)
  ->content_is('echo: works 3!');

# GET /♥/123/one (full external application with a bit of everything)
$t->get_ok('/♥/123/one' => {Host => 'www.foo-bar.de'})->status_is(200)
  ->content_is('One');

# GET /♥/123/one/two (full external application with a bit of everything)
$t->get_ok('/♥/123/one/two' => {Host => 'www.foo-bar.de'})->status_is(200)
  ->content_is('Two');

# GET /host (full external application with bad domain)
$t->get_ok('/' => {Host => 'mojoliciousxorg'})->status_is(404);

# GET /host (full external application with bad wildcard domain)
$t->get_ok('/' => {Host => 'www.kraihxcom'})->status_is(404);

__DATA__

@@ works.html.ep
Hello from the main app!
