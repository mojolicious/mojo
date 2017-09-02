package MojoliciousLoaderTest;
use Mojo::Base 'Mojolicious';

sub startup {
  my $self = shift;

  # Template and static file class with lower precedence for production
  $self->renderer->paths([$self->home->child('templates-loadertest')]);

  my $r = $self->routes;
  $r->get('/foo')->to(controller => 'Foo', action => 'index');
  $r->get('/bar')->to(controller => 'Foo::Bar', action => 'index');
}

1;
