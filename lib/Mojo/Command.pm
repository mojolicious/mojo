package Mojo::Command;
use Mojo::Base -base;

use Carp 'croak';
use Cwd 'getcwd';
use File::Path 'mkpath';
use File::Spec::Functions qw(catdir catfile splitdir);
use IO::Handle;
use Mojo::Server;
use Mojo::Template;
use Mojo::Util qw(b64_decode decamelize);

has description => 'No description.';
has quiet       => 0;
has usage       => "usage: $0\n";

# Cache
my %CACHE;

sub app { Mojo::Server->new->app }

sub chmod_file {
  my ($self, $path, $mod) = @_;
  chmod $mod, $path or croak qq{Can't chmod path "$path": $!};
  $mod = sprintf '%lo', $mod;
  say "  [chmod] $path $mod" unless $self->quiet;
  return $self;
}

sub chmod_rel_file {
  my ($self, $path, $mod) = @_;
  $self->chmod_file($self->rel_file($path), $mod);
}

sub class_to_file {
  my ($self, $class) = @_;
  $class =~ s/:://g;
  $class =~ s/([A-Z])([A-Z]*)/$1.lc($2)/ge;
  return decamelize $class;
}

sub class_to_path { join '.', join('/', split /::|'/, pop), 'pm' }

sub create_dir {
  my ($self, $path) = @_;

  # Exists
  if (-d $path) {
    say "  [exist] $path" unless $self->quiet;
    return $self;
  }

  # Create
  mkpath $path or croak qq{Can't make directory "$path": $!};
  say "  [mkdir] $path" unless $self->quiet;
  return $self;
}

sub create_rel_dir {
  my ($self, $path) = @_;
  $self->create_dir($self->rel_dir($path));
}

# "Olive oil? Asparagus? If your mother wasn't so fancy,
#  we could just shop at the gas station like normal people."
sub get_all_data {
  my ($self, $class) = @_;
  $class ||= ref $self;

  # Refresh or use cached data
  my $d = do { no strict 'refs'; \*{"$class\::DATA"} };
  return $CACHE{$class} || {} unless fileno $d;
  seek $d, 0, 0;
  my $content = join '', <$d>;
  close $d;

  # Ignore everything before __DATA__ (windows will seek to start of file)
  $content =~ s/^.*\n__DATA__\r?\n/\n/s;

  # Ignore everything after __END__
  $content =~ s/\n__END__\r?\n.*$/\n/s;

  # Split
  my @data = split /^@@\s*(.+?)\s*\r?\n/m, $content;
  shift @data;

  # Find data
  my $all = $CACHE{$class} = {};
  while (@data) {
    my ($name, $content) = splice @data, 0, 2;
    $content = b64_decode $content if $name =~ s/\s*\(\s*base64\s*\)$//;
    $all->{$name} = $content;
  }

  return $all;
}

sub get_data {
  my ($self, $data, $class) = @_;
  $self->get_all_data($class)->{$data};
}

# "You don't like your job, you don't strike.
#  You go in every day and do it really half-assed. That's the American way."
sub help {
  print shift->usage;
  exit 0;
}

sub rel_dir { catdir(getcwd(), split /\//, pop) }

sub rel_file { catfile(getcwd(), split /\//, pop) }

sub render_data { Mojo::Template->new->render(shift->get_data(shift), @_) }

sub render_to_file {
  my ($self, $data, $path) = (shift, shift, shift);
  return $self->write_file($path, $self->render_data($data, @_));
}

sub render_to_rel_file {
  my $self = shift;
  $self->render_to_file(shift, $self->rel_dir(shift), @_);
}

sub run { croak 'Method "run" not implemented by subclass' }

# "The only thing I asked you to do for this party was put on clothes,
#  and you didn't do it."
sub write_file {
  my ($self, $path, $data) = @_;

  # Directory
  my @parts = splitdir $path;
  pop @parts;
  my $dir = catdir @parts;
  $self->create_dir($dir);

  # Write unbuffered
  croak qq{Can't open file "$path": $!} unless open my $file, '>', $path;
  croak qq{Can't write to file "$path": $!}
    unless defined $file->syswrite($data);
  say "  [write] $path" unless $self->quiet;

  return $self;
}

sub write_rel_file {
  my ($self, $path, $data) = @_;
  $self->write_file($self->rel_file($path), $data);
}

1;

=head1 NAME

Mojo::Command - Command base class

=head1 SYNOPSIS

  # Lower case command name
  package Mojolicious::Command::mycommand;

  # Subclass
  use Mojo::Base 'Mojo::Command';

  # Take care of command line options
  use Getopt::Long 'GetOptions';

  # Short description
  has description => "My first Mojo command.\n";

  # Short usage message
  has usage => <<"EOF";
  usage: $0 mycommand [OPTIONS]

  These options are available:
    -s, --something   Does something.
  EOF

  # <suitable Futurama quote here>
  sub run {
    my $self = shift;

    # Handle options
    local @ARGV = @_;
    GetOptions('s|something' => sub { $something = 1 });

    # Magic here! :)
  }

=head1 DESCRIPTION

L<Mojo::Command> is an abstract base class for L<Mojo> commands.

See L<Mojolicious::Commands> for a list of commands that are available by
default.

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

=head2 C<app>

  my $app = $command->app;

Currently active application.

  # Introspect
  say "Template path: $_" for @{$command->app->renderer->paths};

=head2 C<chmod_file>

  $command = $command->chmod_file('/home/sri/foo.txt', 0644);

Portably change mode of a file.

=head2 C<chmod_rel_file>

  $command = $command->chmod_rel_file('foo/foo.txt', 0644);

Portably change mode of a file relative to the current working directory.

=head2 C<class_to_file>

  my $file = $command->class_to_file('Foo::Bar');

Convert a class name to a file.

  Foo::Bar -> foo_bar
  FOO::Bar -> foobar
  FooBar   -> foo_bar
  FOOBar   -> foobar

=head2 C<class_to_path>

  my $path = $command->class_to_path('Foo::Bar');

Convert class name to path.

  Foo::Bar -> Foo/Bar.pm

=head2 C<create_dir>

  $command = $command->create_dir('/home/sri/foo/bar');

Portably create a directory.

=head2 C<create_rel_dir>

  $command = $command->create_rel_dir('foo/bar/baz');

Portably create a directory relative to the current working directory.

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

Portably generate an absolute path for a directory relative to the current
working directory.

=head2 C<rel_file>

  my $path = $command->rel_file('foo/bar.txt');

Portably generate an absolute path for a file relative to the current working
directory.

=head2 C<render_data>

  my $data = $command->render_data('foo_bar', @args);

Render a template from the C<DATA> section of the command class.

=head2 C<render_to_file>

  $command = $command->render_to_file('foo_bar', '/home/sri/foo.txt');

Render a template from the C<DATA> section of the command class to a file.

=head2 C<render_to_rel_file>

  $command = $command->render_to_rel_file('foo_bar', 'foo/bar.txt');

Portably render a template from the C<DATA> section of the command class to a
file relative to the current working directory.

=head2 C<run>

  $command->run;
  $command->run(@ARGV);

Run command. Meant to be overloaded in a subclass.

=head2 C<write_file>

  $command = $command->write_file('/home/sri/foo.txt', 'Hello World!');

Portably write text to a file.

=head2 C<write_rel_file>

  $command = $command->write_rel_file('foo/bar.txt', 'Hello World!');

Portably write text to a file relative to the current working directory.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
