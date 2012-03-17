package SingleFileTestApp;
use Mojo::Base 'Mojolicious';

# "Alright, grab a shovel.
#  I'm only one skull short of a Mouseketeer reunion."
sub startup {
  my $self = shift;

  # Only log errors to STDERR
  $self->log->path(undef);
  $self->log->level('fatal');

  # Plugin
  $self->plugin('MojoliciousTest::Plugin::Test::SomePlugin2');

  # DATA classes
  push @{$self->renderer->classes}, 'SingleFileTestApp::Foo';
  push @{$self->static->classes},   'SingleFileTestApp::Foo';

  # Helper route
  $self->routes->route('/helper')->to(
    cb => sub {
      my $self = shift;
      $self->render(text => $self->some_plugin);
    }
  );

  # /*/* - the default route
  $self->routes->route('/:controller/:action')->to(action => 'index');
}

package SingleFileTestApp::Foo;
use Mojo::Base 'Mojolicious::Controller';

sub bar {
  my $self = shift;
  $self->res->headers->header('X-Bender' => 'Bite my shiny metal ass!');
  $self->render_text($self->url_for);
}

sub data_template { shift->render('index') }

sub data_template2 { shift->stash(template => 'too') }

sub data_static { shift->render_static('singlefiletestapp/foo.txt') }

sub index { shift->stash(template => 'withlayout', msg => 'works great!') }

1;
__DATA__
@@ index.html.epl
<%= 20 + 3 %> works!
@@ too.html.epl
This one works too!
@@ singlefiletestapp/foo.txt
And this one... ALL GLORY TO THE HYPNOTOAD!
