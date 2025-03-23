use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::Mojo;
use Test::More;

use Mojo::File qw(curfile);
use lib curfile->sibling('lib')->to_string;

my $t       = Test::Mojo->new('MojoliciousTest');
my $success = '';
$t->or(sub { $success .= 'one' })
  ->success(1)
  ->or(sub { $success .= 'two' })
  ->success(!1)
  ->or(sub { $success .= shift->app->mode });
is $success, 'onetesting', 'two callbacks have been executed';
ok $t->get_ok('/')->success, 'test was successful';

# SyntaxError::foo in testing mode (syntax error in controller)
$t->get_ok('/syntax_error/foo')
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Testing Missing/);

# Foo::syntaxerror in testing mode (syntax error in template)
$t->get_ok('/foo/syntaxerror')
  ->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Testing Missing/);

# Static file /hello.txt in testing mode
$t->get_ok('/hello.txt')
  ->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Hello Mojo from a static file!/);

# Foo::bar in testing mode (missing action)
$t->get_ok('/foo/baz')->status_is(500)->header_is(Server => 'Mojolicious (Perl)')->content_like(qr/Testing/);

# Try to access a file which is not under the web root via path traversal in
# testing mode
$t->get_ok('/../../mojolicious/secret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Testing not found/);

# Try to access a file which is not under the web root via path traversal in
# testing mode (goes back and forth one directory)
$t->get_ok('/another/../../../mojolicious/secret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Testing not found/);

# Try to access a file which is not under the web root via path traversal in
# testing mode (triple dot)
$t->get_ok('/.../mojolicious/secret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Testing not found/);

# Try to access a file which is not under the web root via path traversal in
# testing mode (backslashes)
$t->get_ok('/..\\..\\mojolicious\\secret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Testing not found/);

# Try to access a file which is not under the web root via path traversal in
# testing mode (escaped backslashes)
$t->get_ok('/..%5C..%5Cmojolicious%5Csecret.txt')
  ->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Testing not found/);

# Check that backslashes in query or fragment parts don't block access in
# testing mode
$t->get_ok('/hello.txt?one=\\1#two=\\2')->status_is(200)->content_like(qr/Hello Mojo from a static file!/);

done_testing();
