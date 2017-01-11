package Mojo::File;
use Mojo::Base -strict;
use overload
  '@{}'    => sub { shift->to_array },
  bool     => sub {1},
  '""'     => sub { ${$_[0]} },
  fallback => 1;

use Carp 'croak';
use Cwd 'getcwd';
use Exporter 'import';
use File::Basename ();
use File::Copy     ();
use File::Find     ();
use File::Path     ();
use File::Spec::Functions
  qw(abs2rel canonpath catfile file_name_is_absolute rel2abs splitdir);
use File::Temp ();
use Mojo::Collection;

our @EXPORT_OK = ('path', 'tempdir');

sub basename { scalar File::Basename::basename ${$_[0]}, @_ }

sub child { $_[0]->new(@_) }

sub dirname { $_[0]->new(scalar File::Basename::dirname ${$_[0]}) }

sub is_abs { file_name_is_absolute ${shift()} }

sub list {
  my ($self, $options) = (shift, shift // {});

  return Mojo::Collection->new unless -d $$self;
  opendir(my $dir, $$self) or croak qq{Can't open directory "$$self": $!};
  my @files = grep { $_ ne '.' && $_ ne '..' } readdir $dir;
  @files = grep { !/^\./ } @files unless $options->{hidden};
  @files = map { catfile $$self, $_ } @files;
  @files = grep { !-d } @files unless $options->{dir};

  return Mojo::Collection->new(map { $self->new($_) } sort @files);
}

sub list_tree {
  my ($self, $options) = (shift, shift // {});

  # This may break in the future, but is worth it for performance
  local $File::Find::skip_pattern = qr/^\./ unless $options->{hidden};

  my %files;
  my $w = sub { $files{$File::Find::name}++ };
  my $p = sub { delete $files{$File::Find::dir} };
  File::Find::find {wanted => $w, postprocess => $p, no_chdir => 1}, $$self
    if -d $$self;

  return Mojo::Collection->new(map { $self->new(canonpath($_)) }
      sort keys %files);
}

sub make_path {
  my $self = shift;
  File::Path::make_path $$self, @_
    or croak qq{Can't make directory "$$self": $!};
  return $self;
}

sub move_to {
  my ($self, $to) = @_;
  File::Copy::move($$self, $to)
    or croak qq{Can't move file "$$self" to "$to": $!};
  return $self;
}

sub new {
  my $class = shift;
  my $value = @_ == 1 ? $_[0] : @_ > 1 ? catfile @_ : canonpath getcwd;
  return bless \$value, ref $class || $class;
}

sub path { __PACKAGE__->new(@_) }

sub slurp {
  my $self = shift;

  open my $file, '<', $$self or croak qq{Can't open file "$$self": $!};
  my $ret = my $content = '';
  while ($ret = $file->sysread(my $buffer, 131072, 0)) { $content .= $buffer }
  croak qq{Can't read from file "$$self": $!} unless defined $ret;

  return $content;
}

sub spurt {
  my ($self, $content) = @_;
  open my $file, '>', $$self or croak qq{Can't open file "$$self": $!};
  ($file->syswrite($content) // -1) == length $content
    or croak qq{Can't write to file "$$self": $!};
  return $self;
}

sub tap { shift->Mojo::Base::tap(@_) }

sub tempdir { __PACKAGE__->new(File::Temp->newdir(@_)) }

sub to_abs { $_[0]->new(rel2abs ${$_[0]}) }

sub to_array { [splitdir ${shift()}] }

sub to_rel { $_[0]->new(abs2rel(${$_[0]}, $_[1])) }

sub to_string {"${$_[0]}"}

1;

=encoding utf8

=head1 NAME

Mojo::File - File system paths

=head1 SYNOPSIS

  use Mojo::File;

  # Portably deal with file system paths
  my $path = Mojo::File->new('/home/sri/.vimrc');
  say $path->slurp;
  say $path->basename;
  say $path->dirname->child('.bashrc');

  # Use the alternative constructor
  use Mojo::File 'path';
  my $path = path('/tmp/foo/bar')->make_path;
  $path->child('test.txt')->spurt('Hello Mojo!');

=head1 DESCRIPTION

L<Mojo::File> is a scalar-based container for file system paths that provides a
friendly API for dealing with different operating systems.

  # Access scalar directly to manipulate path
  my $path = Mojo::File->new('/home/sri/test');
  $$path .= '.txt';

=head1 FUNCTIONS

L<Mojo::File> implements the following functions, which can be imported
individually.

=head2 path

  my $path = path;
  my $path = path('/home/sri/.vimrc');
  my $path = path('/home', 'sri', '.vimrc');
  my $path = path(File::Temp->newdir);

Construct a new scalar-based L<Mojo::File> object, defaults to using the current
working directory.

  # "foo/bar/baz.txt" (on UNIX)
  path('foo', 'bar', 'baz.txt');

=head2 tempdir

  my $path = tempdir;
  my $path = tempdir('tempXXXXX');

Construct a new scalar-based L<Mojo::File> object for a temporary directory with
L<File::Temp>.

  # Longer version
  my $path = Mojo::File->new(File::Temp->newdir('tempXXXXX'));

=head1 METHODS

L<Mojo::File> implements the following methods.

=head2 basename

  my $name = $path->basename;
  my $name = $path->basename('.txt');

Return the last level of the path with L<File::Basename>.

  # ".vimrc" (on UNIX)
  Mojo::File->new('/home/sri/.vimrc')->basename;

  # "test" (on UNIX)
  Mojo::File->new('/home/sri/test.txt')->basename('.txt');

=head2 child

  my $child = $path->child('.vimrc');

Return a new L<Mojo::File> object relative to the path.

  # "/home/sri/.vimrc" (on UNIX)
  Mojo::File->new('/home')->child('sri', '.vimrc');

=head2 dirname

  my $name = $path->dirname;

Return all but the last level of the path with L<File::Basename> as a
L<Mojo::File> object.

  # "/home/sri" (on UNIX)
  Mojo::File->new('/home/sri/.vimrc')->dirname;

=head2 is_abs

  my $bool = $path->is_abs;

Check if the path is absolute.

  # True (on UNIX)
  Mojo::File->new('/home/sri/.vimrc')->is_abs;

  # False (on UNIX)
  Mojo::File->new('.vimrc')->is_abs;

=head2 list

  my $collection = $path->list;
  my $collection = $path->list({hidden => 1});

List all files in the directory and return a L<Mojo::Collection> object
containing the results as L<Mojo::File> objects.

  # List files
  say for Mojo::File->new('/home/sri/myapp')->list->each;

These options are currently available:

=over 2

=item dir

  dir => 1

Include directories.

=item hidden

  hidden => 1

Include hidden files.

=back

=head2 list_tree

  my $collection = $path->list_tree;
  my $collection = $path->list_tree({hidden => 1});

List all files recursively in the directory and return a L<Mojo::Collection>
object containing the results as L<Mojo::File> objects.

  # List all templates
  say for Mojo::File->new('/home/sri/myapp/templates')->list_tree->each;

These options are currently available:

=over 2

=item hidden

  hidden => 1

Include hidden files and directories.

=back

=head2 make_path

  $path = $path->make_path;

Create the directories if they don't already exist with L<File::Path>.

=head2 move_to

  $path = $path->move_to('/home/sri/.vimrc.backup');

Move the file.

=head2 new

  my $path = Mojo::File->new;
  my $path = Mojo::File->new('/home/sri/.vimrc');
  my $path = Mojo::File->new('/home', 'sri', '.vimrc');
  my $path = Mojo::File->new(File::Temp->newdir);

Construct a new L<Mojo::File> object, defaults to using the current working
directory.

  # "foo/bar/baz.txt" (on UNIX)
  Mojo::File->new('foo', 'bar', 'baz.txt');

=head2 slurp

  my $bytes = $path->slurp;

Read all data at once from the file.

=head2 spurt

  $path = $path->spurt($bytes);

Write all data at once to the file.

=head2 tap

  $path = $path->tap(sub {...});

Alias for L<Mojo::Base/"tap">.

=head2 to_abs

  my $absolute = $path->to_abs;

Return the canonical path as a L<Mojo::File> object.

=head2 to_array

  my $parts = $path->to_array;

Split the path on directory separators.

  # "home:sri:.vimrc" (on UNIX)
  join ':', @{Mojo::File->new('/home/sri/.vimrc')->to_array};

=head2 to_rel

  my $relative = $path->to_rel('/some/base/path');

Return a relative path from the original path to the destination path as a
L<Mojo::File> object.

  # "sri/.vimrc" (on UNIX)
  Mojo::File->new('/home/sri/.vimrc')->to_rel('/home');

=head2 to_string

  my $str = $path->to_string;

Stringify the path.

=head1 OPERATORS

L<Mojo::File> overloads the following operators.

=head2 array

  my @parts = @$path;

Alias for L</"to_array">.

=head2 bool

  my $bool = !!$path;

Always true.

=head2 stringify

  my $str = "$path";

Alias for L</"to_string">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
