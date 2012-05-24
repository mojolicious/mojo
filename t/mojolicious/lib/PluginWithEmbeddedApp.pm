package PluginWithEmbeddedApp;
use Mojo::Base 'Mojolicious::Plugin';

# "I heard you went off and became a rich doctor.
#  I've performed a few mercy killings."
sub register {
  my ($self, $app) = @_;
  $app->routes->route('/plugin')->detour(PluginWithEmbeddedApp::App::app());
}

package PluginWithEmbeddedApp::App;
use Mojolicious::Lite;

# GET /foo
get '/foo';

1;
__DATA__
@@ foo.html.ep
plugin works!\
