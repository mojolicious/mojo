use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::Mojo;

my $t    = Test::Mojo->new('MojoliciousTest');
my $mode = '';
$t->or(sub { $mode .= $t->app->mode })->or(sub { $mode .= shift->app->mode });
is $mode, 'testingtesting', 'both callbacks have been invoked';

# SyntaxError::foo in testing mode (syntax error in controller)
$t->get_ok('/syntax_error/foo')->status_is(500)
  ->or(sub { $mode .= $t->app->mode })
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Testing Missing/);
is $mode, 'testingtesting', 'callback has not been invoked';

# Foo::syntaxerror in testing mode (syntax error in template)
$t->get_ok('/foo/syntaxerror')->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Testing Missing/);

# Static file /hello.txt in testing mode
$t->get_ok('/hello.txt')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Hello Mojo from a static file!/);

# Foo::bar in testing mode (missing action)
$t->get_ok('/foo/baz')->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Testing not found/);

# Try to access a file which is not under the web root via path
# traversal in testing mode
$t->get_ok('/../../mojolicious/secret.txt')->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Testing not found/);

done_testing();
