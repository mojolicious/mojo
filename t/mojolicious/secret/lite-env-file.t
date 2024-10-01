use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_SECRETS_FILE} = "t/mojolicious/secret/custom.secrets";
}

use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

is_deeply(
  app->secrets,
  ['NeverGonnaMakeYouCryNeverGonnaSayGoodbye', 'NeverGonnaTellALieAndHurtYou'],
  'only valid secrets are loaded from $ENV{MOJO_SECRETS_FILE}'
);

done_testing();
