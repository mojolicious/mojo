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

    # Class to path
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

        # Base 64
        $content = b($content)->b64_decode->to_string
          if $name =~ s/\s*\(\s*base64\s*\)$//;

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

# You don’t like your job, you don’t strike.
# You go in every day and do it really half-assed. That’s the American way.
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

    # Directory
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

    # Camel case command name
    package Mojo::Command::Mycommand;

    # Subclass
    use base 'Mojo::Command';

    # Take care of command line options
    use Getopt::Long 'GetOptions';

    # Short description
    __PACKAGE__->attr(description => <<'EOF');
    My first Mojo command.
    EOF

    # Short usage message
    __PACKAGE__->attr(usage => <<"EOF");
    usage: $0 mycommand [OPTIONS]

    These options are available:
      --something   Does something.
    EOF

    # <suitable Futurama quote here>
    sub run {
        my $self = shift;

        # Handle options
        local @ARGV = @_ if @_;
        GetOptions('something' => sub { $something = 1 });

        # Magic here! :)
    }

=head1 DESCRIPTION

L<Mojo::Command> is an abstract base class for L<Mojo> commands.
See L<Mojo::Commands> for a list of commands that are available by default.

=head1 ATTRIBUTES

L<Mojo::Command> implements the following attributes.

=head2 C<description>

    my $description = $command->description;
    $command        = $command->description('Foo!');

Short description of command, used for the command list.

=head2 C<quiet>

    my $quiet = $command->quiet;
    $command  = $command->quiet(1);

Limited command output.

=head2 C<usage>

    my $usage = $command->usage;
    $command  = $command->usage('Foo!');

Usage information for command, used for the help screen.

=head1 METHODS

L<Mojo::Command> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<chmod_file>

    $command = $command->chmod_file('/foo/bar.txt', 0644);

Portably change mode of a file.

=head2 C<chmod_rel_file>

    $command = $command->chmod_rel_file('foo/bar.txt', 0644);

Portably change mode of a relative file.

=head2 C<class_to_file>

    my $file = $command->class_to_file('Foo::Bar');

Convert a class name to a file.

    FooBar -> foo_bar

=head2 C<class_to_path>

    my $path = $command->class_to_path('Foo::Bar');

Convert class name to path.

    Foo::Bar -> Foo/Bar.pm

=head2 C<create_dir>

    $command = $command->create_dir('/foo/bar/baz');

Portably create a directory.

=head2 C<create_rel_dir>

    $command = $command->create_rel_dir('foo/bar/baz');

Portably create a relative directory.

=head2 C<get_all_data>

    my $all = $command->get_all_data;
    my $all = $command->get_all_data('Some::Class');

Extract all embedded files from the C<DATA> section of a class.

=head2 C<get_data>

    my $data = $command->get_data('foo_bar');
    my $data = $command->get_data('foo_bar', 'Some::Class');

Extract embedded file from the C<DATA> section of a class.

=head2 C<help>

    $command->help;

Print usage information for command.

=head2 C<rel_dir>

    my $path = $command->rel_dir('foo/bar');

Portably generate an absolute path from a relative UNIX style path.

=head2 C<rel_file>

    my $path = $command->rel_file('foo/bar.txt');

Portably generate an absolute path from a relative UNIX style path.

=head2 C<render_data>

    my $data = $command->render_data('foo_bar', @arguments);

Render a template from the C<DATA> section of the command class.

=head2 C<render_to_file>

    $command = $command->render_to_file('foo_bar', '/foo/bar.txt');

Render a template from the C<DATA> section of the command class to a file.

=head2 C<render_to_rel_file>

    $command = $command->render_to_rel_file('foo_bar', 'foo/bar.txt');

Portably render a template from the C<DATA> section of the command class to a
relative file.

=head2 C<run>

    $command = $command->run(@ARGV);

Run command.

=head2 C<write_file>

    $command = $command->write_file('/foo/bar.txt', 'Hello World!');

Portably write text to a file.

=head2 C<write_rel_file>

    $command = $command->write_rel_file('foo/bar.txt', 'Hello World!');

Portably write text to a relative file.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
