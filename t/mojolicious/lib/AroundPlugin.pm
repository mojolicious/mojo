package AroundPlugin;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
  my ($self, $app) = @_;

  # Render return value
  $app->hook(
    around_action => sub {
      my ($next, $c, $action, $last) = @_;
      my $value = $next->();
      $c->render(text => $value) if $last && $c->stash->{return};
      return $value;
    }
  );
}

1;
