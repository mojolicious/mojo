use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'production';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::Mojo;
use Test::More;

use Mojo::File qw(curfile);
use lib curfile->sibling('lib')->to_string;

my $t = Test::Mojo->new('MojoliciousTest');

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
is $t->app,                                      $t->app->commands->app,             'applications are equal';
is $t->app->static->file('hello.txt')->slurp,    "Hello Mojo from a static file!\n", 'right content';
is $t->app->static->file('does_not_exist.html'), undef,                              'no file';
is $t->app->moniker,                             'mojolicious_test',                 'right moniker';

# Remove extra files
is $t->app->static->file('mojo/jquery/jquery.js'), undef, 'no jQuery';

# Default namespaces
is_deeply $t->app->routes->namespaces, ['MojoliciousTest::Controller', 'MojoliciousTest'], 'right namespaces';

# Plugin::Test::SomePlugin2::register (security violation)
$t->get_ok('/plugin-test-some_plugin2/register')
  ->status_isnt(404)
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Not development mode error!/);

# Plugin::Test::SomePlugin2::register (security violation again)
$t->get_ok('/plugin-test-some_plugin2/register')
  ->status_isnt(404)
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Not development mode error!/);

# SyntaxError::foo in production mode (syntax error in controller)
$t->get_ok('/syntax_error/foo')
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Not development mode error!/);

# Foo::syntaxerror in production mode (syntax error in template)
$t->get_ok('/foo/syntaxerror')
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Not development mode error!/);

# Exceptional::this_one_dies (action dies)
$t->get_ok('/exceptional/this_one_dies')
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Not development mode error!/);

# Exceptional::this_one_might_die (bridge dies)
$t->get_ok('/exceptional_too/this_one_dies')
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Not development mode error!/);

# Exceptional::this_one_might_die (action dies)
$t->get_ok('/exceptional_too/this_one_dies' => {'X-DoNotDie' => 1})
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Not development mode error!/);

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

# Static file /hello.txt in production mode
$t->get_ok('/hello.txt')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Hello Mojo from a static file!/);

# Foo::bar in production mode (missing action)
$t->get_ok('/foo/baz')
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Not development mode error!/);

# Try to access a file which is not under the web root via path traversal in
# production mode
$t->get_ok('/../../mojolicious/secret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Page Not Found/);

# Try to access a file which is not under the web root via path traversal in
# production mode (triple dot)
$t->get_ok('/.../mojolicious/secret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Page Not Found/);

# Try to access a file which is not under the web root via path traversal in
# production mode (backslashes)
$t->get_ok('/..\\..\\mojolicious\\secret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Page Not Found/);

# Try to access a file which is not under the web root via path traversal in
# production mode (escaped backslashes)
$t->get_ok('/..%5C..%5Cmojolicious%5Csecret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Page Not Found/);

# Check that backslashes in query or fragment parts don't block access in
# production mode
$t->get_ok('/hello.txt?one=\\1#two=\\2')->status_is(200)->content_like(qr/Hello Mojo from a static file!/);

# Embedded production static file
$t->get_ok('/some/static/file.txt')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("Production static file with low precedence.\n\n");

# Embedded production template
$t->get_ok('/just/some/template')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("Production template with low precedence.\n");

# MojoliciousTest3::Bar::index (controller class in development namespace)
$t->get_ok('/test9' => {'X-Test' => 'Hi there!'})
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Not development mode error!/);

# MojoliciousTest::Baz::index (controller class precedence)
$t->get_ok('/test10')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('Production namespace has low precedence!');

done_testing();
