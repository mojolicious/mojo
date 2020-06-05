package Mojolicious::Command;
use Mojo::Base -base;

use Carp qw(croak);
use Mojo::File qw(path);
use Mojo::Loader qw(data_section);
use Mojo::Server;
use Mojo::Template;

has app         => sub { $_[0]{app_ref} = Mojo::Server->new->build_app('Mojo::HelloWorld') }, weak => 1;
has description => 'No description';
has 'quiet';
has template => sub { {vars => 1} };
has usage    => "Usage: APPLICATION\n";

sub chmod_file {
  my ($self, $path, $mode) = @_;
  path($path)->chmod($mode);
  return $self->_loud("  [chmod] $path " . sprintf('%lo', $mode));
}

sub chmod_rel_file { $_[0]->chmod_file($_[0]->rel_file($_[1]), $_[2]) }

sub create_dir {
  my ($self, $path) = @_;
  return $self->_loud("  [exist] $path") if -d $path;
  path($path)->make_path;
  return $self->_loud("  [mkdir] $path");
}

sub create_rel_dir { $_[0]->create_dir($_[0]->rel_file($_[1])) }

sub extract_usage { Mojo::Util::extract_usage((caller)[1]) }

sub help { print shift->usage }

sub rel_file { path->child(split('/', pop)) }

sub render_data {
  my ($self, $name) = (shift, shift);
  my $template = Mojo::Template->new($self->template)->name("template $name from DATA section");
  my $output   = $template->render(data_section(ref $self, $name), @_);
  return ref $output ? die $output : $output;
}

sub render_to_file {
  my ($self, $data, $path) = (shift, shift, shift);
  return $self->write_file($path, $self->render_data($data, @_));
}

sub render_to_rel_file {
  my $self = shift;
  $self->render_to_file(shift, $self->rel_file(shift), @_);
}

sub run { croak 'Method "run" not implemented by subclass' }

sub write_file {
  my ($self, $path, $data) = @_;
  return $self->_loud("  [exist] $path") if -f $path;
  $self->create_dir(path($path)->dirname);
  path($path)->spurt($data);
  return $self->_loud("  [write] $path");
}

sub write_rel_file { $_[0]->write_file($_[0]->rel_file($_[1]), $_[2]) }

sub _loud {
  my ($self, $msg) = @_;
  say $msg unless $self->quiet;
  return $self;
}

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

  # Usage message from SYNOPSIS
  has usage => sub { shift->extract_usage };

  sub run {
    my ($self, @args) = @_;

    # Magic here! :)
  }

  =head1 SYNOPSIS

    Usage: APPLICATION mycommand [OPTIONS]

    Options:
      -s, --something   Does something

  =cut

=head1 DESCRIPTION

L<Mojolicious::Command> is an abstract base class for L<Mojolicious> commands.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command> implements the following attributes.

=head2 app

  my $app  = $command->app;
  $command = $command->app(Mojolicious->new);

Application for command, defaults to a L<Mojo::HelloWorld> object. Note that this attribute is weakened.

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

=head2 template

  my $template = $command->template;
  $command     = $command->template({vars => 1});

Attribute values passed to L<Mojo::Template> objects used to render templates with L</"render_data">, defaults to
activating C<vars>.

=head2 usage

  my $usage = $command->usage;
  $command  = $command->usage('Foo');

Usage information for command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 chmod_file

  $command = $command->chmod_file('/home/sri/foo.txt', 0644);

Change mode of a file.

=head2 chmod_rel_file

  $command = $command->chmod_rel_file('foo/foo.txt', 0644);

Portably change mode of a file relative to the current working directory.

=head2 create_dir

  $command = $command->create_dir('/home/sri/foo/bar');

Create a directory if it does not exist already.

=head2 create_rel_dir

  $command = $command->create_rel_dir('foo/bar/baz');

Portably create a directory relative to the current working directory if it does not exist already.

=head2 extract_usage

  my $usage = $command->extract_usage;

Extract usage message from the SYNOPSIS section of the file this method was called from with
L<Mojo::Util/"extract_usage">.

=head2 help

  $command->help;

Print usage information for command.

=head2 rel_file

  my $path = $command->rel_file('foo/bar.txt');

Return a L<Mojo::File> object relative to the current working directory.

=head2 render_data

  my $data = $command->render_data('foo_bar');
  my $data = $command->render_data('foo_bar', @args);
  my $data = $command->render_data('foo_bar', {foo => 'bar'});

Render a template from the C<DATA> section of the command class with L<Mojo::Loader> and L<Mojo::Template>. The
template can be configured with L</"template">.

=head2 render_to_file

  $command = $command->render_to_file('foo_bar', '/home/sri/foo.txt');
  $command = $command->render_to_file('foo_bar', '/home/sri/foo.txt', @args);
  $command = $command->render_to_file(
    'foo_bar', '/home/sri/foo.txt', {foo => 'bar'});

Render a template with L</"render_data"> to a file if it does not exist already, and create the directory if necessary.

=head2 render_to_rel_file

  $command = $command->render_to_rel_file('foo_bar', 'foo/bar.txt');
  $command = $command->render_to_rel_file('foo_bar', 'foo/bar.txt', @args);
  $command = $command->render_to_rel_file(
    'foo_bar', 'foo/bar.txt', {foo => 'bar'});

Portably render a template with L</"render_data"> to a file relative to the current working directory if it does not
exist already, and create the directory if necessary.

=head2 run

  $command->run;
  $command->run(@ARGV);

Run command. Meant to be overloaded in a subclass.

=head2 write_file

  $command = $command->write_file('/home/sri/foo.txt', 'Hello World!');

Write text to a file if it does not exist already, and create the directory if necessary.

=head2 write_rel_file

  $command = $command->write_rel_file('foo/bar.txt', 'Hello World!');

Portably write text to a file relative to the current working directory if it does not exist already, and create the
directory if necessary.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
