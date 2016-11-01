package MojoliciousTest::Command::test_command;
use Mojo::Base 'Mojolicious::Command';

use Mojo::Util 'getopt';

sub run {
  my ($self, @args) = @_;
  getopt \@args, ['default'], 'too' => \my $too;
  return $too ? 'works too!' : 'works!';
}

1;
