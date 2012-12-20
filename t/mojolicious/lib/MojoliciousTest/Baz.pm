package MojoliciousTest::Baz;
use Mojo::Base 'Mojolicious::Controller';

sub index {
  my $self = shift;
  $self->render(text => 'Production namespace works again!');
}

1;
