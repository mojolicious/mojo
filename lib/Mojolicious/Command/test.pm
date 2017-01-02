package Mojolicious::Command::test;
use Mojo::Base 'Mojolicious::Command';

use Mojo::Util 'getopt';

has description => 'Run tests';
has usage => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;

  getopt \@args, 'v|verbose' => \$ENV{HARNESS_VERBOSE};

  if (!@args && (my $tests = $self->app->home->child('t'))) {
    die "Can't find test directory.\n" unless -d $tests;
    @args = $tests->list_tree->grep(qr/\.t$/)->map('to_string')->each;
    say qq{Running tests from "$tests".};
  }

  $ENV{HARNESS_OPTIONS} //= 'c';
  require Test::Harness;
  local $Test::Harness::switches = '';
  Test::Harness::runtests(sort @args);
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::test - Test command

=head1 SYNOPSIS

  Usage: APPLICATION test [OPTIONS] [TESTS]

    ./myapp.pl test
    ./myapp.pl test t/foo.t
    ./myapp.pl test -v t/foo/*.t

  Options:
    -h, --help      Show this summary of available options
    -v, --verbose   Print verbose debug information to STDERR

=head1 DESCRIPTION

L<Mojolicious::Command::test> runs application tests from the C<t> directory.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are
available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::test> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $test->description;
  $test           = $test->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $test->usage;
  $test     = $test->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::test> inherits all methods from L<Mojolicious::Command>
and implements the following new ones.

=head2 run

  $test->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
