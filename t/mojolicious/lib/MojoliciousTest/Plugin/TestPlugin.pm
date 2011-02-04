package MojoliciousTest::Plugin::TestPlugin;
use Mojo::Base 'Mojolicious::Plugin';

# "Space: It seems to go on and on forever...
#  but then you get to the end and a gorilla starts throwing barrels at you."
sub register {
  my ($self, $app) = @_;

  # Add "test_plugin" helper
  $app->helper(test_plugin => sub {'Welcome aboard!'});
}

1;
