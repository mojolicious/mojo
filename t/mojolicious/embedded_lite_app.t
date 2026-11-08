use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;

use Mojo::File qw(curfile);
use lib curfile->sibling('lib')->to_string;

use Mojolicious::Lite;
use Test::Mojo;

package TestApp;
use Mojolicious::Lite;
use Mojo::Util qw(generate_secret);

app->secrets([generate_secret]);

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
use Mojo::Base 'Mojolicious';

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
my $external = curfile->sibling('external', 'myapp.pl');
plugin Mount => {'/x/1' => $external};
my $route = plugin(Mount => ('/x/♥' => $external))->to(message => 'works 2!');
is $route->to->{message},                       'works 2!', 'right message';
is $route->pattern->defaults->{app}->same_name, 'myapp',    'right name';
plugin Mount => {'/y/1'            => curfile->sibling('external', 'myapp2.pl')};
plugin Mount => {'mojolicious.org' => $external};
plugin(Mount => ('/y/♥' => curfile->sibling('external', 'myapp2.pl')))->to(message => 'works 3!');
plugin Mount => {'MOJOLICIOUS.ORG/' => $external};
plugin Mount => {'*.example.com'    => $external};
plugin(Mount => ('*.foo-bar.de/♥/123' => $external))->to(message => 'works 3!');

get '/hello' => 'works';

get('/bye' => {name => 'second embedded'})->partial(1)->to('MyTestApp::Test1');

get('/bar' => {name => 'third embedded'})->partial(1)->to(app => 'MyTestApp::Test1');

get('/baz')->partial(1)->to('test1#', name => 'fourth embedded');

get('/yada')->to('test1#', name => 'fifth embedded');

get('/yada/yada/yada')->to('test1#', path => '/yada', name => 'sixth embedded');

get('/basic')->partial(1)->to(MyTestApp::Basic->new, test => 'lalala');

get('/third' => {app => 'MyTestApp::Test2', name => 'third embedded'})->partial(1);

app->routes->any('/hello')->partial(1)->to(TestApp::app())->to(name => 'embedded');

get('/just' => {name => 'working'})->partial(1)->to('EmbeddedTestApp');

get '/host' => {text => 'main application!'};

my $t = Test::Mojo->new;

subtest 'PluginWithEmbeddedApp' => sub {
  $t->get_ok('/plugin/foo')->status_is(200)->content_is('plugin works!');
};

subtest 'main' => sub {
  $t->get_ok('/hello')->status_is(200)->content_is("Hello from the main app!\n");
};

subtest 'TestApp' => sub {
  $t->get_ok('/hello/hello')->status_is(200)->content_is('Hello from the embedded (1) app!');
};

subtest 'TestApp again' => sub {
  $t->get_ok('/hello/hello')->status_is(200)->content_is('Hello from the embedded (2) app!');
};

subtest 'TestApp again' => sub {
  $t->get_ok('/hello/hello')->status_is(200)->content_is('Hello from the embedded (3) app!');
};

subtest 'MyTestApp::Test1' => sub {
  $t->get_ok('/bye/bye')->status_is(200)->content_is('Hello from the embedded (1) app!second embedded! success!');
};

subtest 'MyTestApp::Test1 with different prefix' => sub {
  $t->get_ok('/bar/bye')->status_is(200)->content_is('Hello from the embedded (2) app!third embedded! success!');
};

subtest 'MyTestApp::Test1 with yet another prefix' => sub {
  $t->get_ok('/baz/bye')->status_is(200)->content_is('Hello from the embedded (3) app!fourth embedded! success!');
};

subtest '::Test1 without prefix' => sub {
  $t->get_ok('/yada')->status_is(200)->content_is('yada fifth embedded works!');
};

subtest '404 from MyTestApp::Test1' => sub {
  $t->get_ok('/yada/yada')->status_is(404);
};

subtest 'MyTestApp::Test1 with a long prefix' => sub {
  $t->get_ok('/yada/yada/yada')->status_is(200)->content_is('yada sixth embedded works!');
};

subtest 'MyTestApp::Basic' => sub {
  $t->get_ok('/basic')->status_is(200)->content_is('Hello lalala!');
};

subtest 'MyTestApp::Test2' => sub {
  $t->get_ok('/third')->status_is(200)->content_is('Bye from the third embedded app! /third!');
};

subtest 'EmbeddedTestApp' => sub {
  $t->get_ok('/just/works')->status_is(200)->content_is("It is working!\n");
};

subtest 'EmbeddedTestApp again' => sub {
  $t->get_ok('/just/works/too')->status_is(200)->content_is("It just works!\n");
};

subtest 'Template from myapp.pl' => sub {
  $t->get_ok('/x/1/')->status_is(200)->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/x/1/">Test</a>
<form action="/x/1/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF
};

subtest 'Template from myapp.pl (no trailing slash)' => sub {
  $t->get_ok('/x/1')->status_is(200)->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/x/1/">Test</a>
<form action="/x/1/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF
};

subtest 'Static file from myapp.pl' => sub {
  $t->get_ok('/x/1/index.html')->status_is(200)->content_is("External static file!\n");
};

subtest 'Echo from myapp.pl' => sub {
  $t->get_ok('/x/1/echo')->status_is(200)->content_is('echo: nothing!');
};

subtest 'Stream from myapp.pl' => sub {
  $t->get_ok('/x/1/stream')->status_is(200)->content_is('hello!');
};

subtest 'URL from myapp.pl' => sub {
  $t->get_ok('/x/1/url/☃')->status_is(200)->content_is('/x/1/url/%E2%98%83.json -> /x/1/%E2%98%83/stream!');
};

subtest 'Route to template from myapp.pl' => sub {
  $t->get_ok('/x/1/template/menubar')->status_is(200)->content_is("myapp\nworks ♥!Insecure!Insecure!\n");
};

subtest 'Missing template from myapp.pl' => sub {
  $t->get_ok('/x/1/template/does_not_exist')->status_is(500)->content_like(qr/Server Error/);
};

subtest 'Template from myapp.pl with Unicode prefix' => sub {
  $t->get_ok('/x/♥/')->status_is(200)->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/x/%E2%99%A5/">Test</a>
<form action="/x/%E2%99%A5/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF
};

subtest 'Template from myapp.pl with Unicode prefix (no trailing slash)' => sub {
  $t->get_ok('/x/♥')->status_is(200)->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/x/%E2%99%A5/">Test</a>
<form action="/x/%E2%99%A5/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF
};

subtest 'Static file from myapp.pl with Unicode prefix' => sub {
  $t->get_ok('/x/♥/index.html')->status_is(200)->content_is("External static file!\n");
};

subtest 'Echo from myapp.pl with Unicode prefix' => sub {
  $t->get_ok('/x/♥/echo')->status_is(200)->content_is('echo: works 2!');
};

subtest 'Stream from myapp.pl with Unicode prefix' => sub {
  $t->get_ok('/x/♥/stream')->status_is(200)->content_is('hello!');
};

subtest 'URL from myapp.pl with Unicode prefix' => sub {
  $t->get_ok('/x/♥/url/☃')
    ->status_is(200)
    ->content_is('/x/%E2%99%A5/url/%E2%98%83.json -> /x/%E2%99%A5/%E2%98%83/stream!');
};

subtest 'Route to template from myapp.pl with Unicode prefix' => sub {
  $t->get_ok('/x/♥/template/menubar')->status_is(200)->content_is("myapp\nworks ♥!Insecure!Insecure!\n");
};

subtest 'Missing template from myapp.pl with Unicode prefix' => sub {
  $t->get_ok('/x/♥/template/does_not_exist')->status_is(500)->content_like(qr/Server Error/);
};

subtest 'A little bit of everything from myapp2.pl' => sub {
  $t->get_ok('/y/1')->status_is(200)->content_is("myapp2\nworks 4!\nInsecure too!");
};

subtest 'Route to template from myapp.pl again (helpers sharing the same name)' => sub {
  $t->get_ok('/x/1/template/menubar')->status_is(200)->content_is("myapp\nworks ♥!Insecure!Insecure!\n");
};

subtest 'Caching helper from myapp2.pl' => sub {
  $t->get_ok('/y/1/cached?cache=foo')->status_is(200)->content_is('foo');
};

subtest 'Caching helper with cached value from myapp2.pl' => sub {
  $t->get_ok('/y/1/cached?cache=fail')->status_is(200)->content_is('foo');
};

subtest '404 from myapp2.pl' => sub {
  $t->get_ok('/y/1/2')->status_is(404);
};

subtest 'myapp2.pl with Unicode prefix' => sub {
  $t->get_ok('/y/♥')->status_is(200)->content_is("myapp2\nworks 3!\nInsecure too!");
};

subtest 'Caching helper from myapp2.pl with Unicode prefix' => sub {
  $t->get_ok('/y/♥/cached?cache=bar')->status_is(200)->content_is('bar');
};

subtest 'Caching helper with cached value from myapp2.pl with Unicode prefix' => sub {
  $t->get_ok('/y/♥/cached?cache=fail')->status_is(200)->content_is('bar');
};

subtest '404 from myapp2.pl with Unicode prefix' => sub {
  $t->get_ok('/y/♥/2')->status_is(404);
};

subtest 'main' => sub {
  $t->get_ok('/host')->status_is(200)->content_is('main application!');
};

subtest 'Template from myapp.pl with domain' => sub {
  $t->get_ok('/' => {Host => 'mojolicious.org'})->status_is(200)->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/">Test</a>
<form action="/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF
};

subtest 'Host from myapp.pl with domain' => sub {
  $t->get_ok('/host' => {Host => 'mojolicious.org'})
    ->status_is(200)
    ->header_is('X-Message' => 'it works!')
    ->content_is('mojolicious.org');
};

subtest 'Template from myapp.pl with domain again' => sub {
  $t->get_ok('/' => {Host => 'mojolicious.org'})->status_is(200)->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/">Test</a>
<form action="/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF
};

subtest 'Host from myapp.pl with domain again' => sub {
  $t->get_ok('/host' => {Host => 'mojolicious.org'})
    ->status_is(200)
    ->header_is('X-Message' => 'it works!')
    ->content_is('mojolicious.org');
};

subtest 'Template from myapp.pl with wildcard domain' => sub {
  $t->get_ok('/' => {Host => 'example.com'})->status_is(200)->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/">Test</a>
<form action="/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF
};

subtest 'Host from myapp.pl with wildcard domain' => sub {
  $t->get_ok('/host' => {Host => 'ExAmPlE.CoM'})
    ->status_is(200)
    ->header_is('X-Message' => 'it works!')
    ->content_is('ExAmPlE.CoM');
};

subtest 'Host from myapp.pl with wildcard domain again' => sub {
  $t->get_ok('/host' => {Host => 'www.example.com'})
    ->status_is(200)
    ->header_is('X-Message' => 'it works!')
    ->content_is('www.example.com');
};

subtest 'Host from myapp.pl with wildcard domain again' => sub {
  $t->get_ok('/host' => {Host => 'foo.bar.example.com'})
    ->status_is(200)
    ->header_is('X-Message' => 'it works!')
    ->content_is('foo.bar.example.com');
};

subtest 'Template from myapp.pl with wildcard domain and Unicode prefix' => sub {
  $t->get_ok('/♥/123/' => {Host => 'foo-bar.de'})->status_is(200)->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/%E2%99%A5/123/">Test</a>
<form action="/%E2%99%A5/123/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF
};

subtest 'Host from myapp.pl with wildcard domain and Unicode prefix' => sub {
  $t->get_ok('/♥/123/host' => {Host => 'foo-bar.de'})
    ->status_is(200)
    ->header_is('X-Message' => 'it works!')
    ->content_is('foo-bar.de');
};

subtest 'Echo from myapp.pl with wildcard domain and Unicode prefix' => sub {
  $t->get_ok('/♥/123/echo' => {Host => 'foo-bar.de'})->status_is(200)->content_is('echo: works 3!');
};

subtest 'Host from myapp.pl with wildcard domain and Unicode prefix again' => sub {
  $t->get_ok('/♥/123/host' => {Host => 'www.foo-bar.de'})
    ->status_is(200)
    ->header_is('X-Message' => 'it works!')
    ->content_is('www.foo-bar.de');
};

subtest 'Host from myapp.pl with wildcard domain and Unicode prefix again' => sub {
  $t->get_ok('/♥/123/echo' => {Host => 'www.foo-bar.de'})->status_is(200)->content_is('echo: works 3!');
};

subtest 'Text from myapp.pl with wildcard domain and Unicode prefix' => sub {
  $t->get_ok('/♥/123/one' => {Host => 'www.foo-bar.de'})->status_is(200)->content_is('One');
};

subtest 'Another text from myapp.pl with wildcard domain and Unicode prefix' => sub {
  $t->get_ok('/♥/123/one/two' => {Host => 'www.foo-bar.de'})->status_is(200)->content_is('Two');
};

subtest 'Invalid domain' => sub {
  $t->get_ok('/' => {Host => 'mojoliciousxorg'})->status_is(404);
};

subtest 'Another invalid domain' => sub {
  $t->get_ok('/' => {Host => 'www.kraihxcom'})->status_is(404);
};

subtest 'Embedded WebSocket' => sub {
  $t->websocket_ok('/x/♥/url_for')
    ->send_ok('ws_test')
    ->message_ok->message_like(qr!^ws://127\.0\.0\.1:\d+/x/%E2%99%A5/url_for$!)
    ->send_ok('index')
    ->message_ok->message_like(qr!^http://127\.0\.0\.1:\d+/x/%E2%99%A5$!)->finish_ok;
};

subtest 'Template from myapp.pl (shared logger)' => sub {
  my $logs = $t->app->log->capture('trace');
  $t->get_ok('/x/1')->status_is(200)->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/x/1/">Test</a>
<form action="/x/1/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF
  like $logs, qr/Routing to application "Mojolicious::Lite"/,                    'right message';
  like $logs, qr/Rendering cached template "menubar.html.ep" from DATA section/, 'right message';
  undef $logs;
};

done_testing();

__DATA__

@@ works.html.ep
Hello from the main app!
