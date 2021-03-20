package Mojo::HelloWorld;
use Mojo::Base 'Mojolicious';

sub startup {
  my $self = shift;
  $self->preload_namespaces([])->log->level('error')->path(undef);
  $self->routes->any('/*whatever' => {whatever => '', text => 'Your Mojo is working!'});
}

1;

=encoding utf8

=head1 NAME

Mojo::HelloWorld - Hello World!

=head1 SYNOPSIS

  use Mojo::HelloWorld;

  my $hello = Mojo::HelloWorld->new;
  $hello->start;

=head1 DESCRIPTION

L<Mojo::HelloWorld> is the default L<Mojolicious> application, used mostly for testing.

=head1 ATTRIBUTES

L<Mojo::HelloWorld> inherits all attributes from L<Mojolicious>.

=head1 METHODS

L<Mojo::HelloWorld> inherits all methods from L<Mojolicious> and implements the following new ones.

=head2 startup

  $hello->startup;

Creates a catch-all route that renders a text message.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
