# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Command::Test;

use strict;
use warnings;

use base 'Mojo::Command';

use Cwd;
use FindBin;
use File::Spec;
use Test::Harness;

__PACKAGE__->attr(description => <<'EOF');
Run unit tests.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 test [TESTS]
EOF

# My eyes! The goggles do nothing!
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
                    Cwd::realpath(
                        File::Spec->catfile(File::Spec->splitdir($fpath))
                    )
                  ) if (-f $fpath) && ($fpath =~ /\.t$/);
            }
            closedir $fh;
        }

        $path = Cwd::realpath($path);
        print "Running tests from '$path'.\n";
    }

    # Run tests
    runtests(@tests);

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Command::Test - Test Command

=head1 SYNOPSIS

    use Mojo::Command::Test;

    my $test = Mojo::Command::Test->new;
    $test->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Command::Test> is a test script.

=head1 ATTRIBUTES

L<Mojo::Command::Test> inherits all attributes from L<Mojo::Command> and
implements the following new ones.

=head2 C<description>

    my $description = $test->description;
    $test           = $test->description('Foo!');

=head2 C<usage>

    my $usage = $test->usage;
    $test     = $test->usage('Foo!');

=head1 METHODS

L<Mojo::Command::Test> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

    $test = $test->run(@ARGV);

=cut
