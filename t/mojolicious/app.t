use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_MODE}    = 'development';
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 339;

use FindBin;
use lib "$FindBin::Bin/lib";

use File::Spec::Functions 'catdir';
use Mojo::Date;
use Mojo::Transaction::HTTP;
use Mojolicious;
use Test::Mojo;

# Missing config file
{
  eval { Test::Mojo->new('MojoliciousConfigTest')->app };
  like $@, qr/mojolicious_config_test.conf" missing/, 'right error';
  local $ENV{MOJO_MODE} = 'whatever';
  is(Test::Mojo->new('MojoliciousConfigTest')->app->config->{it},
    'works', 'right result');
}

my $t = Test::Mojo->new('MojoliciousTest');

# Application is already available
is $t->app->routes->find('something')->to_string, '/test4/:something',
  'right pattern';
is $t->app->routes->find('test3')->pattern->defaults->{namespace},
  'MojoliciousTestController', 'right namespace';
is $t->app->routes->find('authenticated')->pattern->defaults->{controller},
  'foo', 'right controller';
is ref $t->app->routes->find('something'), 'Mojolicious::Routes::Route',
  'right class';
is ref $t->app->routes->find('something')->root, 'Mojolicious::Routes',
  'right class';
is $t->app->sessions->cookie_domain, '.example.com', 'right domain';
is $t->app->sessions->cookie_path,   '/bar',         'right path';
is_deeply $t->app->commands->namespaces,
  [qw(Mojolicious::Command MojoliciousTest::Command)], 'right namespaces';
is $t->app, $t->app->commands->app, 'applications are equal';
is $t->app->static->file('hello.txt')->slurp,
  "Hello Mojo from a development static file!\n", 'right content';

# Plugin::Test::SomePlugin2::register (security violation)
$t->get_ok('/plugin-test-some_plugin2/register')->status_isnt(500)
  ->status_is(404)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_unlike(qr/Something/)->content_like(qr/Page not found/);

# Plugin::Test::SomePlugin2::register (security violation again)
$t->get_ok('/plugin-test-some_plugin2/register')->status_isnt(500)
  ->status_is(404)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_unlike(qr/Something/)->content_like(qr/Page not found/);

# Foo::fun
my $url = $t->ua->app_url;
$url->path('/fun/time');
$t->get_ok($url => {'X-Test' => 'Hi there!'})->status_isnt(404)
  ->status_is(200)->header_isnt('X-Bender' => 'Bite my shiny metal ass!')
  ->header_is('X-Bender' => undef)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_isnt('Have')
  ->content_is('Have fun!');

# Foo::baz (missing action without template)
$t->get_ok('/foo/baz')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_unlike(qr/Something/)->content_like(qr/Page not found/);

# Foo::yada (action-less template)
$t->get_ok('/foo/yada')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/look ma! no action!/);

# SyntaxError::foo (syntax error in controller)
$t->get_ok('/syntax_error/foo')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Missing right curly/);

# Foo::syntaxerror (syntax error in template)
$t->get_ok('/foo/syntaxerror')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Missing right curly/);

# Exceptional::this_one_dies (action dies)
$t->get_ok('/exceptional/this_one_dies')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is("doh!\n\n");

# Exceptional::this_one_might_die (bridge dies)
$t->get_ok('/exceptional_too/this_one_dies')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("double doh!\n\n");

# Exceptional::this_one_dies (action behind bridge dies)
$t->get_ok('/exceptional_too/this_one_dies' => {'X-DoNotDie' => 1})
  ->status_is(500)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is("doh!\n\n");

# Exceptional::this_one_does_not_exist (action does not exist)
$t->get_ok('/exceptional/this_one_does_not_exist')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Page not found/);

# Exceptional::this_one_does_not_exist (action behind bridge does not exist)
$t->get_ok('/exceptional_too/this_one_does_not_exist' => {'X-DoNotDie' => 1})
  ->status_is(404)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Page not found/);

# Foo::fun
$t->get_ok('/fun/time' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is('X-Bender' => undef)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Have fun!');

# Foo::fun
$url = $t->ua->app_url;
$url->path('/fun/time');
$t->get_ok($url => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is('X-Bender' => undef)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Have fun!');

# Foo::fun
$t->get_ok('/happy/fun/time' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is('X-Bender' => undef)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Have fun!');

# Foo::authenticated (authentication bridge)
$t->get_ok('/auth/authenticated' => {'X-Bender' => 'Hi there!'})
  ->status_is(200)->header_is('X-Bender' => undef)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('authenticated');

# Foo::authenticated (authentication bridge)
$t->get_ok('/auth/authenticated')->status_is(404)
  ->header_is('X-Bender' => undef)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Page not found/);

# Foo::test
$t->get_ok('/foo/test' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is('X-Bender'     => 'Bite my shiny metal ass!')
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr!/bar/test!);

# Foo::index
$t->get_ok('/foo' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr|<body>\s+23\nHello Mojo from the template /foo! He|);

# Foo::Bar::index
$t->get_ok('/foo-bar' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr|Hello Mojo from the other template /foo-bar!|);

# Foo::something
$t->get_ok('/somethingtest' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('/test4/42');

# Foo::url_for_missing
$t->get_ok('/something_missing' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('does_not_exist');

# Foo::templateless
$t->get_ok('/foo/templateless' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Hello Mojo from a templateless renderer!/);

# Foo::withlayout
$t->get_ok('/foo/withlayout' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Same old in green Seems to work!/);

# Foo::withblock
$t->get_ok('/foo/withblock.txt' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_isnt('text/html')->content_type_is('text/plain')
  ->content_like(qr/Hello Baerbel\.\s+Hello Wolfgang\./);

# MojoliciousTest2::Foo::test
$t->get_ok('/test2' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is('X-Bender'     => 'Bite my shiny metal ass!')
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr!/test2!);

# MojoliciousTestController::index
$t->get_ok('/test3' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is('X-Bender'     => 'Bite my shiny metal ass!')
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/No class works!/);

# MojoliciousTestController::index (only namespace)
$t->get_ok('/test5' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is('X-Bender'     => 'Bite my shiny metal ass!')
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('/test5');

# MojoliciousTestController::index (no namespace)
$t->get_ok('/test6' => {'X-Test' => 'Hi there!'})->status_is(200)
  ->header_is('X-Bender'     => 'Bite my shiny metal ass!')
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('/test6');

# 404
$t->get_ok('/' => {'X-Test' => 'Hi there!'})->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Page not found/);

# Static file /another/file (no extension)
$t->get_ok('/another/file')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_is('text/plain')->content_like(qr/Hello Mojolicious!/);

# Static directory /another
$t->get_ok('/another')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)');

# Check Last-Modified header for static files
my $path  = catdir($FindBin::Bin, 'public_dev', 'hello.txt');
my $size  = (stat $path)[7];
my $mtime = Mojo::Date->new((stat $path)[9])->to_string;

# Static file /hello.txt
$t->get_ok('/hello.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Last-Modified' => $mtime)->header_is('Content-Length' => $size)
  ->content_type_is('text/plain')
  ->content_like(qr/Hello Mojo from a development static file!/);

# Try to access a file which is not under the web root via path
# traversal
$t->get_ok('/../../mojolicious/secret.txt')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Page not found/);

# Check If-Modified-Since
$t->get_ok('/hello.txt' => {'If-Modified-Since' => $mtime})->status_is(304)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('');

# Embedded development static file
$t->get_ok('/some/static/file.txt')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Development static file with high precedence.\n");

# Embedded development template
$t->get_ok('/just/some/template')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Development template with high precedence.\n");

# Check develpment mode log level
my $app = Mojolicious->new;
is $app->log->level, 'debug', 'right log level';

# Make sure we can override attributes with constructor arguments
$app = MojoliciousTest->new({mode => 'test'});
is $app->mode, 'test', 'right mode';

# Persistent error
$app = MojoliciousTest->new;
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo');
$app->handler($tx);
is $tx->res->code, 200, 'right status';
like $tx->res->body, qr|Hello Mojo from the template /foo! Hello World!|,
  'right content';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo/willdie');
$app->handler($tx);
is $tx->res->code,   500,         'right status';
like $tx->res->body, qr/Foo\.pm/, 'right content';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo');
$app->handler($tx);
is $tx->res->code, 200, 'right status';
like $tx->res->body, qr|Hello Mojo from the template /foo! Hello World!|,
  'right content';

$t = Test::Mojo->new('SingleFileTestApp');

# SingleFileTestApp::Foo::index
$t->get_ok('/foo')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Same old in green Seems to work!/);

# SingleFileTestApp (helper)
$t->get_ok('/helper')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Welcome aboard!');

# PluginWithEmbeddedApp (lite app in plugin)
$t->get_ok('/plugin/foo')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('plugin works!');

# SingleFileTestApp::Foo::conf (config file)
$t->get_ok('/foo/conf')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('works!');

# SingleFileTestApp::Foo::data_template
$t->get_ok('/foo/data_template')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("23 works!\n");

# SingleFileTestApp::Foo::data_template
$t->get_ok('/foo/data_template2')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("This one works too!\n");

# SingleFileTestApp::Foo::data_static
$t->get_ok('/foo/data_static')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("And this one... ALL GLORY TO THE HYPNOTOAD!\n");

# SingleFileTestApp::Foo::routes
$t->get_ok('/foo/routes')->status_is(200)
  ->header_is('X-Bender'     => 'Bite my shiny metal ass!')
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/foo/routes');

# SingleFileTestApp::Redispatch::handler
$t->get_ok('/redispatch')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Redispatch!');

# SingleFileTestApp::Redispatch::render
$t->get_ok('/redispatch/render')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Render!');

# SingleFileTestApp::Redispatch::handler (targeting an existing method)
$t->get_ok('/redispatch/secret')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Redispatch!');

# SingleFileTestApp::Redispatch::secret
$t->get_ok('/redispatch/secret?rly=1')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Secret!');

$t = Test::Mojo->new('MojoliciousTest');

# MojoliciousTestController::Foo::plugin_upper_case
$t->get_ok('/plugin/upper_case')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('WELCOME aboard!');

# MojoliciousTestController::Foo::plugin_camel_case
$t->get_ok('/plugin/camel_case')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Welcome aboard!');

# MojoliciousTestController::Foo::stage2
$t->get_ok('/staged' => {'X-Pass' => '1'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Welcome aboard!');

# MojoliciousTestController::Foo::stage1
$t->get_ok('/staged')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Go away!');

# MojoliciousTest::Foo::config
$t->get_ok('/stash_config')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('123');

# Shortcuts to controller#action
$t->get_ok('/shortcut/ctrl-act')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('ctrl-act');
$t->get_ok('/shortcut/ctrl')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('ctrl');
$t->get_ok('/shortcut/act')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('act');

# Session with domain
$t->get_ok('/foo/session')->status_is(200)
  ->header_like('Set-Cookie' => qr/; domain=\.example\.com/)
  ->header_like('Set-Cookie' => qr!; path=/bar!)
  ->content_is('Bender rockzzz!');

# Mixed formats
$t->get_ok('/rss.xml')->status_is(200)->content_type_is('application/rss+xml')
  ->content_like(qr!<\?xml version="1.0" encoding="UTF-8"\?><rss />!);
