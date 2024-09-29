use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_HOME} = "t/mojolicious/";
}

use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

is app->secrets->[0], 'NeverGonnaGiveYouUpNeverGonnaLetYouDown', 'secret is loaded from home';

done_testing();
