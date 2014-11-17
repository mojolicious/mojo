package SingleFileTestApp;
use Mojo::Base 'Mojolicious';

sub startup {
  my $self = shift;

  # Only log errors to STDERR
  $self->log->level('fatal');

  # Plugins
  $self->plugin('PluginWithEmbeddedApp');
  $self->plugin('MojoliciousTest::Plugin::Test::SomePlugin2');
  $self->plugin('Config');

  # DATA classes
  push @{$self->renderer->classes}, 'SingleFileTestApp::Foo';
  push @{$self->static->classes},   'SingleFileTestApp::Foo';

  # Helper route
  $self->routes->route('/helper')->to(
    cb => sub {
      my $c = shift;
      $c->render(text => $c->some_plugin);
    }
  );

  # The default route
  $self->routes->route('/:controller/:action')->to(action => 'index');
}

package SingleFileTestApp::Redispatch;
use Mojo::Base 'Mojo';

sub handler {
  my ($self, $c) = @_;
  return secret($c) if $c->param('rly');
  return render($c) if $c->stash('action') eq 'render';
  $c->render(text => 'Redispatch!');
}

sub render {
  my $c = shift;
  $c->render(text => 'Render!');
}

sub secret {
  my $c = shift;
  $c->render(text => 'Secret!');
}

package SingleFileTestApp::Foo;
use Mojo::Base 'Mojolicious::Controller';

sub conf {
  my $self = shift;
  $self->render(text => $self->config->{single_file});
}

sub data_template { shift->render('index') }

sub data_template2 { shift->stash(template => 'too') }

sub data_static { shift->reply->static('singlefiletestapp/foo.txt') }

sub index {
  shift->stash(template => 'WithGreenLayout', msg => 'works great!');
}

sub routes {
  my $self = shift;
  $self->res->headers->header('X-Bender' => 'Bite my shiny metal ass!');
  $self->render(text => $self->url_for);
}

1;
__DATA__
@@ index.html.epl
<%= 20 + 3 %> works!
@@ too.html.epl
This one works too!
@@ singlefiletestapp/foo.txt
And this one... ALL GLORY TO THE HYPNOTOAD!
