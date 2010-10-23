package Mojo::Home;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

use File::Spec;
use FindBin;
use Mojo::Command;
use Mojo::Loader;

__PACKAGE__->attr(app_class => 'Mojo::HelloWorld');

# I'm normally not a praying man, but if you're up there,
# please save me Superman.
sub detect {
    my ($self, $class) = @_;

    # Class
    $self->app_class($class) if $class;
    $class ||= $self->app_class;

    # Environment variable
    if ($ENV{MOJO_HOME}) {
        my @parts = File::Spec->splitdir($ENV{MOJO_HOME});
        $self->{_parts} = \@parts;
        return $self;
    }

    # Try to find home from lib directory
    if ($class) {

        # Load
        my $file = Mojo::Command->class_to_path($class);
        unless ($INC{$file}) {
            if (my $e = Mojo::Loader->load($class)) { die $e if ref $e }
        }

        # Detect
        if (my $path = $INC{$file}) {

            $path =~ s/$file$//;
            my @home = File::Spec->splitdir($path);

            # Remove "lib" and "blib"
            while (@home) {
                last unless $home[-1] =~ /^b?lib$/ || $home[-1] eq '';
                pop @home;
            }

            $self->{_parts} = \@home;
        }
    }

    # FindBin fallback
    $self->{_parts} = [split /\//, $FindBin::Bin] unless $self->{_parts};

    return $self;
}

sub lib_dir {
    my $self = shift;

    # Directory found
    my $parts = $self->{_parts} || [];
    my $path = File::Spec->catdir(@$parts, 'lib');
    return $path if -d $path;

    # No lib directory
    return;
}

sub list_files {
    my ($self, $dir) = @_;

    # Parts
    my $parts = $self->{_parts} || [];

    # Root
    my $root = File::Spec->catdir(@$parts);

    # Directory
    $dir = File::Spec->catdir($root, split '/', ($dir || ''));

    # Read directory
    my (@files, @dirs);
    opendir DIR, $dir or return [];
    for my $file (readdir DIR) {

        # Hidden file
        next if $file =~ /^\./;

        # File
        my $path = File::Spec->catfile($dir, $file);
        my $rel = File::Spec->abs2rel($path, $root);
        if (-f $path) {
            push @files, join '/', File::Spec->splitdir($rel);
        }

        # Directory
        elsif (-d $path) { push @dirs, join('/', File::Spec->splitdir($rel)) }
    }
    closedir DIR;

    # Walk directories
    for my $path (@dirs) {
        my $new = $self->list_files($path);
        push @files, @$new;
    }

    return [sort @files];
}

# And now to create an unstoppable army of between one million and two
# million zombies!
sub parse {
    my ($self, $path) = @_;
    my @parts = File::Spec->splitdir($path);
    $self->{_parts} = \@parts;
    return $self;
}

sub rel_dir {
    my $self = shift;
    my $parts = $self->{_parts} || [];
    return File::Spec->catdir(@$parts, split '/', shift);
}

sub rel_file {
    my $self = shift;
    my $parts = $self->{_parts} || [];
    return File::Spec->catfile(@$parts, split '/', shift);
}

sub to_string {
    my $self = shift;
    my $parts = $self->{_parts} || [];
    return File::Spec->catdir(@$parts);
}

1;
__END__

=head1 NAME

Mojo::Home - Detect And Access The Project Root Directory In Mojo

=head1 SYNOPSIS

    use Mojo::Home;

    my $home = Mojo::Home->new;
    $home->detect;

=head1 DESCRIPTION

L<Mojo::Home> is a container for home directories.

=head1 ATTRIBUTES

L<Mojo::Home> implements the following attributes.

=head2 C<app_class>

    my $class = $home->app_class;
    $home     = $home->app_class('Foo::Bar');

Application class.

=head1 METHODS

L<Mojo::Home> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<detect>

    $home = $home->detect;
    $home = $home->detect('My::App');

Detect home directory from application class.

=head2 C<lib_dir>

    my $path = $home->lib_dir;

Path to C<lib> directory.

=head2 C<list_files>

    my $files = $home->list_files;
    my $files = $home->list_files('foo/bar');

List all files in directory and subdirectories recursively.

=head2 C<parse>

    $home = $home->parse('/foo/bar');

Parse path.

=head2 C<rel_dir>

    my $path = $home->rel_dir('foo/bar');

Generate absolute path for relative directory.

=head2 C<rel_file>

    my $path = $home->rel_file('foo/bar.html');

Generate absolute path for relative file.

=head2 C<to_string>

    my $string = $home->to_string;
    my $string = "$home";

Home directory.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
