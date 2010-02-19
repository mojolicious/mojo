# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Command;

use strict;
use warnings;

use base 'Mojo::Base';

require Cwd;
require File::Path;
require File::Spec;
require IO::File;

use Carp 'croak';
use Mojo::ByteStream 'b';
use Mojo::Template;

__PACKAGE__->attr(description => 'No description.');
__PACKAGE__->attr(quiet       => 0);
__PACKAGE__->attr(renderer    => sub { Mojo::Template->new });
__PACKAGE__->attr(usage       => "usage: $0\n");

sub chmod_file {
    my ($self, $path, $mod) = @_;

    # chmod
    chmod $mod, $path or croak qq/Can't chmod path "$path": $!/;

    $mod = sprintf '%lo', $mod;
    print "  [chmod] $path $mod\n" unless $self->quiet;
    return $self;
}

sub chmod_rel_file {
    my ($self, $path, $mod) = @_;

    # Path
    $path = $self->rel_file($path);

    # chmod
    $self->chmod_file($path, $mod);
}

sub class_to_file {
    my ($self, $class) = @_;

    # Class to file
    $class =~ s/:://g;
    $class = b($class)->decamelize->to_string;

    return $class;
}

sub class_to_path {
    my ($self, $class) = @_;

    # Class to path (work with unix paths everywhere internally)
    my $path = join '/', split /::/, $class;

    return "$path.pm";
}

sub create_dir {
    my ($self, $path) = @_;

    # Exists
    if (-d $path) {
        print "  [exist] $path\n" unless $self->quiet;
        return $self;
    }

    # Make
    File::Path::mkpath($path) or croak qq/Can't make directory "$path": $!/;
    print "  [mkdir] $path\n" unless $self->quiet;
    return $self;
}

sub create_rel_dir {
    my ($self, $path) = @_;

    # Path
    $path = $self->rel_dir($path);

    # Create
    $self->create_dir($path);
}

sub get_all_data {
    my ($self, $class) = @_;
    $class ||= ref $self;

    # Handle
    my $d = do { no strict 'refs'; \*{"$class\::DATA"} };

    # Shortcut
    return unless fileno $d;

    # Reset
    seek $d, 0, 0;

    # Slurp
    my $content = join '', <$d>;

    # Ignore everything before __DATA__ (windows will seek to start of file)
    $content =~ s/^.*\n__DATA__\n/\n/s;

    # Ignore everything after __END__
    $content =~ s/\n__END__\n.*$/\n/s;

    # Split
    my @data = split /^@@\s+(.+)\s*\r?\n/m, $content;

    # Remove split garbage
    shift @data;

    # Find data
    my $all = {};
    while (@data) {
        my ($name, $content) = splice @data, 0, 2;
        $all->{$name} = $content;
    }

    return $all;
}

sub get_data {
    my ($self, $data, $class) = @_;

    # All data
    my $all = $self->get_all_data($class);

    return $all->{$data};
}

sub help {
    my $self = shift;
    print $self->usage;
    exit;
}

sub rel_dir {
    my ($self, $path) = @_;

    # Parts
    my @parts = split /\//, $path;

    # Render
    return File::Spec->catdir(Cwd::getcwd(), @parts);
}

sub rel_file {
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

sub render_to_rel_file {
    my $self = shift;
    my $data = shift;
    my $path = shift;

    # Path
    $path = $self->rel_dir($path);

    # Render
    $self->render_to_file($data, $path, @_);
}

# My cat's breath smells like cat food.
sub run { croak 'Method "run" not implemented by subclass' }

sub write_file {
    my ($self, $path, $data) = @_;

    # Directory (expect an OS-dependent path from rel_file() )
    my @parts = File::Spec->splitdir($path);
    pop @parts;
    my $dir = File::Spec->catdir(@parts);
    $self->create_dir($dir);

    # Open file
    my $file = IO::File->new;
    $file->open(">$path") or croak qq/Can't open file "$path": $!/;

    # Write unbuffered
    $file->syswrite($data);

    print "  [write] $path\n" unless $self->quiet;
    return $self;
}

sub write_rel_file {
    my ($self, $path, $data) = @_;

    # Path
    $path = $self->rel_file($path);

    # Write
    $self->write_file($path, $data);
}

1;
__END__

=head1 NAME

Mojo::Command - Command Base Class

=head1 SYNOPSIS

    use base 'Mojo::Command';

    sub run {
        my $self = shift;
        $self->render_to_rel_file('foo_bar', 'foo/bar.txt');
    }

    1;
    __DATA__

    @@ foo_bar
    % for (1 .. 5) {
        Hello World!
    % }

=head1 DESCRIPTION

L<Mojo::Command> is an abstract base class for commands.

Mojo commands are available as arguments to the C<mojo> and
C<mojolicious> commands, application scripts (C<< script/appname >>)
and Mojolicious::Lite applications.

See L<Mojo::Commands> for an overview of command syntax and use as
well as information on how to implement sub-commands.

=head1 ATTRIBUTES

L<Mojo::Command> implements the following attributes.

=head2 C<description>

    my $description = $command->description;
    $command        = $command->description('Foo!');

Used in help messages and commands listings.

=head2 C<quiet>

    my $quiet = $command->quiet;
    $command  = $command->quiet(1);

Do not print messages to STDOUT as you go.

=head2 C<usage>

    my $usage = $command->usage;
    $command  = $command->usage('Foo!');

Usage and argument description for help messages.

=head1 METHODS

L<Mojo::Command> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<chmod_file>

    $command = $command->chmod_file('/foo/bar.txt', 0644);

Portably change mode and permissions of a file or directory. Arguments are unix-style.


=head2 C<chmod_rel_file>

    $command = $command->chmod_rel_file('foo/bar.txt', 0644);

A relative-path version of C<chmod_file>.

=head2 C<class_to_file>

    my $file = $command->class_to_file('Foo::Bar');

Converts a class name to a suitable file name for a script. Used for
code generation. See L<Mojo::Command:Generate::App> for an example.

=head2 C<class_to_path>

    my $path = $command->class_to_path('Foo::Bar');

Convert class hierarchy to a unix-like path.

=head2 C<create_dir>

    $command = $command->create_dir('/foo/bar/baz');

Portably create a directory using an absolute path argument.

=head2 C<create_rel_dir>

    $command = $command->create_rel_dir('foo/bar/baz');

A relative-path version of C<crete_dir>.

=head2 C<get_all_data>

    my $all = $command->get_all_data;
    my $all = $command->get_all_data('Some::Class');

Loads data from the C<__DATA__> section of the file. Defaults to the
class of the C<$command> object. Returns a hashref. Used to process
templates from C<__DATA__> sections.

=head2 C<get_data>

    my $data = $command->get_data('foo_bar');
    my $data = $command->get_data('foo_bar', 'Some::Class');

Uses C<get_all_data> and returns only the selected hash key.

=head2 C<help>

    $command->help;

Prints C<usage> attribute.

=head2 C<rel_dir>

    my $path = $command->rel_dir('foo/bar');

Portably builds an absolute path for a directory from the current working
directory and a relative path argument.

=head2 C<rel_file>

    my $path = $command->rel_file('foo/bar.txt');

The same, for a file.

=head2 C<render_data>

    my $data = $command->render_data('foo_bar', @arguments);

Uses a renderer to process the template C<'foo_bar'> with C<@arguments>.

=head2 C<render_to_file>

    $command = $command->render_to_file('foo_bar', '/foo/bar.txt');

The same, with output to a file.

=head2 C<render_to_rel_file>

    $command = $command->render_to_rel_file('foo_bar', 'foo/bar.txt');

The same, with output to a file with a relative path.

=head2 C<run>

    $command = $command->run(@ARGV);

Virtual method for execution of the command. To be implemented by the
command subclass.

=head2 C<write_file>

    $command = $command->write_file('/foo/bar.txt', 'Hello World!');

Portably write text to a file.

=head2 C<write_rel_file>

    $command = $command->write_rel_file('foo/bar.txt', 'Hello World!');

Portably write text to a file with a relative path.

=head1 IMPLEMENTING A COMMAND

    package Mojo::Command::<command_name_capitalized>;
    
    use strict;
    use warnings;
    
    use base 'Mojo::Command';
    
    use Getopt::Long 'GetOptions';
    
    __PACKAGE__->attr(description => <<'EOF');
    <Command description here>
    EOF
    __PACKAGE__->attr(usage => <<"EOF");
    usage: $0 <command name> <arguments>
    
    These options are available:
      --<option>    <description>
    EOF
    
    # <suitable Futurama comment here>
    sub run {
        my $self = shift;
    
        # Options
        @ARGV = @_ if @_;
        GetOptions('<option>' => sub { $<option> = 1 });
    
        <perform action>
    }

Note that the L<Mojo::Commands> C<start> method should call your
command after taking care of getting the arguments from @ARGV.

See L<Mojo::Command::Get> for an example of interaction with the
application and L<Mojo::Command:Generate::Makefile> for an example of
simple file generation and using templates.

=head1 SEE ALSO

L<Mojo::Commands> for sub-commands, L<Mojolicious>,
L<Mojolicious::Book>, L<http://mojolicious.org>.

=cut
