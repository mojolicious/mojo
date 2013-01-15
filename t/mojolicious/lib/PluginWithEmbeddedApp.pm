package PluginWithEmbeddedApp;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
  my ($self, $app) = @_;
  $app->routes->route('/plugin')->detour(PluginWithEmbeddedApp::App::app());
}

package PluginWithEmbeddedApp::App;
use Mojolicious::Lite;

get '/foo';

1;
__DATA__
@@ foo.html.ep
plugin works!\
