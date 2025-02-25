use Mojo::Base -strict;

BEGIN {
  $ENV{PLACK_ENV}    = undef;
  $ENV{MOJO_MODE}    = 'development';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::Mojo;
use Test::More;

use Mojo::File qw(curfile);
use lib curfile->sibling('lib')->to_string;

use Mojo::Asset::File;
use Mojo::Date;
use Mojo::File qw(path);
use Mojo::Home;
use Mojo::IOLoop;
use Mojolicious;
use Mojolicious::Controller;

subtest 'Missing config file' => sub {
  eval { Test::Mojo->new('MojoliciousConfigTest')->app };
  like $@, qr/mojolicious_config_test.conf" missing/, 'right error';
  local $ENV{MOJO_MODE} = 'whatever';
  is(Test::Mojo->new('MojoliciousConfigTest')->app->config->{it}, 'works', 'right result');
};

subtest 'Bad deployment plugins' => sub {
  eval { Test::Mojo->new('MojoliciousTest')->app->plugin(Config => {default => {plugins => 'fail'}}) };
  like $@, qr/Configuration value "plugins" is not an array reference/, 'right error';
  eval { Test::Mojo->new('MojoliciousTest')->app->plugin(Config => {default => {plugins => ['fail']}}) };
  like $@, qr/Configuration value "plugins" contains an entry that is not a hash reference/, 'right error';
};

# Mode detection
{
  local $ENV{MOJO_MODE} = undef;
  local $ENV{PLACK_ENV} = 'something';
  is(Test::Mojo->new('MojoliciousTest')->app->mode, 'something', 'right mode');
}
{
  local $ENV{MOJO_MODE} = 'else';
  local $ENV{PLACK_ENV} = 'something';
  is(Test::Mojo->new('MojoliciousTest')->app->mode, 'else', 'right mode');
}

# Optional home detection
my @path = qw(th is mojo dir wil l never-ever exist);
my $app  = Mojolicious->new(home => Mojo::Home->new(@path));
is $app->home, path(@path), 'right home directory';

subtest 'Config override' => sub {
  my $t = Test::Mojo->new('MojoliciousTest');
  ok !$t->app->config->{config_override}, 'no override';
  ok !$t->app->config->{foo},             'no value';
  $t = Test::Mojo->new('MojoliciousTest', {foo => 'bar'});
  ok $t->app->config->{config_override}, 'override';
  is $t->app->config->{foo}, 'bar', 'right value';
  $t = Test::Mojo->new(MojoliciousTest->new, {foo => 'baz'});
  ok $t->app->config->{config_override}, 'override';
  is $t->app->config->{foo}, 'baz', 'right value';

  my $app = Mojolicious->new;
  $t = Test::Mojo->new($app);
  ok !$t->app->config->{config_override}, 'no override';
  ok !$t->app->config->{foo},             'no value';
  $t = Test::Mojo->new($app, {foo => 'bar'});
  ok $t->app->config->{config_override}, 'override';
  is $t->app->config->{foo}, 'bar', 'right value';
};

my $t = Test::Mojo->new('MojoliciousTest');

subtest 'Preload namespaces' => sub {
  is_deeply $t->app->preload_namespaces, ['MojoliciousTest::Controller'], 'right namespaces';
  ok !!MojoliciousTest::Controller::Foo::Bar->can('new'), 'preloaded controller';
};

# Application is already available
is $t->app->routes->find('something')->to_string,                       '/test4/:something',     'right pattern';
is $t->app->routes->find('test3')->pattern->defaults->{namespace},      'MojoliciousTest2::Foo', 'right namespace';
is $t->app->routes->find('withblock')->pattern->defaults->{controller}, 'foo',                   'right controller';
is ref $t->app->routes->find('something'),                              'Mojolicious::Routes::Route', 'right class';
is ref $t->app->routes->find('something')->root,                        'Mojolicious::Routes',        'right class';
is $t->app->sessions->cookie_domain,                                    '.example.com',               'right domain';
is $t->app->sessions->cookie_path,                                      '/bar',                       'right path';
is_deeply $t->app->commands->namespaces,
  ['Mojolicious::Command::Author', 'Mojolicious::Command', 'MojoliciousTest::Command'], 'right namespaces';
is $t->app,                                   $t->app->commands->app,                         'applications are equal';
is $t->app->static->file('hello.txt')->slurp, "Hello Mojo from a development static file!\n", 'right content';
is $t->app->static->file('does_not_exist.html'), undef,              'no file';
is $t->app->moniker,                             'mojolicious_test', 'right moniker';
is $t->app->secrets->[0],                        $t->app->moniker,   'secret defaults to moniker';
is $t->app->renderer->template_handler({template => 'foo/bar/index', format => 'html'}), 'epl',   'right handler';
is $t->app->build_controller->req->url,                                                  '',      'no URL';
is $t->app->build_controller->render_to_string('does_not_exist'),                        undef,   'no result';
is $t->app->build_controller->render_to_string(inline => '%= $c', c => 'foo'),           "foo\n", 'right result';

# Missing methods and functions (AUTOLOAD)
eval { $t->app->missing };
like $@, qr/^Can't locate object method "missing" via package "MojoliciousTest"/, 'right error';
eval { Mojolicious::missing() };
like $@, qr/^Undefined subroutine &Mojolicious::missing called/, 'right error';
my $c = $t->app->build_controller;
eval { $c->missing };
like $@, qr/^Can't locate object method "missing" via package "@{[ref $c]}"/, 'right error';
eval { Mojolicious::Controller::missing() };
like $@, qr/^Undefined subroutine &Mojolicious::Controller::missing called/, 'right error';
eval { $t->app->routes->missing };
like $@, qr/^Can't locate object method "missing" via package "Mojolicious::Routes"/, 'right error';
eval { Mojolicious::Route::missing() };
like $@, qr/^Undefined subroutine &Mojolicious::Route::missing called/, 'right error';

subtest 'Reserved stash value' => sub {
  ok !$t->app->routes->is_reserved('foo'),       'not reserved';
  ok $t->app->routes->is_reserved('action'),     'is reserved';
  ok $t->app->routes->is_reserved('app'),        'is reserved';
  ok $t->app->routes->is_reserved('cb'),         'is reserved';
  ok $t->app->routes->is_reserved('controller'), 'is reserved';
  ok $t->app->routes->is_reserved('data'),       'is reserved';
  ok $t->app->routes->is_reserved('extends'),    'is reserved';
  ok $t->app->routes->is_reserved('format'),     'is reserved';
  ok $t->app->routes->is_reserved('handler'),    'is reserved';
  ok $t->app->routes->is_reserved('inline'),     'is reserved';
  ok $t->app->routes->is_reserved('json'),       'is reserved';
  ok $t->app->routes->is_reserved('layout'),     'is reserved';
  ok $t->app->routes->is_reserved('namespace'),  'is reserved';
  ok $t->app->routes->is_reserved('path'),       'is reserved';
  ok $t->app->routes->is_reserved('status'),     'is reserved';
  ok $t->app->routes->is_reserved('template'),   'is reserved';
  ok $t->app->routes->is_reserved('text'),       'is reserved';
  ok $t->app->routes->is_reserved('variant'),    'is reserved';
};

subtest 'Reserved stash value (in placeholder)' => sub {
  eval { $t->app->routes->any('/:controller') };
  like $@, qr/Route pattern "\/:controller" contains a reserved stash value/, 'right error';
  eval { $t->app->routes->any('/:action') };
  like $@, qr/Route pattern "\/:action" contains a reserved stash value/, 'right error';
  eval { $t->app->routes->any('/foo/:text') };
  like $@, qr/Route pattern "\/foo\/:text" contains a reserved stash value/, 'right error';
  eval { $t->app->routes->any('/foo/<text:num>') };
  like $@, qr/Route pattern "\/foo\/<text:num>" contains a reserved stash value/, 'right error';
};

# Unknown hooks
ok !$t->app->plugins->emit_chain('does_not_exist'),         'hook has been emitted';
ok !!$t->app->plugins->emit_hook('does_not_exist'),         'hook has been emitted';
ok !!$t->app->plugins->emit_hook_reverse('does_not_exist'), 'hook has been emitted';

# Custom hooks
my $custom;
$t->app->hook('custom_hook' => sub { $custom += shift });
$t->app->plugins->emit_hook(custom_hook => 1);
is $custom, 1, 'hook has been emitted';
$t->app->plugins->emit_hook_reverse(custom_hook => 2);
is $custom, 3, 'hook has been emitted again';
$t->app->hook('custom_chain' => sub { return shift->() * 2 });
$t->app->hook('custom_chain' => sub { return pop });
is $t->app->plugins->emit_chain(custom_chain => 4), 8, 'hook has been emitted';

# MojoliciousTest::Command::test_command (with abbreviation)
is $t->app->start(qw(test_command --to)), 'works too!', 'right result';

# Plugin::Test::SomePlugin2::register (security violation)
$t->get_ok('/plugin-test-some_plugin2/register')
  ->status_isnt(404)
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_unlike(qr/Something/)
  ->content_like(qr/Class "MojoliciousTest::Plugin::Test::SomePlugin2" is not a controller/);

# Plugin::Test::SomePlugin2::register (security violation again)
my $logs = $t->app->log->capture('trace');
$t->get_ok('/plugin-test-some_plugin2/register')
  ->status_isnt(404)
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_unlike(qr/Something/)
  ->content_like(qr/Class "MojoliciousTest::Plugin::Test::SomePlugin2" is not a controller/);
like $logs, qr/Class "MojoliciousTest::Plugin::Test::SomePlugin2" is not a controller/, 'right message';
undef $logs;

# Foo::fun (with a lot of different tests)
my $url = $t->ua->server->url;
$url->path('/fun/time');
$t->get_ok($url => {'X-Test' => 'Hi there!'})
  ->status_isnt(404)
  ->status_is(200)
  ->status_is(200, 'with description')
  ->status_isnt(500)
  ->status_isnt(500, 'with description')
  ->header_is('X-Bender' => undef)
  ->header_is(Server     => 'Mojolicious (Perl)')
  ->header_is(Server     => 'Mojolicious (Perl)', 'with description')
  ->header_isnt(Server => 'Whatever')
  ->header_isnt(Server => 'Whatever', 'with description')
  ->header_like(Server => qr/Mojolicious/)
  ->header_like(Server => qr/Mojolicious/, 'with description')
  ->header_unlike(Server => qr/Bender/)
  ->header_unlike(Server => qr/Bender/, 'with description')
  ->content_type_is('text/html;charset=UTF-8')
  ->content_type_is('text/html;charset=UTF-8', 'with description')
  ->content_type_isnt('text/plain')
  ->content_type_isnt('text/plain', 'with description')
  ->content_type_like(qr/html/)
  ->content_type_like(qr/html/, 'with description')
  ->content_type_unlike(qr/plain/)
  ->content_type_unlike(qr/plain/, 'with description')
  ->content_isnt('Have')
  ->content_isnt('Have', 'with description')
  ->content_is('<p>Have fun!</p>')
  ->content_is('<p>Have fun!</p>', 'with description')
  ->content_like(qr/fun/)
  ->content_like(qr/fun/, 'with description')
  ->content_unlike(qr/boring/)
  ->content_unlike(qr/boring/, 'with description')
  ->element_exists('p')
  ->element_exists('p', 'with description')
  ->element_exists_not('b')
  ->element_exists_not('b', 'with description')
  ->text_is('p',        'Have fun!')
  ->text_is('p',        'Have fun!', 'with description')
  ->text_is('notfound', undef)
  ->text_isnt('p', 'Have')
  ->text_isnt('p', 'Have', 'with description')
  ->text_like('p', qr/fun/)
  ->text_like('p', qr/fun/, 'with description')
  ->text_unlike('p', qr/boring/)
  ->text_unlike('p', qr/boring/, 'with description');

# Foo::joy (testing HTML attributes in template)
$t->get_ok('/fun/joy')
  ->status_is(200)
  ->attr_is('p.joy',    'style',      'background-color: darkred;')
  ->attr_is('p.joy',    'style',      'background-color: darkred;', 'with description')
  ->attr_is('p.joy',    'data-foo',   '0')
  ->attr_is('p.joy',    'data-empty', '')
  ->attr_is('notfound', 'style',      undef)
  ->attr_isnt('p.joy', 'style', 'float: left;')
  ->attr_isnt('p.joy', 'style', 'float: left;', 'with description')
  ->attr_like('p.joy', 'style', qr/color/)
  ->attr_like('p.joy', 'style', qr/color/, 'with description')
  ->attr_unlike('p.joy', 'style', qr/^float/)
  ->attr_unlike('p.joy', 'style', qr/^float/, 'with description');

# Foo::baz (missing action without template)
$logs = $t->app->log->capture('trace');
$t->get_ok('/foo/baz')
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_unlike(qr/Something/)
  ->content_like(qr/Route without action and nothing to render/);
like $logs, qr/Action not found in controller/, 'right message';
undef $logs;

# Foo::yada (action-less template)
$t->get_ok('/foo/yada')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/look ma! no action!/);

# SyntaxError::foo (syntax error in controller)
$t->get_ok('/syntax_error/foo')
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Missing right curly/);

# Foo::syntaxerror (syntax error in template)
$logs = $t->app->log->capture('trace');
$t->get_ok('/foo/syntaxerror')
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Missing right curly/);
like $logs, qr/Rendering template "syntaxerror.html.epl"/,          'right message';
like $logs, qr/Missing right curly/,                                'right message';
like $logs, qr/Template "exception.development.html.ep" not found/, 'right message';
like $logs, qr/Rendering template "exception.html.epl"/,            'right message';
like $logs, qr/500 Internal Server Error/,                          'right message';
undef $logs;

# Exceptional::this_one_dies (action dies)
$t->get_ok('/exceptional/this_one_dies')
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("doh!\n\n");

# Exceptional::this_one_might_die (bridge dies)
$t->get_ok('/exceptional_too/this_one_dies')
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("double doh!\n\n");

# Exceptional::this_one_dies (action behind bridge dies)
$t->get_ok('/exceptional_too/this_one_dies' => {'X-DoNotDie' => 1})
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("doh!\n\n");

# Exceptional::this_one_does_not_exist (action does not exist)
$t->get_ok('/exceptional/this_one_does_not_exist')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Page Not Found/);

# Exceptional::this_one_does_not_exist (action behind bridge does not exist)
$t->get_ok('/exceptional_too/this_one_does_not_exist' => {'X-DoNotDie' => 1})
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Page Not Found/);

# Foo::fun
$t->get_ok('/fun/time' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is('X-Bender' => undef)
  ->header_is(Server     => 'Mojolicious (Perl)')
  ->content_is('<p>Have fun!</p>');

# Foo::fun
$url  = $t->ua->server->url;
$logs = $t->app->log->capture('trace');
$url->path('/fun/time');
$t->get_ok($url => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is('X-Bender' => undef)
  ->header_is(Server     => 'Mojolicious (Perl)')
  ->content_is('<p>Have fun!</p>');
like $logs, qr!Rendering cached template "foo/fun\.html\.ep" from DATA section!, 'right message';
undef $logs;

# Foo::fun
$t->get_ok('/happy/fun/time' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is('X-Bender' => undef)
  ->header_is(Server     => 'Mojolicious (Perl)')
  ->content_is('<p>Have fun!</p>');

# Foo::test
$t->get_ok('/foo/test' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is('X-Bender' => 'Bite my shiny metal ass!')
  ->header_is(Server     => 'Mojolicious (Perl)')
  ->content_like(qr!/bar/test!);

# Foo::index
$t->get_ok('/foo' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr|<body>\s+23\nHello Mojo from the template /foo! He|);

# Foo::Bar::index
$t->get_ok('/foo-bar' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr|Hello Mojo from the other template /foo-bar!|);

# Foo::something
$t->put_ok('/somethingtest' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('/test4/42');
$t->post_ok('/somethingtest?_method=PUT' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('/test4/42');
$t->get_ok('/somethingtest?_method=PUT' => {'X-Test' => 'Hi there!'})
  ->status_is(500)
  ->content_like(qr/Controller "MojoliciousTest::Somethingtest" does not exist/);

# Foo::url_for_missing
$t->get_ok('/something_missing' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('does_not_exist');

# Foo::templateless
$t->get_ok('/foo/templateless' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Hello Mojo from a templateless renderer!/);

# Foo::withlayout
$t->get_ok('/foo/withlayout' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Same old in green Seems to work!/);

# Foo::withBlock
$t->get_ok('/withblock.txt' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_type_isnt('text/html')
  ->content_type_is('text/plain;charset=UTF-8')
  ->content_like(qr/Hello Baerbel\.\s+Hello Wolfgang\./);

# MojoliciousTest2::Foo::test
$t->get_ok('/test2' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is('X-Bender' => 'Bite my shiny metal ass!')
  ->header_is(Server     => 'Mojolicious (Perl)')
  ->content_like(qr!/test2!);

# MojoliciousTestController::index
$t->get_ok('/test3' => {'X-Test' => 'Hi there!'})
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Namespace "MojoliciousTest2::Foo" requires a controller/);

# MojoliciousTest::Foo::Bar (no action)
$t->get_ok('/test1' => {'X-Test' => 'Hi there!'})
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Controller "MojoliciousTest::Controller::Foo::Bar" requires an action/);

# MojoliciousTestController::index (no namespace)
$t->get_ok('/test6' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is('X-Bender' => 'Bite my shiny metal ass!')
  ->header_is(Server     => 'Mojolicious (Perl)')
  ->content_is('/test6');

# MojoliciousTest::Foo::Bar::test (controller class shortcut)
$t->get_ok('/test7' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("Class works!\n");

# MojoliciousTest::Foo::Bar::test (controller class)
$t->get_ok('/test8' => {'X-Test' => 'Hi there!'})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("Class works!\n");

# MojoliciousTest3::Bar::index (controller class in development namespace)
$t->get_ok('/test9')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('Development namespace works!');

# MojoliciousTest3::Baz::index (controller class precedence)
$t->get_ok('/test10')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('Development namespace has high precedence!');

# 404
$t->get_ok('/' => {'X-Test' => 'Hi there!'})
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Page Not Found/);

# Static file /another/file (no extension)
$t->get_ok('/another/file')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_type_is('application/octet-stream')
  ->content_like(qr/Hello Mojolicious!/);

# Static directory /another
$logs = $t->app->log->capture('trace');
$t->get_ok('/another')->status_is(500)->header_is(Server => 'Mojolicious (Perl)');
like $logs, qr/Controller "MojoliciousTest::Another" does not exist/, 'right message';
undef $logs;

# Check Last-Modified header for static files
my $path  = curfile->sibling('public_dev', 'hello.txt');
my $size  = Mojo::Asset::File->new(path => $path)->size;
my $mtime = Mojo::Date->new(Mojo::Asset::File->new(path => $path)->mtime)->to_string;

# Static file /hello.txt
$t->get_ok('/hello.txt')
  ->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('Last-Modified' => $mtime)
  ->header_like('ETag' => qr/^"\w+"$/)
  ->header_is('Content-Length' => $size)
  ->content_type_is('text/plain;charset=UTF-8')
  ->content_like(qr/Hello Mojo from a development static file!/);

# Try to access a file which is not under the web root via path traversal
$t->get_ok('/../../mojolicious/secret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Page Not Found/);

# Try to access a file which is not under the web root via path traversal (goes
# back and forth one directory)
$t->get_ok('/another/../../../mojolicious/secret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Page Not Found/);

# Try to access a file which is not under the web root via path traversal
# (triple dot)
$t->get_ok('/.../mojolicious/secret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Page Not Found/);

# Try to access a file which is not under the web root via path traversal
# (backslashes)
$t->get_ok('/..\\..\\mojolicious\\secret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Page Not Found/);

# Try to access a file which is not under the web root via path traversal
# (escaped backslashes)
$t->get_ok('/..%5C..%5Cmojolicious%5Csecret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Page Not Found/);

# Check that backslashes in query or fragment parts don't block access
$t->get_ok('/another/file?one=\\1#two=\\2')->status_is(200)->content_like(qr/Hello Mojolicious!/);

# Check If-Modified-Since
$t->get_ok('/hello.txt' => {'If-Modified-Since' => $mtime})
  ->status_is(304)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('');

# Check If-None-Match
my $etag = $t->tx->res->headers->etag;
$t->get_ok('/hello.txt' => {'If-None-Match' => $etag})
  ->status_is(304)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('');

# Check weak If-None-Match against strong ETag
$t->get_ok('/hello.txt' => {'If-None-Match' => qq{W/"$etag"}})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Hello Mojo from a development static file!/);

# Check If-None-Match and If-Last-Modified
$t->get_ok('/hello.txt' => {'If-None-Match' => $etag, 'If-Last-Modified' => $mtime})
  ->status_is(304)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('');

# Bad If-None-Match with correct If-Modified-Since
$t->get_ok('/hello.txt' => {'If-None-Match' => '"123"', 'If-Modified-Since' => $mtime})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Hello Mojo from a development static file!/);

# Bad If-Modified-Since with correct If-None-Match
$t->get_ok('/hello.txt' => {'If-Modified-Since' => Mojo::Date->new(23), 'If-None-Match' => $etag})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Hello Mojo from a development static file!/);

# Embedded development static file
$t->get_ok('/some/static/file.txt')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("Development static file with high precedence.\n");

# Embedded development template
$t->get_ok('/just/some/template')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("Development template with high precedence.\n");

{
  # Check default development mode log level
  local $ENV{MOJO_LOG_LEVEL};
  is(Mojolicious->new->log->level, 'trace', 'right log level');

  # Check non-development mode log level
  is(Mojolicious->new->mode('test')->log->level, 'info', 'right log level');
}

# Make sure we can override attributes with constructor arguments
is(MojoliciousTest->new(mode => 'test')->mode,   'test', 'right mode');
is(MojoliciousTest->new({mode => 'test'})->mode, 'test', 'right mode');

# Persistent error
$app = MojoliciousTest->new;
my $tx = $t->ua->build_tx(GET => '/foo');
$app->handler($tx);
is $tx->res->code, 200, 'right status';
like $tx->res->body, qr|Hello Mojo from the template /foo! Hello World!|, 'right content';
$tx = $t->ua->build_tx(GET => '/foo/willdie');
$app->handler($tx);
is $tx->res->code, 500, 'right status';
like $tx->res->body, qr/Foo\.pm/, 'right content';
$tx = $t->ua->build_tx(GET => '/foo');
$app->handler($tx);
is $tx->res->code, 200, 'right status';
like $tx->res->body, qr|Hello Mojo from the template /foo! Hello World!|, 'right content';

$t = Test::Mojo->new('SingleFileTestApp');

# SingleFileTestApp::Foo::index
$t->get_ok('/foo')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Same old in green Seems to work!/);

# SingleFileTestApp (helper)
$t->get_ok('/helper')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('Welcome aboard!');

# PluginWithEmbeddedApp (lite app in plugin)
$t->get_ok('/plugin/foo')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('plugin works!');

# SingleFileTestApp::Foo::conf (config file)
$t->get_ok('/foo/conf')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('works!');

# SingleFileTestApp::Foo::data_template
$t->get_ok('/foo/data_template')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is("23 works!\n");

# SingleFileTestApp::Foo::data_template
$t->get_ok('/foo/data_template2')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("This one works too!\n");

# SingleFileTestApp::Foo::data_static
$t->get_ok('/foo/data_static')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("And this one... ALL GLORY TO THE HYPNOTOAD!\n");

# SingleFileTestApp::Foo::routes
$t->get_ok('/foo/routes')
  ->status_is(200)
  ->header_is('X-Bender' => 'Bite my shiny metal ass!')
  ->header_is(Server     => 'Mojolicious (Perl)')
  ->content_is('/foo/routes');

# SingleFileTestApp::Redispatch::handler
$t->app->log->level('trace')->unsubscribe('message');
$logs = $t->app->log->capture;
$t->get_ok('/redispatch')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('Redispatch!');
like $logs, qr/Routing to application "SingleFileTestApp::Redispatch"/, 'right message';
undef $logs;

# SingleFileTestApp::Redispatch::render
$t->get_ok('/redispatch/render')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('Render!');

# SingleFileTestApp::Redispatch::handler (targeting an existing method)
$t->get_ok('/redispatch/secret')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('Redispatch!');

# SingleFileTestApp::Redispatch::secret
$t->get_ok('/redispatch/secret?rly=1')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('Secret!');

subtest 'Override deployment plugins' => sub {
  my $t = Test::Mojo->new('SingleFileTestApp',
    {plugins => [{'MojoliciousTest::Plugin::DeploymentPlugin' => {name => 'override_helper'}}]});
  is $t->app->override_helper, 'deployment plugins work!', 'right value';
};

$t = Test::Mojo->new('MojoliciousTest');

# MojoliciousTestController::Foo::plugin_upper_case
$t->get_ok('/plugin/upper_case')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('WELCOME aboard!');

# MojoliciousTestController::Foo::plugin_camel_case
$t->get_ok('/plugin/camel_case')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('Welcome aboard!');

# MojoliciousTestController::Foo::stage2
$t->get_ok('/staged' => {'X-Pass' => 1})
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('Welcome aboard!');

# MojoliciousTestController::Foo::stage1
$t->get_ok('/staged')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('Go away!');

# MojoliciousTestController::Foo::suspended
$logs = $t->app->log->capture('trace');
$t->get_ok('/suspended')
  ->status_is(200)
  ->header_is(Server        => 'Mojolicious (Perl)')
  ->header_is('X-Suspended' => '0, 1, 1, 2')
  ->content_is('<p>Have fun!</p>');
like $logs, qr!GET "/suspended"!,                                                    'right message';
like $logs, qr/Routing to controller "MojoliciousTest::Foo" and action "suspended"/, 'right message';
like $logs, qr/Routing to controller "MojoliciousTest::Foo" and action "fun"/,       'right message';
like $logs, qr!Rendering template "foo/fun.html.ep" from DATA section!,              'right message';
like $logs, qr/200 OK/,                                                              'right message';
undef $logs;

# MojoliciousTest::Foo::longpoll
my $stash;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/longpoll')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('Poll!');
Mojo::IOLoop->one_tick until $stash->{finished};
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';

# MojoliciousTest::Foo::config
$t->get_ok('/stash_config')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('123');

# Shortcuts to controller#action
$t->get_ok('/shortcut/ctrl-act')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('ctrl-act');
$t->get_ok('/shortcut/ctrl')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('ctrl');
$t->get_ok('/shortcut/act')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('act');

# Session with domain
$t->get_ok('/foo/session')
  ->status_is(200)
  ->header_like('Set-Cookie' => qr/; domain=\.example\.com/)
  ->header_like('Set-Cookie' => qr!; path=/bar!)
  ->content_is('Bender rockzzz!');

# Mixed formats
$t->get_ok('/rss.xml')
  ->status_is(200)
  ->content_type_is('application/rss+xml')
  ->content_like(qr!<\?xml version="1.0" encoding="UTF-8"\?><rss />!);

# Missing controller has no side effects
$t->get_ok('/side_effects-test/index')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('pass');
$t->get_ok('/side_effects/index')->status_is(404)->header_is(Server => 'Mojolicious (Perl)');
$t->get_ok('/side_effects/index')->status_is(404)->header_is(Server => 'Mojolicious (Perl)');
$t->get_ok('/side_effects-test/index')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('pass');

# Transaction already destroyed
eval { Mojolicious::Controller->new->finish };
like $@, qr/Transaction already destroyed/, 'right error';
eval {
  Mojolicious::Controller->new->on(finish => sub { });
};
like $@, qr/Transaction already destroyed/, 'right error';
eval { Mojolicious::Controller->new->req };
like $@, qr/Transaction already destroyed/, 'right error';
eval { Mojolicious::Controller->new->res };
like $@, qr/Transaction already destroyed/, 'right error';
eval { Mojolicious::Controller->new->send('whatever') };
like $@, qr/Transaction already destroyed/, 'right error';

# Abstract methods
eval { Mojolicious::Plugin->register };
like $@, qr/Method "register" not implemented by subclass/, 'right error';

done_testing();
