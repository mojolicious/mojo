use Mojo::Base -strict;

use Mojo::File qw(tempdir path);
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;


my $tmpdir = tempdir;
my $file   = $tmpdir->child("mojo.secrets");
$ENV{MOJO_SECRETS_FILE} = $file;

like app->secrets->[0], qr/^[-A-Za-z0-9_]{43}$/, 'secret was generated, and matches expected urandom_urlsafe format';
is app->secrets->[0], $file->slurp, 'secret stored at $ENV{MOJO_SECRETS_FILE} is the same as app->secrets->[0]';

done_testing();
