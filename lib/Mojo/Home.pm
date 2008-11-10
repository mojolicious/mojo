# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Home;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

use File::Spec;
use FindBin;
use Mojo::Script;

__PACKAGE__->attr('app_class',  chained => 1);
__PACKAGE__->attr('parts',  chained => 1, default => sub { [] });

# I'm normally not a praying man, but if you're up there,
# please save me Superman.
sub new {
    my $self = shift->SUPER::new();

    # Parse
    if (@_) { $self->parse(@_) }

    # Detect
    else {
        my $class = (caller())[0];
        $self->detect($class);
    }

    return $self;
}

sub detect {
    my ($self, $class) = @_;

    $self->app_class($class) if $class;
    $class ||= $self->app_class;

    # Environment variable
    if ($ENV{MOJO_HOME}) {
        my @parts = File::Spec->splitdir($ENV{MOJO_HOME});
        return $self->parts(\@parts);
    }

    my $name = $self->_class_to_file($class);

    # Try to find executable from lib directory
    if ($class) {
        my $file = $self->_class_to_path($class);

        if (my $entry = $INC{$file}) {
            my $path = $entry;
            $path =~ s/$file$//;
            my @home = File::Spec->splitdir($path);

            # Remove "lib" and "blib"
            pop @home while $home[-1] =~ /^b?lib$/ || $home[-1] eq '';

            # Check for executable
            return $self->parts(\@home)
              if -f File::Spec->catfile(@home, 'bin', $name)
              || -f File::Spec->catfile(@home, 'bin', 'mojo');
        }
    }

    # Try to find executable from t directory
    my $path;
    my @base = File::Spec->splitdir($FindBin::Bin);
    my @uplevel;
    for (1 .. 5) {
        push @uplevel, '..';

        # executable in bin directory
        $path = File::Spec->catfile(@base, @uplevel, 'bin', $name);
        last if -f $path;

        # "mojo" in bin directory
        $path = File::Spec->catfile(@base, @uplevel, 'bin', 'mojo');
        last if -f $path;
    }

    # Found
    if (-f $path) {
        my @parts = File::Spec->splitdir($path);
        pop @parts;
        pop @parts;
        $self->parts(\@parts);
    }

    return $self;
}

sub executable {
    my $self = shift;

    # Executable
    my $path;
    if (my $class = $self->app_class) {
        my $name = $self->_class_to_file($class);
        $path = File::Spec->catfile(@{$self->parts}, 'bin', $name);
        return $path if -f $path;
    }

    # "mojo"
    $path = File::Spec->catfile(@{$self->parts}, 'bin', 'mojo');
    return $path if -f $path;

    # No script
    return undef;
}

sub lib_dir {
    my $self = shift;

    # Directory found
    my $path = File::Spec->catdir(@{$self->parts}, 'lib');
    return $path if -d $path;

    # No lib directory
    return undef;
}

sub parse {
    my ($self, $path) = @_;
    my @parts = File::Spec->splitdir($path);
    $self->parts(\@parts);
    return $self;
}

sub rel_dir { File::Spec->catdir(@{shift->parts}, split '/', shift) }

sub rel_file { File::Spec->catfile(@{shift->parts}, split '/', shift) }

sub to_string { File::Spec->catdir(@{shift->parts}) }

sub _class_to_file { Mojo::Script->new->class_to_file($_[1]) }

sub _class_to_path { Mojo::Script->new->class_to_path($_[1]) }

1;
__END__

=head1 NAME

Mojo::Home - Detect And Access The Project Root Directory In Mojo

=head1 SYNOPSIS

    use Mojo::Home;

=head1 DESCRIPTION

L<Mojo::Home> is a container for home directories.
Functionality includes locating the home directory and portable path handling.

=head1 ATTRIBUTES

=head2 C<app_class>

    my $class = $home->app_class;
    $home     = $home->app_class('Foo::Bar');

Returns the Mojo applications class name if called without arguments.
Returns the invocant if called with arguments.

=head2 C<parts>

    my $parts = $home->parts;
    $home     = $home->parts([qw/foo bar baz/]);

Returns an arrayref containing the parts of the projects root directory if
called without arguments.
Returns the invocant if called with arguments.

=head1 METHODS

L<Mojo::Home> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $home = Mojo::Home->new;
    my $home = Mojo::Home->new('/foo/bar/baz');

Returns a new L<Mojo::Home> object, used to find the root directory of the
project.

=head2 C<detect>

    $home = $home->detect;
    $home = $home->detect('My::App');

Returns the invocant and detects the path to the root of the Mojo project.
C<$ENV{MOJO_HOME}> is used as the location if available.
Autodetection based on the class name is used as a fallback.

=head2 C<executable>

    my $path = $home->executable;

Returns the path to the Mojo executable in the C<bin> directory of your
project, it will either be named after your project, or C<mojo>.

=head2 C<lib_dir>

    my $path = $home->lib_dir;

Returns the path to the C<lib> directory of the project if it exists, or
undef otherwise.

=head2 C<parse>

    $home = $home->parse('/foo/bar');

Returns the invocant and splits the given path into C<parts>.

=head2 C<rel_dir>

    my $path = $home->rel_dir('foo/bar');

Returns an absolute directory path based on the projects root directory.
Note that the UNIX style C</> is used as separator on all platforms.

=head2 C<rel_file>

    my $path = $home->rel_file('foo/bar.html');

Returns an absolute file path based on the projects root directory.
Note that the UNIX style C</> is used as separator on all platforms.

=head2 C<to_string>

    my $string = $home->to_string;
    my $string = "$home";

Return the path to projects root directory.

=cut