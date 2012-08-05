use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojo::Base 'Mojolicious';

# "This snow is beautiful. I'm glad global warming never happened.
#  Actually, it did. But thank God nuclear winter canceled it out."
sub handler {
  my $tx = pop;
  $tx->res->code(200)->body('Hello World!');
  $tx->resume;
}

# Fast "Hello World" application for profiling the HTTP stack
__PACKAGE__->new->start;
