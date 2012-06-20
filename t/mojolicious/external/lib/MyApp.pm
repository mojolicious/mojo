package MyApp;
use Mojo::Base 'Mojolicious';

# "Well, at least here you'll be treated with dignity.
#  Now strip naked and get on the probulator."
sub startup {
  my $self = shift;
  my $r    = $self->routes;

  # Load plugin
  $self->plugin('Config');

  # GET /
  $r->get(
    '/' => sub {
      my $self = shift;
      $self->render(text => $self->config->{works});
    }
  );

  # GET /test
  $r->get(
    '/test' => sub {
      my $self = shift;
      $self->render(text => $self->config->{whatever});
    }
  );

  # GET /secondary
  $r->get(
    '/secondary' => sub {
      my $self = shift;
      $self->render(text => ++$self->session->{secondary});
    }
  );
}

1;
