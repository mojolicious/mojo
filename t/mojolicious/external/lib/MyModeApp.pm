package MyModeApp;
use Mojo::Base 'Mojolicious';

sub startup {
  my $self = shift;

  # Load plugin
  $self->plugin('Config');
}

1;