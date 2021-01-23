package MojoliciousTest::Plugin::DeploymentPlugin;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
  my ($self, $app, $config) = @_;
  my $name = $config->{name}    // 'deployment_helper';
  my $msg  = $config->{message} // 'deployment plugins work!';
  $app->helper($name => sub {$msg});
}

1;
