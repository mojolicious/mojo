package MojoliciousTest3::Baz;
use Mojo::Base 'Mojolicious::Controller';

sub index {
  my $self = shift;
  $self->render(text => 'Development namespace works again!');
}

1;
