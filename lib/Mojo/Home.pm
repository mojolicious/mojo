# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Home;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

use File::Spec;
use Mojo::Loader;
use Mojo::Script;

__PACKAGE__->attr('app_class', default => 'Mojo::HelloWorld');
__PACKAGE__->attr('parts', default => sub { [] });

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

    # Class
    $self->app_class($class) if $class;
    $class ||= $self->app_class;

    # Environment variable
    if ($ENV{MOJO_HOME}) {
        my @parts = File::Spec->splitdir($ENV{MOJO_HOME});
        $self->parts(\@parts);
        return $self;
    }

    # Try to find home from lib directory
    if ($class) {

        # Load?
        my $file = Mojo::Script->class_to_path($class);
        unless ($INC{$file}) {
            if (my $e = Mojo::Loader->load($class)) { die $e if ref $e }
        }

        # Detect
        my $path = $INC{$file};
        return $self unless $path;

        $path =~ s/$file$//;
        my @home = File::Spec->splitdir($path);

        # Remove "lib" and "blib"
        while (@home) {
            last unless $home[-1] =~ /^b?lib$/ || $home[-1] eq '';
            pop @home;
        }

        $self->parts(\@home);
    }

    return $self;
}

sub lib_dir {
    my $self = shift;

    # Directory found
    my $path = File::Spec->catdir(@{$self->parts}, 'lib');
    return $path if -d $path;

    # No lib directory
    return;
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

1;
__END__

=head1 NAME

Mojo::Home - Detect And Access The Project Root Directory In Mojo

=head1 SYNOPSIS

    use Mojo::Home;

=head1 DESCRIPTION

L<Mojo::Home> is a container for home directories.

=head1 ATTRIBUTES

L<Mojo::Home> implements the following attributes.

=head2 C<app_class>

    my $class = $home->app_class;
    $home     = $home->app_class('Foo::Bar');

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

=head2 C<lib_dir>

    my $path = $home->lib_dir;

=head2 C<parse>

    $home = $home->parse('/foo/bar');

=head2 C<rel_dir>

    my $path = $home->rel_dir('foo/bar');

=head2 C<rel_file>

    my $path = $home->rel_file('foo/bar.html');

=head2 C<to_string>

    my $string = $home->to_string;
    my $string = "$home";

=cut
