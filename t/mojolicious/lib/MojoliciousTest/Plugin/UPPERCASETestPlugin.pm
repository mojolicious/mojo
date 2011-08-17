package MojoliciousTest::Plugin::UPPERCASETestPlugin;
use Mojo::Base 'Mojolicious::Plugin';

# "I hate these nerds. Just because I'm stupider than them
# they think they're smarter than me."
sub register {
  my ($self, $app) = @_;

  # Add "test_plugin" helper
  $app->helper(uppercase_test_plugin => sub {'WELCOME aboard!'});
}

1;
