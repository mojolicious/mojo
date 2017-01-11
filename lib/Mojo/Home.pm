package Mojo::Home;
use Mojo::Base 'Mojo::File';

use Mojo::Util qw(class_to_path deprecated);

sub detect {
  my ($self, $class) = @_;

  # Environment variable
  my $home;
  if ($ENV{MOJO_HOME}) { $home = Mojo::File->new($ENV{MOJO_HOME})->to_array }

  # Location of the application class (Windows mixes backslash and slash)
  elsif ($class && (my $path = $INC{my $file = class_to_path $class})) {
    $home = Mojo::File->new($path)->to_array;
    splice @$home, split('/', $file) * -1;
    pop @$home if @$home && ($home->[-1] eq 'blib' || $home->[-1] eq 'lib');
  }

  $$self = Mojo::File->new(@$home)->to_abs->to_string if $home;
  return $self;
}

# DEPRECATED!
sub lib_dir {
  deprecated 'Mojo::Home::lib_dir is DEPRECATED';
  shift->child('lib')->to_string;
}

# DEPRECATED!
sub list_files {
  deprecated
    'Mojo::Home::list_files is DEPRECATED in favor of Mojo::Files::list_tree';
  my ($self, $dir, $options) = (shift, shift // '', shift);
  my $base = $self->child(split('/', $dir));
  $base->list_tree($options)->map(sub { join '/', @{$_->to_rel($base)} })
    ->to_array;
}

sub mojo_lib_dir { shift->new(__FILE__)->dirname->child('..') }

# DEPRECATED!
sub parse {
  deprecated 'Mojo::Home::parse is DEPRECATED';
  my $self = shift;
  $$self = shift;
  return $self;
}

# DEPRECATED!
sub parts {
  deprecated 'Mojo::Home::parts is DEPRECATED';
  my $self = shift;
  return $self->to_array unless @_;
  $$self = Mojo::File->new(@{shift()})->to_string;
  return $self;
}

# DEPRECATED!
sub rel_dir {
  deprecated
    'Mojo::Home::rel_dir is DEPRECATED in favor of Mojo::Home::rel_file';
  Mojo::File->new(@{shift->parts}, split('/', shift))->to_string;
}

sub rel_file { shift->child(split('/', shift)) }

1;

=encoding utf8

=head1 NAME

Mojo::Home - Home sweet home

=head1 SYNOPSIS

  use Mojo::Home;

  # Find and manage the project root directory
  my $home = Mojo::Home->new;
  $home->detect;
  say $home->child('templates', 'layouts', 'default.html.ep');
  say "$home";

=head1 DESCRIPTION

L<Mojo::Home> is a container for home directories based on L<Mojo::File>.

=head1 METHODS

L<Mojo::Home> inherits all methods from L<Mojo::File> and implements the
following new ones.

=head2 detect

  $home = $home->detect;
  $home = $home->detect('My::App');

Detect home directory from the value of the C<MOJO_HOME> environment variable or
the location of the application class.

=head2 mojo_lib_dir

  my $path = $home->mojo_lib_dir;

Path to C<lib> directory in which L<Mojolicious> is installed as a L<Mojo::Home>
object.

=head2 rel_file

  my $path = $home->rel_file('foo/bar.html');

Return a new L<Mojo::Home> object relative to the home directory.

=head1 OPERATORS

L<Mojo::Home> inherits all overloaded operators from L<Mojo::File>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
