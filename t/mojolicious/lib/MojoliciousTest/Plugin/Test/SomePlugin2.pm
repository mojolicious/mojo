package MojoliciousTest::Plugin::Test::SomePlugin2;
use Mojo::Base 'Mojolicious::Plugin';

# "Space: It seems to go on and on forever...
#  but then you get to the end and a gorilla starts throwing barrels at you."
sub register {
  my ($self, $app) = @_;

  # Add "some_plugin" helper
  $app->helper(some_plugin => sub {'Welcome aboard!'});
}

1;
