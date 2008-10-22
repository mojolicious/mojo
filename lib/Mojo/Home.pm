# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Home;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

use File::Spec;
use FindBin;
use Mojo::Script;

__PACKAGE__->attr('application_class',  chained => 1);
__PACKAGE__->attr('parts',  chained => 1, default => sub { [] });

*app_class = \&application_class;
*lib_dir   = \&lib_directory;
*rel_dir   = \&relative_directory;
*rel_file  = \&relative_file;

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

    $self->application_class($class) if $class;
    $class ||= $self->application_class;

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
            return $self->parts(@home)
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
    if (my $class = $self->application_class) {
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

sub lib_directory {
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

sub relative_directory {
    File::Spec->catdir(@{shift->parts}, split '/', shift);
}

sub relative_file { File::Spec->catfile(@{shift->parts}, split '/', shift) }

sub to_string { File::Spec->catdir(@{shift->parts}) }

sub _class_to_file { Mojo::Script->new->class_to_file($_[1]) }

sub _class_to_path { Mojo::Script->new->class_to_path($_[1]) }

1;
__END__

=head1 NAME

Mojo::Home - Home Sweet Home!

=head1 SYNOPSIS

    use Mojo::Home;

=head1 DESCRIPTION

L<Mojo::Home> is a container for home directories.

=head1 ATTRIBUTES

=head2 C<app_class>

=head2 C<application_class>

    my $class = $home->app_class;
    my $class = $home->application_class;
    $home     = $home->app_class('Foo::Bar');
    $home     = $home->application_class('Foo::Bar');

=head2 C<parts>

    my $parts = $home->parts;
    $home     = $home->parts([qw/foo bar baz/]);

=head1 METHODS

L<Mojo::Home> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $home = Mojo::Home->new;
    my $home = Mojo::Home->new('/foo/bar/baz');

=head2 C<detect>

    $home = $home->detect;
    $home = $home->detect('My::App');

=head2 C<executable>

    my $path = $home->executable;

=head2 C<lib_dir>

=head2 C<lib_directory>

    my $path = $home->lib_dir;
    my $path = $home->lib_directory;

=head2 C<parse>

    $home = $home->parse('/foo/bar');

=head2 C<rel_dir>

=head2 C<relative_directory>

    my $path = $home->rel_dir('foo/bar');
    my $path = $home->relative_directory('foo/bar');

=head2 C<rel_file>

=head2 C<relative_file>

    my $path = $home->rel_file('foo/bar.html');
    my $path = $home->relative_file('foo/bar.html');

=head2 C<to_string>

    my $string = $home->to_string;
    my $string = "$home";

=cut