package Mojo::HelloWorld;
use Mojolicious::Lite;

app->log->level('error')->path(undef);

any '/*whatever' => {whatever => '', text => 'Your Mojo is working!'};

1;

=head1 NAME

Mojo::HelloWorld - Hello World!

=head1 SYNOPSIS

  use Mojo::HelloWorld;

  my $hello = Mojo::HelloWorld->new;
  $hello->start;

=head1 DESCRIPTION

L<Mojo::HelloWorld> is the default L<Mojolicious> application, used mostly
for testing.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
