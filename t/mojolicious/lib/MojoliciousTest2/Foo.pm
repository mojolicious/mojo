package MojoliciousTest2::Foo;
use Mojo::Base 'Mojolicious::Controller';

sub test {
  my $self = shift;
  $self->res->headers->header('X-Bender' => 'Bite my shiny metal ass!');
  $self->render(text => $self->url_for);
}

1;
