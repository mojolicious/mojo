package MojoliciousTest3::Bar;
use Mojo::Base 'Mojolicious::Controller';

sub index {
  my $self = shift;
  $self->render(text => 'Development namespace works!');
}

1;
