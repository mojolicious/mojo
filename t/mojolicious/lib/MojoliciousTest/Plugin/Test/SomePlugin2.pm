package MojoliciousTest::Plugin::Test::SomePlugin2;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
  my ($self, $app) = @_;

  # Add "some_plugin" helper
  $app->helper(some_plugin => sub {'Welcome aboard!'});
}

1;
