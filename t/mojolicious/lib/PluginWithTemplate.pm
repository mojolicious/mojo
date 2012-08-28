package PluginWithTemplate;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
  my ($self, $app) = @_;
  push @{$app->renderer->classes}, __PACKAGE__;
  $app->routes->route('/plugin_with_template')
    ->to(cb => sub { shift->render('plugin_with_template') });
}

1;
__DATA__

@@ plugin_with_template.html.ep
% layout 'plugin_with_template';
with template
