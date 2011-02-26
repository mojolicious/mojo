package MojoliciousTestController;
use Mojo::Base 'Mojolicious::Controller';

# "My folks were always on me to groom myself and wear underpants.
#  What am I, the pope?"
sub index {
  my $self = shift;
  $self->res->headers->header('X-Bender' => 'Bite my shiny metal ass!');
  $self->render_text("No class works!");
}

1;
