package PluginWithTemplate;
use Mojo::Base 'Mojolicious::Plugin';

# "Good news, everyone! I've taught the toaster to feel love!"
sub register {
  my ($self, $app) = @_;
  $app->routes->route('/plugin_with_template')->to(
    cb => sub {
      shift->render('template', template_class => __PACKAGE__);
    }
  );
}

1;
__DATA__

@@ template.html.ep
% layout plugin_with_template => (template_class => 'main');
with template
