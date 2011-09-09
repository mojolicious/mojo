package Mojolicious::Command::test;
use Mojo::Base 'Mojo::Command';

use Cwd;
use FindBin;
use File::Spec;
use Test::Harness;

has description => <<'EOF';
Run unit tests.
EOF
has usage => <<"EOF";
usage: $0 test [TESTS]
EOF

# "Why, the secret ingredient was...water!
#  Yes, ordinary water, laced with nothing more than a few spoonfuls of LSD."
sub run {
  my ($self, @tests) = @_;

  # Search tests
  unless (@tests) {
    my @base = File::Spec->splitdir(File::Spec->abs2rel($FindBin::Bin));

    # Test directory in the same directory as "mojo" (t)
    my $path = File::Spec->catdir(@base, 't');

    # Test dirctory in the directory above "mojo" (../t)
    $path = File::Spec->catdir(@base, '..', 't') unless -d $path;
    unless (-d $path) {
      print "Can't find test directory.\n";
      return;
    }

    # List test files
    my @dirs = ($path);
    while (my $dir = shift @dirs) {
      opendir(my $fh, $dir);
      for my $file (readdir($fh)) {
        next if $file eq '.';
        next if $file eq '..';
        my $fpath = File::Spec->catfile($dir, $file);
        push @dirs, File::Spec->catdir($dir, $file) if -d $fpath;
        push @tests,
          File::Spec->abs2rel(
          Cwd::realpath(File::Spec->catfile(File::Spec->splitdir($fpath))))
          if (-f $fpath) && ($fpath =~ /\.t$/);
      }
      closedir $fh;
    }

    $path = Cwd::realpath($path);
    print "Running tests from '$path'.\n";
  }

  # Run tests
  runtests(sort @tests);
}

1;
__END__

=head1 NAME

Mojolicious::Command::test - Test Command

=head1 SYNOPSIS

  use Mojolicious::Command::test;

  my $test = Mojolicious::Command::test->new;
  $test->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::test> is a test script.

=head1 ATTRIBUTES

L<Mojolicious::Command::test> inherits all attributes from L<Mojo::Command>
and implements the following new ones.

=head2 C<description>

  my $description = $test->description;
  $test           = $test->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $test->usage;
  $test     = $test->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::test> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

  $test->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
