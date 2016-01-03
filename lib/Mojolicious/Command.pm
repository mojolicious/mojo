package Mojolicious::Command;
use Mojo::Base -base;

use Carp 'croak';
use Cwd 'getcwd';
use File::Basename 'dirname';
use File::Path 'mkpath';
use File::Spec::Functions qw(catdir catfile);
use Mojo::Loader 'data_section';
use Mojo::Server;
use Mojo::Template;
use Mojo::Util qw(spurt unindent);
use Pod::Usage 'pod2usage';

has app => sub { Mojo::Server->new->build_app('Mojo::HelloWorld') };
has description => 'No description';
has 'quiet';
has usage => "Usage: APPLICATION\n";

sub chmod_file {
  my ($self, $path, $mod) = @_;
  chmod $mod, $path or croak qq{Can't chmod file "$path": $!};
  say "  [chmod] $path " . sprintf('%lo', $mod) unless $self->quiet;
  return $self;
}

sub chmod_rel_file { $_[0]->chmod_file($_[0]->rel_file($_[1]), $_[2]) }

sub create_dir {
  my ($self, $path) = @_;

  if (-d $path) { say "  [exist] $path" unless $self->quiet }
  else {
    mkpath $path or croak qq{Can't make directory "$path": $!};
    say "  [mkdir] $path" unless $self->quiet;
  }

  return $self;
}

sub create_rel_dir { $_[0]->create_dir($_[0]->rel_dir($_[1])) }

sub extract_usage {
  my $self = shift;

  open my $handle, '>', \my $output;
  pod2usage -exitval => 'noexit', -input => (caller)[1], -output => $handle;
  $output =~ s/^.*\n//;
  $output =~ s/\n$//;

  return unindent $output;
}

sub help { print shift->usage }

sub rel_dir  { catdir getcwd(),  split('/', pop) }
sub rel_file { catfile getcwd(), split('/', pop) }

sub render_data {
  my ($self, $name) = (shift, shift);
  Mojo::Template->new->name("template $name from DATA section")
    ->render(data_section(ref $self, $name), @_);
}

sub render_to_file {
  my ($self, $data, $path) = (shift, shift, shift);
  return $self->write_file($path, $self->render_data($data, @_));
}

sub render_to_rel_file {
  my $self = shift;
  $self->render_to_file(shift, $self->rel_dir(shift), @_);
}

sub run { croak 'Method "run" not implemented by subclass' }

sub write_file {
  my ($self, $path, $data) = @_;
  $self->create_dir(dirname $path);
  spurt $data, $path;
  say "  [write] $path" unless $self->quiet;
  return $self;
}

sub write_rel_file { $_[0]->write_file($_[0]->rel_file($_[1]), $_[2]) }

1;

=encoding utf8

=head1 NAME

Mojolicious::Command - Command base class

=head1 SYNOPSIS

  # Lowercase command name
  package Mojolicious::Command::mycommand;
  use Mojo::Base 'Mojolicious::Command';

  # Short description
  has description => 'My first Mojo command';

  # Short usage message
  has usage => <<EOF;
  Usage: APPLICATION mycommand [OPTIONS]

  Options:
    -s, --something   Does something
  EOF

  sub run {
    my ($self, @args) = @_;

    # Magic here! :)
  }

=head1 DESCRIPTION

L<Mojolicious::Command> is an abstract base class for L<Mojolicious> commands.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are
available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command> implements the following attributes.

=head2 app

  my $app  = $command->app;
  $command = $command->app(Mojolicious->new);

Application for command, defaults to a L<Mojo::HelloWorld> object.

  # Introspect
  say "Template path: $_" for @{$command->app->renderer->paths};

=head2 description

  my $description = $command->description;
  $command        = $command->description('Foo');

Short description of command, used for the command list.

=head2 quiet

  my $bool = $command->quiet;
  $command = $command->quiet($bool);

Limited command output.

=head2 usage

  my $usage = $command->usage;
  $command  = $command->usage('Foo');

Usage information for command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 chmod_file

  $command = $command->chmod_file('/home/sri/foo.txt', 0644);

Change mode of a file.

=head2 chmod_rel_file

  $command = $command->chmod_rel_file('foo/foo.txt', 0644);

Portably change mode of a file relative to the current working directory.

=head2 create_dir

  $command = $command->create_dir('/home/sri/foo/bar');

Create a directory.

=head2 create_rel_dir

  $command = $command->create_rel_dir('foo/bar/baz');

Portably create a directory relative to the current working directory.

=head2 extract_usage

  my $usage = $command->extract_usage;

Extract usage message from the SYNOPSIS section of the file this method was
called from.

=head2 help

  $command->help;

Print usage information for command.

=head2 rel_dir

  my $path = $command->rel_dir('foo/bar');

Portably generate an absolute path for a directory relative to the current
working directory.

=head2 rel_file

  my $path = $command->rel_file('foo/bar.txt');

Portably generate an absolute path for a file relative to the current working
directory.

=head2 render_data

  my $data = $command->render_data('foo_bar');
  my $data = $command->render_data('foo_bar', @args);

Render a template from the C<DATA> section of the command class with
L<Mojo::Loader> and L<Mojo::Template>.

=head2 render_to_file

  $command = $command->render_to_file('foo_bar', '/home/sri/foo.txt');
  $command = $command->render_to_file('foo_bar', '/home/sri/foo.txt', @args);

Render a template from the C<DATA> section of the command class with
L<Mojo::Template> to a file and create directory if necessary.

=head2 render_to_rel_file

  $command = $command->render_to_rel_file('foo_bar', 'foo/bar.txt');
  $command = $command->render_to_rel_file('foo_bar', 'foo/bar.txt', @args);

Portably render a template from the C<DATA> section of the command class with
L<Mojo::Template> to a file relative to the current working directory and
create directory if necessary.

=head2 run

  $command->run;
  $command->run(@ARGV);

Run command. Meant to be overloaded in a subclass.

=head2 write_file

  $command = $command->write_file('/home/sri/foo.txt', 'Hello World!');

Write text to a file and create directory if necessary.

=head2 write_rel_file

  $command = $command->write_rel_file('foo/bar.txt', 'Hello World!');

Portably write text to a file relative to the current working directory and
create directory if necessary.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
