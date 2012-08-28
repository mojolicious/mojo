package MojoliciousTest::Plugin::UPPERCASETestPlugin;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
  my ($self, $app) = @_;

  # Add "upper_case_test_plugin" helper
  $app->helper(upper_case_test_plugin => sub {'WELCOME aboard!'});
}

1;
