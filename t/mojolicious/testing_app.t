use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER}  = 'Mojo::IOWatcher';
  $ENV{MOJO_MODE}       = 'testing';
}

use Test::More tests => 25;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::Mojo;

# "Anything less than immortality is a complete waste of time!"
my $t = Test::Mojo->new('MojoliciousTest');

# SyntaxError::foo in testing mode (syntax error in controller)
$t->get_ok('/syntax_error/foo')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Testing Missing/);

# Foo::syntaxerror in testing mode (syntax error in template)
$t->get_ok('/foo/syntaxerror')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Testing Missing/);

# Static file /hello.txt in testing mode
$t->get_ok('/hello.txt')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Hello Mojo from a static file!/);

# Foo::bar in testing mode (missing action)
$t->get_ok('/foo/baz')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Testing not found/);

# Try to access a file which is not under the web root via path
# traversal in testing mode
$t->get_ok('/../../mojolicious/secret.txt')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Testing not found/);
