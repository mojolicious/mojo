use Mojo::Base 'Mojolicious';

sub handler {
  my $tx = pop;
  $tx->res->code(200)->body('Hello World!');
  $tx->resume;
}

# Fast "Hello World" application for profiling the HTTP stack
__PACKAGE__->new->start;
