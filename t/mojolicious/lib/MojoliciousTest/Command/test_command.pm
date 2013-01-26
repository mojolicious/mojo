package MojoliciousTest::Command::test_command;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long 'GetOptionsFromArray';

sub run {
  my ($self, @args) = @_;
  GetOptionsFromArray \@args, 'too' => \my $too;
  return $too ? 'works too!' : 'works!';
}

1;
