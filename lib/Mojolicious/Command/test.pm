package Mojolicious::Command::test;
use Mojo::Base 'Mojolicious::Command';

use Cwd 'realpath';
use FindBin;
use File::Spec::Functions qw(abs2rel catdir splitdir);
use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use Mojo::Home;

has description => "Run unit tests.\n";
has usage       => <<"EOF";
usage: $0 test [OPTIONS] [TESTS]

These options are available:
  -v, --verbose   Print verbose debug information to STDERR.
EOF

sub run {
  my ($self, @args) = @_;

  GetOptionsFromArray \@args, 'v|verbose' => sub { $ENV{HARNESS_VERBOSE} = 1 };

  unless (@args) {
    my @base = splitdir(abs2rel $FindBin::Bin);

    # "./t"
    my $path = catdir @base, 't';

    # "../t"
    $path = catdir @base, '..', 't' unless -d $path;
    die "Can't find test directory.\n" unless -d $path;

    my $home = Mojo::Home->new($path);
    /\.t$/ and push @args, $home->rel_file($_) for @{$home->list_files};
    say "Running tests from '", realpath($path), "'.";
  }

  $ENV{HARNESS_OPTIONS} //= 'c';
  require Test::Harness;
  Test::Harness::runtests(sort @args);
}

1;

=head1 NAME

Mojolicious::Command::test - Test command

=head1 SYNOPSIS

  use Mojolicious::Command::test;

  my $test = Mojolicious::Command::test->new;
  $test->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::test> runs application tests from the C<t> directory.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

=head1 ATTRIBUTES

L<Mojolicious::Command::test> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $test->description;
  $test           = $test->description('Foo!');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $test->usage;
  $test     = $test->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::test> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $test->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
