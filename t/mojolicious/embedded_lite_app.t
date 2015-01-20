use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;

use FindBin;
use lib "$FindBin::Bin/lib";

use Mojolicious::Lite;
use Test::Mojo;

package TestApp;
use Mojolicious::Lite;

get '/hello' => sub {
  my $c       = shift;
  my $name    = $c->stash('name');
  my $counter = ++$c->session->{counter};
  $c->render(text => "Hello from the $name ($counter) app!");
};

package MyTestApp::Test1;
use Mojolicious::Lite;

get '/yada' => sub {
  my $c    = shift;
  my $name = $c->stash('name');
  $c->render(text => "yada $name works!");
};

get '/bye' => sub {
  my $c    = shift;
  my $name = $c->stash('name');
  my $nb   = '';
  $c->ua->server->app(main::app());
  $c->ua->get(
    '/hello/hello' => sub {
      my ($ua, $tx) = @_;
      $c->render(text => $tx->res->body . "$name! $nb");
    }
  );
  $nb .= 'success!';
};

package MyTestApp::Test2;
use Mojolicious::Lite;

get '/' => sub {
  my $c    = shift;
  my $name = $c->param('name');
  my $url  = $c->url_for;
  $c->render(text => "Bye from the $name app! $url!");
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

# Plugin app
plugin 'PluginWithEmbeddedApp';

app->routes->namespaces(['MyTestApp']);

# Mount full external application a few times
my $external = "$FindBin::Bin/external/myapp.pl";
plugin Mount => {'/x/1' => $external};
my $route
  = plugin(Mount => ('/x/♥' => $external))->to(message => 'works 2!');
is $route->to->{message}, 'works 2!', 'right message';
is $route->pattern->defaults->{app}->same_name, 'myapp', 'right name';
plugin Mount => {'/y/1'            => "$FindBin::Bin/external/myapp2.pl"};
plugin Mount => {'mojolicious.org' => $external};
plugin(Mount => ('/y/♥' => "$FindBin::Bin/external/myapp2.pl"))
  ->to(message => 'works 3!');
plugin Mount => {'MOJOLICIO.US/' => $external};
plugin Mount => {'*.example.com' => $external};
plugin(Mount => ('*.foo-bar.de/♥/123' => $external))
  ->to(message => 'works 3!');

get '/hello' => 'works';

get('/bye' => {name => 'second embedded'})->detour('MyTestApp::Test1');

get('/bar' => {name => 'third embedded'})->detour(app => 'MyTestApp::Test1');

get('/baz')->detour('test1#', name => 'fourth embedded');

get('/yada')->to('test1#', name => 'fifth embedded');

get('/yada/yada/yada')
  ->to('test1#', path => '/yada', name => 'sixth embedded');

get('/basic')->detour(MyTestApp::Basic->new, test => 'lalala');

get '/third/*path' =>
  {app => 'MyTestApp::Test2', name => 'third embedded', path => '/'};

app->routes->route('/hello')->detour(TestApp::app())->to(name => 'embedded');

get('/just' => {name => 'working'})->detour('EmbeddedTestApp');

get '/host' => {text => 'main application!'};

my $t = Test::Mojo->new;

# PluginWithEmbeddedApp
$t->get_ok('/plugin/foo')->status_is(200)->content_is('plugin works!');

# main
$t->get_ok('/hello')->status_is(200)->content_is("Hello from the main app!\n");

# TestApp
$t->get_ok('/hello/hello')->status_is(200)
  ->content_is('Hello from the embedded (1) app!');

# TestApp again
$t->get_ok('/hello/hello')->status_is(200)
  ->content_is('Hello from the embedded (2) app!');

# TestApp again
$t->get_ok('/hello/hello')->status_is(200)
  ->content_is('Hello from the embedded (3) app!');

# MyTestApp::Test1
$t->get_ok('/bye/bye')->status_is(200)
  ->content_is('Hello from the embedded (1) app!second embedded! success!');

# MyTestApp::Test1 with different prefix
$t->get_ok('/bar/bye')->status_is(200)
  ->content_is('Hello from the embedded (2) app!third embedded! success!');

# MyTestApp::Test1 with yet another prefix
$t->get_ok('/baz/bye')->status_is(200)
  ->content_is('Hello from the embedded (3) app!fourth embedded! success!');

# MyTestApp::Test1 without prefix
$t->get_ok('/yada')->status_is(200)->content_is('yada fifth embedded works!');

# 404 from MyTestApp::Test1
$t->get_ok('/yada/yada')->status_is(404);

# MyTestApp::Test1 with a long prefix
$t->get_ok('/yada/yada/yada')->status_is(200)
  ->content_is('yada sixth embedded works!');

# MyTestApp::Basic
$t->get_ok('/basic')->status_is(200)->content_is('Hello lalala!');

# MyTestApp::Test2
$t->get_ok('/third')->status_is(200)
  ->content_is('Bye from the third embedded app! /third!');

# EmbeddedTestApp
$t->get_ok('/just/works')->status_is(200)->content_is("It is working!\n");

# EmbeddedTestApp again
$t->get_ok('/just/works/too')->status_is(200)->content_is("It just works!\n");

# Template from myapp.pl
$t->get_ok('/x/1/')->status_is(200)->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/x/1/">Test</a>
<form action="/x/1/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF

# Static file from myapp.pl
$t->get_ok('/x/1/index.html')->status_is(200)
  ->content_is("External static file!\n");

# Echo from myapp.pl
$t->get_ok('/x/1/echo')->status_is(200)->content_is('echo: nothing!');

# Stream from myapp.pl
$t->get_ok('/x/1/stream')->status_is(200)->content_is('hello!');

# URL from myapp.pl
$t->get_ok('/x/1/url/☃')->status_is(200)
  ->content_is('/x/1/url/%E2%98%83.json -> /x/1/%E2%98%83/stream!');

# Route to template from myapp.pl
$t->get_ok('/x/1/template/menubar')->status_is(200)
  ->content_is("myapp\nworks ♥!Insecure!Insecure!\n");

# Missing template from myapp.pl
$t->get_ok('/x/1/template/does_not_exist')->status_is(404);

# Template from myapp.pl with Unicode prefix
$t->get_ok('/x/♥/')->status_is(200)->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/x/%E2%99%A5/">Test</a>
<form action="/x/%E2%99%A5/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF

# Static file from myapp.pl with Unicode prefix
$t->get_ok('/x/♥/index.html')->status_is(200)
  ->content_is("External static file!\n");

# Echo from myapp.pl with Unicode prefix
$t->get_ok('/x/♥/echo')->status_is(200)->content_is('echo: works 2!');

# Stream from myapp.pl with Unicode prefix
$t->get_ok('/x/♥/stream')->status_is(200)->content_is('hello!');

# URL from myapp.pl with Unicode prefix
$t->get_ok('/x/♥/url/☃')->status_is(200)
  ->content_is(
  '/x/%E2%99%A5/url/%E2%98%83.json -> /x/%E2%99%A5/%E2%98%83/stream!');

# Route to template from myapp.pl with Unicode prefix
$t->get_ok('/x/♥/template/menubar')->status_is(200)
  ->content_is("myapp\nworks ♥!Insecure!Insecure!\n");

# Missing template from myapp.pl with Unicode prefix
$t->get_ok('/x/♥/template/does_not_exist')->status_is(404);

# A little bit of everything from myapp2.pl
$t->get_ok('/y/1')->status_is(200)
  ->content_is("myapp2\nworks 4!\nInsecure too!");

# Route to template from myapp.pl again (helpers sharing the same name)
$t->get_ok('/x/1/template/menubar')->status_is(200)
  ->content_is("myapp\nworks ♥!Insecure!Insecure!\n");

# Caching helper from myapp2.pl
$t->get_ok('/y/1/cached?cache=foo')->status_is(200)->content_is('foo');

# Caching helper with cached value from myapp2.pl
$t->get_ok('/y/1/cached?cache=fail')->status_is(200)->content_is('foo');

# 404 from myapp2.pl
$t->get_ok('/y/1/2')->status_is(404);

# myapp2.pl with Unicode prefix
$t->get_ok('/y/♥')->status_is(200)
  ->content_is("myapp2\nworks 3!\nInsecure too!");

# Caching helper from myapp2.pl with Unicode prefix
$t->get_ok('/y/♥/cached?cache=bar')->status_is(200)->content_is('bar');

# Caching helper with cached value from myapp2.pl with Unicode prefix
$t->get_ok('/y/♥/cached?cache=fail')->status_is(200)->content_is('bar');

# 404 from myapp2.pl with Unicode prefix
$t->get_ok('/y/♥/2')->status_is(404);

# main
$t->get_ok('/host')->status_is(200)->content_is('main application!');

# Template from myapp.pl with domain
$t->get_ok('/' => {Host => 'mojolicious.org'})->status_is(200)
  ->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/">Test</a>
<form action="/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF

# Host from myapp.pl with domain
$t->get_ok('/host' => {Host => 'mojolicious.org'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('mojolicious.org');

# Template from myapp.pl with domain again
$t->get_ok('/' => {Host => 'mojolicio.us'})->status_is(200)
  ->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/">Test</a>
<form action="/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF

# Host from myapp.pl with domain again
$t->get_ok('/host' => {Host => 'mojolicio.us'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('mojolicio.us');

# Template from myapp.pl with wildcard domain
$t->get_ok('/' => {Host => 'example.com'})->status_is(200)
  ->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/">Test</a>
<form action="/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF

# Host from myapp.pl with wildcard domain
$t->get_ok('/host' => {Host => 'ExAmPlE.CoM'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('ExAmPlE.CoM');

# Host from myapp.pl with wildcard domain again
$t->get_ok('/host' => {Host => 'www.example.com'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('www.example.com');

# Host from myapp.pl with wildcard domain again
$t->get_ok('/host' => {Host => 'foo.bar.example.com'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('foo.bar.example.com');

# Template from myapp.pl with wildcard domain and Unicode prefix
$t->get_ok('/♥/123/' => {Host => 'foo-bar.de'})->status_is(200)
  ->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/%E2%99%A5/123/">Test</a>
<form action="/%E2%99%A5/123/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF

# Host from myapp.pl with wildcard domain and Unicode prefix
$t->get_ok('/♥/123/host' => {Host => 'foo-bar.de'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('foo-bar.de');

# Echo from myapp.pl with wildcard domain and Unicode prefix
$t->get_ok('/♥/123/echo' => {Host => 'foo-bar.de'})->status_is(200)
  ->content_is('echo: works 3!');

# Host from myapp.pl with wildcard domain and Unicode prefix again
$t->get_ok('/♥/123/host' => {Host => 'www.foo-bar.de'})->status_is(200)
  ->header_is('X-Message' => 'it works!')->content_is('www.foo-bar.de');

# Host from myapp.pl with wildcard domain and Unicode prefix again
$t->get_ok('/♥/123/echo' => {Host => 'www.foo-bar.de'})->status_is(200)
  ->content_is('echo: works 3!');

# Text from myapp.pl with wildcard domain and Unicode prefix
$t->get_ok('/♥/123/one' => {Host => 'www.foo-bar.de'})->status_is(200)
  ->content_is('One');

# Another text from myapp.pl with wildcard domain and Unicode prefix
$t->get_ok('/♥/123/one/two' => {Host => 'www.foo-bar.de'})->status_is(200)
  ->content_is('Two');

# Invalid domain
$t->get_ok('/' => {Host => 'mojoliciousxorg'})->status_is(404);

# Another invalid domain
$t->get_ok('/' => {Host => 'www.kraihxcom'})->status_is(404);

# Embedded WebSocket
$t->websocket_ok('/x/♥/url_for')->send_ok('ws_test')
  ->message_ok->message_like(qr!^ws://127\.0\.0\.1:\d+/x/%E2%99%A5/url_for$!)
  ->send_ok('index')
  ->message_ok->message_like(qr!^http://127\.0\.0\.1:\d+/x/%E2%99%A5$!)
  ->finish_ok;

done_testing();

__DATA__

@@ works.html.ep
Hello from the main app!
