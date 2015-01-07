package Mojo::Home;
use Mojo::Base -base;
use overload bool => sub {1}, '""' => sub { shift->to_string }, fallback => 1;

use Cwd 'abs_path';
use File::Basename 'dirname';
use File::Find 'find';
use File::Spec::Functions qw(abs2rel catdir catfile splitdir);
use FindBin;
use Mojo::Util qw(class_to_path slurp);

has parts => sub { [] };

sub detect {
  my $self = shift;

  # Environment variable
  return $self->parts([splitdir abs_path $ENV{MOJO_HOME}]) if $ENV{MOJO_HOME};

  # Try to find home from lib directory
  if (my $class = @_ ? shift : 'Mojo::HelloWorld') {
    my $file = class_to_path $class;
    if (my $path = $INC{$file}) {
      $path =~ s/\Q$file\E$//;
      my @home = splitdir $path;

      # Remove "lib" and "blib"
      pop @home while @home && ($home[-1] =~ /^b?lib$/ || $home[-1] eq '');

      # Turn into absolute path
      return $self->parts([splitdir abs_path catdir(@home) || '.']);
    }
  }

  # FindBin fallback
  return $self->parts([split '/', $FindBin::Bin]);
}

sub lib_dir {
  my $path = catdir @{shift->parts}, 'lib';
  return -d $path ? $path : undef;
}

sub list_files {
  my ($self, $dir) = @_;

  $dir = catdir @{$self->parts}, split('/', $dir // '');
  return [] unless -d $dir;
  my @files;
  find {
    wanted => sub {
      my @parts = splitdir abs2rel($File::Find::name, $dir);
      push @files, join '/', @parts unless grep {/^\./} @parts;
    },
    no_chdir => 1
  }, $dir;

  return [sort @files];
}

sub mojo_lib_dir { catdir dirname(__FILE__), '..' }

sub new { @_ > 1 ? shift->SUPER::new->parse(@_) : shift->SUPER::new }

sub parse { shift->parts([splitdir shift]) }

sub rel_dir  { catdir @{shift->parts},  split('/', shift) }
sub rel_file { catfile @{shift->parts}, split('/', shift) }

sub to_string { catdir @{shift->parts} }

1;

=encoding utf8

=head1 NAME

Mojo::Home - Home sweet home!

=head1 SYNOPSIS

  use Mojo::Home;

  # Find and manage the project root directory
  my $home = Mojo::Home->new;
  $home->detect;
  say $home->lib_dir;
  say $home->rel_file('templates/layouts/default.html.ep');
  say "$home";

=head1 DESCRIPTION

L<Mojo::Home> is a container for home directories.

=head1 ATTRIBUTES

L<Mojo::Home> implements the following attributes.

=head2 parts

  my $parts = $home->parts;
  $home     = $home->parts([]);

Home directory parts.

=head1 METHODS

L<Mojo::Home> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 detect

  $home = $home->detect;
  $home = $home->detect('My::App');

Detect home directory from the value of the C<MOJO_HOME> environment variable
or application class.

=head2 lib_dir

  my $path = $home->lib_dir;

Path to C<lib> directory of application.

=head2 list_files

  my $files = $home->list_files;
  my $files = $home->list_files('foo/bar');

Portably list all files recursively in directory relative to the home
directory.

  say $home->rel_file($home->list_files('templates/layouts')->[1]);

=head2 mojo_lib_dir

  my $path = $home->mojo_lib_dir;

Path to C<lib> directory in which L<Mojolicious> is installed.

=head2 new

  my $home = Mojo::Home->new;
  my $home = Mojo::Home->new('/home/sri/my_app');

Construct a new L<Mojo::Home> object and L</"parse"> home directory if
necessary.

=head2 parse

  $home = $home->parse('/home/sri/my_app');

Parse home directory.

=head2 rel_dir

  my $path = $home->rel_dir('foo/bar');

Portably generate an absolute path for a directory relative to the home
directory.

=head2 rel_file

  my $path = $home->rel_file('foo/bar.html');

Portably generate an absolute path for a file relative to the home directory.

=head2 to_string

  my $str = $home->to_string;

Home directory.

=head1 OPERATORS

L<Mojo::Home> overloads the following operators.

=head2 bool

  my $bool = !!$home;

Always true.

=head2 stringify

  my $str = "$home";

Alias for L</"to_string">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
