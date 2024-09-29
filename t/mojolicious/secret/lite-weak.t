use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_SECRETS_FILE} = "t/mojolicious/secret/weak.secrets";
}

use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

eval { app->secrets; };
like $@, qr/does not contain any acceptable secret/;

done_testing();
