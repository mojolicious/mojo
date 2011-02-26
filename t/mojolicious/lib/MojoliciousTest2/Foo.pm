package MojoliciousTest2::Foo;
use Mojo::Base 'Mojolicious::Controller';

# "I can't afford to keep running people over.
#  I'm not famous enough to get away with it."
sub test {
  my $self = shift;
  $self->res->headers->header('X-Bender' => 'Bite my shiny metal ass!');
  $self->render(text => $self->url_for);
}

1;
