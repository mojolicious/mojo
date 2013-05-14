package MojoliciousTestController;
use Mojo::Base 'Mojolicious::Controller';

sub index {
  my $self = shift;
  $self->res->headers->header('X-Bender' => 'Bite my shiny metal ass!');
  $self->render(text => "No class works!");
}

1;
