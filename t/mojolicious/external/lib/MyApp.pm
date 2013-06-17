package MyApp;
use Mojo::Base 'Mojolicious';

sub startup {
  my $self = shift;
  my $r    = $self->routes;

  $self->plugin('Config');

  $r->get(
    '/' => sub {
      my $self = shift;
      $self->render(text => $self->config->{works});
    }
  );

  $r->get('/test' => sub { $_->render(text => $_->config->{whatever}) });

  $r->get(
    '/secondary' => sub { $_->render(text => ++$_->session->{secondary}) });
}

1;
