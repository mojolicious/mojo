# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Script;

use strict;
use warnings;

use base 'Mojo::Base';

require Carp;
require Cwd;
require File::Path;
require File::Spec;
require IO::File;

use Mojo::ByteStream;
use Mojo::Template;

__PACKAGE__->attr('description',
    chained => 1,
    default => sub { 'No description.' }
);
__PACKAGE__->attr('quiet', chained => 1, default => sub { 0 });
__PACKAGE__->attr('renderer',
    chained => 1,
    default => sub { Mojo::Template->new }
);

*chmod_rel_file     = \&chmod_relative_file;
*create_dir         = \&create_directory;
*create_rel_dir     = \&create_relative_directory;
*rel_dir            = \&relative_directory;
*rel_file           = \&relative_file;
*render_to_rel_file = \&render_to_relative_file;
*write_rel_file     = \&write_relative_file;

sub chmod_file {
    my ($self, $path, $mod) = @_;

    # chmod
    chmod $mod, $path or die qq/Can't chmod path "$path": $!/;

    $mod = sprintf '%lo', $mod;
    print "  [chmod] $path $mod\n" unless $self->quiet;
    return $self;
}

sub chmod_relative_file {
    my ($self, $path, $mod) = @_;

    # Path
    $path = $self->relative_file($path);

    # chmod
    $self->chmod_file($path, $mod);
}

sub class_to_file {
    my ($self, $class) = @_;

    # Class to file
    $class =~ s/:://g;
    $class = Mojo::ByteStream->new($class)->decamelize->to_string;

    return $class;
}

sub class_to_path {
    my ($self, $class) = @_;

    # Class to path
    my $path = join '/', split /::/, $class;

    return "$path.pm";
}

sub create_directory {
    my ($self, $path) = @_;

    # Exists
    if (-d $path) {
        print "  [exist] $path\n" unless $self->quiet;
        return $self;
    }

    # Make
    File::Path::mkpath($path) or die qq/Can't make directory "$path": $!/;
    print "  [mkdir] $path\n" unless $self->quiet;
    return $self;
}

sub create_relative_directory {
    my ($self, $path) = @_;

    # Path
    $path = $self->relative_directory($path);

    # Create
    $self->create_directory($path);
}

sub get_data {
    my ($self, $data, $class) = @_;
    $class ||= ref $self;

    # Cache
    my $sections = $self->{data};

    # Slurp
    $sections = do {
        local $/;
        eval "package $class; <DATA>";
    } unless $sections;

    $self->{data} ||= $sections;

    # Split
    my @data = split /^__(.+)__\r?\n/m, $sections;

    # Remove split garbage
    shift @data;

    # Find data
    while (@data) {
        my ($name, $content) = splice @data, 0, 2;
        return $content if $name eq $data;
    }

    return undef;
}

sub relative_directory {
    my ($self, $path) = @_;

    # Parts
    my @parts = split /\//, $path;

    # Render
    return File::Spec->catdir(Cwd::getcwd(), @parts);
}

sub relative_file {
    my ($self, $path) = @_;

    # Parts
    my @parts = split /\//, $path;

    # Render
    return File::Spec->catfile(Cwd::getcwd(), @parts);
}

sub render_data {
    my $self = shift;
    my $data = shift;

    # Get data
    my $template = $self->get_data($data);

    # Render
    return $self->renderer->render($template, @_);
}

sub render_to_file {
    my $self = shift;
    my $data = shift;
    my $path = shift;

    # Render
    my $content = $self->render_data($data, @_);

    # Write
    $self->write_file($path, $content);

    return $self;
}

sub render_to_relative_file {
    my $self = shift;
    my $data = shift;
    my $path = shift;

    # Path
    $path = $self->relative_directory($path);

    # Render
    $self->render_to_file($data, $path, @_);
}

# My cat's breath smells like cat food.
sub run { Carp::croak('Method "run" not implemented by subclass') }

sub write_file {
    my ($self, $path, $data) = @_;

    # Directory
    my @parts = File::Spec->splitdir($path);
    pop @parts;
    my $dir = File::Spec->catdir(@parts);
    $self->create_directory($dir);

    # Open file
    my $file = IO::File->new;
    $file->open(">$path") or die qq/Can't open file "$path": $!/;

    # Write unbuffered
    $file->syswrite($data);

    print "  [write] $path\n" unless $self->quiet;
    return $self;
}

sub write_relative_file {
    my ($self, $path, $data) = @_;

    # Path
    $path = $self->relative_file($path);

    # Write
    $self->write_file($path, $data);
}

1;
__END__

=head1 NAME

Mojo::Script - Script Base Class

=head1 SYNOPSIS

    use base 'Mojo::Script';

    sub run {
        my $self = shift;
        $self->render_to_relative_file('foo_bar', 'foo/bar.txt');
    }

    1;
    __DATA__
    __foo_bar__
    % for (1 .. 5) {
        Hello World!
    % }

=head1 DESCRIPTION

L<Mojo::Script> is a base class for scripts.

=head1 ATTRIBUTES

=head2 C<description>

    my $description = $script->description;
    $script         = $script->description('Foo!');

=head2 C<quiet>

    my $quiet = $script->quiet;
    $script   = $script->quiet(1);

=head1 METHODS

L<Mojo::Script> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<chmod_file>

    $script = $script->chmod_file('/foo/bar.txt', 0644);

=head2 C<chmod_rel_file>

=head2 C<chmod_relative_file>

    $script = $script->chmod_rel_file('foo/bar.txt', 0644);
    $script = $script->chmod_relative_file('foo/bar.txt', 0644);

=head2 C<class_to_file>

    my $file = $script->class_to_file('Foo::Bar');

=head2 C<class_to_path>

    my $path = $script->class_to_path('Foo::Bar');

=head2 C<create_dir>

=head2 C<create_directory>

    $script = $script->create_dir('/foo/bar/baz');
    $script = $script->create_direcory('/foo/bar/baz');

=head2 C<create_rel_dir>

=head2 C<create_relative_directory>

    $script = $script->create_rel_dir('foo/bar/baz');
    $script = $script->create_relative_direcory('foo/bar/baz');

=head2 C<get_data>

    my $data = $script->get_data('foo_bar');

=head2 C<rel_dir>

=head2 C<relative_directory>

    my $path = $script->rel_dir('foo/bar');
    my $path = $script->relative_directory('foo/bar');

=head2 C<rel_file>

=head2 C<relative_file>

    my $path = $script->rel_file('foo/bar.txt');
    my $path = $script->relative_file('foo/bar.txt');

=head2 C<render_data>

    my $data = $script->render_data('foo_bar', @arguments);

=head2 C<render_to_file>

    $script = $script->render_to_file('foo_bar', '/foo/bar.txt');

=head2 C<render_to_rel_file>

=head2 C<render_to_relative_file>

    $script = $script->render_to_rel_file('foo_bar', 'foo/bar.txt');
    $script = $script->render_to_relative_file('foo_bar', 'foo/bar.txt');

=head2 C<run>

    $script = $script->run(@ARGV);

=head2 C<write_file>

    $script = $script->write_file('/foo/bar.txt', 'Hello World!');

=head2 C<write_rel_file>

=head2 C<write_relative_file>

    $script = $script->write_rel_file('foo/bar.txt', 'Hello World!');
    $script = $script->write_relative_file('foo/bar.txt', 'Hello World!');

=cut