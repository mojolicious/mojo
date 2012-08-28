package Mojo::Home;
use Mojo::Base -base;
use overload
  'bool'   => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

use Cwd 'abs_path';
use File::Basename 'dirname';
use File::Find 'find';
use File::Spec::Functions qw(abs2rel catdir catfile splitdir);
use FindBin;
use Mojo::Util qw(class_to_path slurp);

sub new { shift->SUPER::new->parse(@_) }

sub detect {
  my $self = shift;

  # Environment variable
  if ($ENV{MOJO_HOME}) {
    $self->{parts} = [splitdir(abs_path $ENV{MOJO_HOME})];
    return $self;
  }

  # Try to find home from lib directory
  if (my $class = @_ ? shift : 'Mojo::HelloWorld') {
    my $file = class_to_path $class;
    if (my $path = $INC{$file}) {
      $path =~ s/$file$//;
      my @home = splitdir $path;

      # Remove "lib" and "blib"
      pop @home while @home && ($home[-1] =~ /^b?lib$/ || $home[-1] eq '');

      # Turn into absolute path
      $self->{parts} = [splitdir(abs_path(catdir(@home) || '.'))];
    }
  }

  # FindBin fallback
  $self->{parts} = [split /\//, $FindBin::Bin] unless $self->{parts};

  return $self;
}

sub lib_dir {
  my $path = catdir @{shift->{parts} || []}, 'lib';
  return -d $path ? $path : undef;
}

sub list_files {
  my ($self, $dir) = @_;

  # Files relative to directory
  my $parts = $self->{parts} || [];
  my $root = catdir @$parts;
  $dir = catdir $root, split '/', ($dir || '');
  return [] unless -d $dir;
  my @files;
  find {
    wanted => sub {
      my @parts = splitdir(abs2rel($File::Find::name, $dir));
      push @files, join '/', @parts unless /^\./ ~~ \@parts;
    },
    no_chdir => 1
  }, $dir;

  return [sort @files];
}

sub mojo_lib_dir { catdir(dirname(__FILE__), '..') }

sub parse {
  my ($self, $path) = @_;
  return $self unless defined $path;
  $self->{parts} = [splitdir $path];
  return $self;
}

sub rel_dir { catdir(@{shift->{parts} || []}, split '/', shift) }
sub rel_file { catfile(@{shift->{parts} || []}, split '/', shift) }

sub slurp_rel_file { slurp shift->rel_file(@_) }

sub to_string { catdir(@{shift->{parts} || []}) }

1;

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

=head1 METHODS

L<Mojo::Home> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $home = Mojo::Home->new;
  my $home = Mojo::Home->new('/home/sri/myapp');

Construct a new L<Mojo::Home> object.

=head2 C<detect>

  $home = $home->detect;
  $home = $home->detect('My::App');

Detect home directory from the value of the C<MOJO_HOME> environment variable
or application class.

=head2 C<lib_dir>

  my $path = $home->lib_dir;

Path to C<lib> directory of application.

=head2 C<list_files>

  my $files = $home->list_files;
  my $files = $home->list_files('foo/bar');

Portably list all files recursively in directory relative to the home
diectory.

  $home->rel_file($home->list_files('templates/layouts')->[1]);

=head2 C<mojo_lib_dir>

  my $path = $home->mojo_lib_dir;

Path to C<lib> directory in which L<Mojolicious> is installed.

=head2 C<parse>

  $home = $home->parse('/home/sri/myapp');

Parse home directory.

=head2 C<rel_dir>

  my $path = $home->rel_dir('foo/bar');

Portably generate an absolute path for a directory relative to the home
directory.

=head2 C<rel_file>

  my $path = $home->rel_file('foo/bar.html');

Portably generate an absolute path for a file relative to the home directory.

=head2 C<slurp_rel_file>

  my $content = $home->slurp_rel_file('foo/bar.html');

Portably read all data at once from file relative to the home directory.

  my $content = $home->slurp_rel_file($home->list_files('public')->[1]);

=head2 C<to_string>

  my $string = $home->to_string;
  my $string = "$home";

Home directory.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
