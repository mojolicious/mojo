package Mojo::File;
use Mojo::Base -strict;
use overload '@{}' => sub { shift->to_array }, bool => sub {1}, '""' => sub { ${$_[0]} }, fallback => 1;

use Carp qw(croak);
use Cwd qw(getcwd);
use Exporter qw(import);
use File::Basename ();
use File::Copy qw(copy move);
use File::Find qw(find);
use File::Path ();
use File::Spec::Functions qw(abs2rel canonpath catfile file_name_is_absolute rel2abs splitdir);
use File::stat ();
use File::Temp ();
use IO::File   ();
use Mojo::Collection;

our @EXPORT_OK = ('curfile', 'path', 'tempdir', 'tempfile');

sub basename { File::Basename::basename ${shift()}, @_ }

sub child { $_[0]->new(${shift()}, @_) }

sub chmod {
  my ($self, $mode) = @_;
  chmod $mode, $$self or croak qq{Can't chmod file "$$self": $!};
  return $self;
}

sub copy_to {
  my ($self, $to) = @_;
  copy($$self, $to) or croak qq{Can't copy file "$$self" to "$to": $!};
  return $self->new(-d $to ? ($to, File::Basename::basename $self) : $to);
}

sub curfile { __PACKAGE__->new(Cwd::realpath((caller)[1])) }

sub dirname { $_[0]->new(scalar File::Basename::dirname ${$_[0]}) }

sub extname { shift->basename =~ /.+\.([^.]+)$/ ? $1 : '' }

sub is_abs { file_name_is_absolute ${shift()} }

sub list {
  my ($self, $options) = (shift, shift // {});

  return Mojo::Collection->new unless -d $$self;
  opendir(my $dir, $$self) or croak qq{Can't open directory "$$self": $!};
  my @files = grep { $_ ne '.' && $_ ne '..' } readdir $dir;
  @files = grep { !/^\./ } @files unless $options->{hidden};
  @files = map  { catfile $$self, $_ } @files;
  @files = grep { !-d } @files unless $options->{dir};

  return Mojo::Collection->new(map { $self->new($_) } sort @files);
}

sub list_tree {
  my ($self, $options) = (shift, shift // {});

  # This may break in the future, but is worth it for performance
  local $File::Find::skip_pattern = qr/^\./ unless $options->{hidden};

  # The File::Find documentation lies, this is needed for CIFS
  local $File::Find::dont_use_nlink = 1 if $options->{dont_use_nlink};

  my %all;
  my $wanted = sub {
    if ($options->{max_depth}) {
      (my $rel = $File::Find::name) =~ s!^\Q$$self\E/?!!;
      $File::Find::prune = 1 if splitdir($rel) >= $options->{max_depth};
    }
    $all{$File::Find::name}++ if $options->{dir} || !-d $File::Find::name;
  };
  find {wanted => $wanted, no_chdir => 1}, $$self if -d $$self;
  delete $all{$$self};

  return Mojo::Collection->new(map { $self->new(canonpath $_) } sort keys %all);
}

sub lstat { File::stat::lstat(${shift()}) }

sub make_path {
  my $self = shift;
  File::Path::make_path $$self, @_;
  return $self;
}

sub move_to {
  my ($self, $to) = @_;
  move($$self, $to) or croak qq{Can't move file "$$self" to "$to": $!};
  return $self->new(-d $to ? ($to, File::Basename::basename $self) : $to);
}

sub new {
  my $class = shift;
  croak 'Invalid path' if grep { !defined } @_;
  my $value = @_ == 1 ? $_[0] : @_ > 1 ? catfile @_ : canonpath getcwd;
  return bless \$value, ref $class || $class;
}

sub open {
  my $self   = shift;
  my $handle = IO::File->new;
  $handle->open($$self, @_) or croak qq{Can't open file "$$self": $!};
  return $handle;
}

sub path { __PACKAGE__->new(@_) }

sub realpath { $_[0]->new(Cwd::realpath ${$_[0]}) }

sub remove {
  my ($self, $mode) = @_;
  unlink $$self or croak qq{Can't remove file "$$self": $!} if -e $$self;
  return $self;
}

sub remove_tree {
  my $self = shift;
  File::Path::remove_tree $$self, @_;
  return $self;
}

sub sibling {
  my $self = shift;
  return $self->new(scalar File::Basename::dirname($self), @_);
}

sub slurp {
  my $self = shift;

  CORE::open my $file, '<', $$self or croak qq{Can't open file "$$self": $!};
  my $ret = my $content = '';
  while ($ret = $file->sysread(my $buffer, 131072, 0)) { $content .= $buffer }
  croak qq{Can't read from file "$$self": $!} unless defined $ret;

  return $content;
}

sub spurt {
  my ($self, $content) = (shift, join '', @_);
  CORE::open my $file, '>', $$self or croak qq{Can't open file "$$self": $!};
  ($file->syswrite($content) // -1) == length $content or croak qq{Can't write to file "$$self": $!};
  return $self;
}

sub stat { File::stat::stat(${shift()}) }

sub tap { shift->Mojo::Base::tap(@_) }

sub tempdir { __PACKAGE__->new(File::Temp->newdir(@_)) }

sub tempfile { __PACKAGE__->new(File::Temp->new(@_)) }

sub to_abs { $_[0]->new(rel2abs ${$_[0]}) }

sub to_array { [splitdir ${shift()}] }

sub to_rel { $_[0]->new(abs2rel(${$_[0]}, $_[1])) }

sub to_string {"${$_[0]}"}

sub touch {
  my $self = shift;
  $self->open('>') unless -e $$self;
  utime undef, undef, $$self or croak qq{Can't touch file "$$self": $!};
  return $self;
}

sub with_roles { shift->Mojo::Base::with_roles(@_) }

1;

=encoding utf8

=head1 NAME

Mojo::File - File system paths

=head1 SYNOPSIS

  use Mojo::File;

  # Portably deal with file system paths
  my $path = Mojo::File->new('/home/sri/.vimrc');
  say $path->slurp;
  say $path->dirname;
  say $path->basename;
  say $path->extname;
  say $path->sibling('.bashrc');

  # Use the alternative constructor
  use Mojo::File qw(path);
  my $path = path('/tmp/foo/bar')->make_path;
  $path->child('test.txt')->spurt('Hello Mojo!');

=head1 DESCRIPTION

L<Mojo::File> is a scalar-based container for file system paths that provides a friendly API for dealing with different
operating systems.

  # Access scalar directly to manipulate path
  my $path = Mojo::File->new('/home/sri/test');
  $$path .= '.txt';

=head1 FUNCTIONS

L<Mojo::File> implements the following functions, which can be imported individually.

=head2 curfile

  my $path = curfile;

Construct a new scalar-based L<Mojo::File> object for the absolute path to the current source file.

=head2 path

  my $path = path;
  my $path = path('/home/sri/.vimrc');
  my $path = path('/home', 'sri', '.vimrc');
  my $path = path(File::Temp->newdir);

Construct a new scalar-based L<Mojo::File> object, defaults to using the current working directory.

  # "foo/bar/baz.txt" (on UNIX)
  path('foo', 'bar', 'baz.txt');

=head2 tempdir

  my $path = tempdir;
  my $path = tempdir('tempXXXXX');

Construct a new scalar-based L<Mojo::File> object for a temporary directory with L<File::Temp>.

  # Longer version
  my $path = path(File::Temp->newdir('tempXXXXX'));

=head2 tempfile

  my $path = tempfile;
  my $path = tempfile(DIR => '/tmp');

Construct a new scalar-based L<Mojo::File> object for a temporary file with L<File::Temp>.

  # Longer version
  my $path = path(File::Temp->new(DIR => '/tmp'));

=head1 METHODS

L<Mojo::File> implements the following methods.

=head2 basename

  my $name = $path->basename;
  my $name = $path->basename('.txt');

Return the last level of the path with L<File::Basename>.

  # ".vimrc" (on UNIX)
  path('/home/sri/.vimrc')->basename;

  # "test" (on UNIX)
  path('/home/sri/test.txt')->basename('.txt');

=head2 child

  my $child = $path->child('.vimrc');

Return a new L<Mojo::File> object relative to the path.

  # "/home/sri/.vimrc" (on UNIX)
  path('/home')->child('sri', '.vimrc');

=head2 chmod

  $path = $path->chmod(0644);

Change file permissions.

=head2 copy_to

  my $destination = $path->copy_to('/home/sri');
  my $destination = $path->copy_to('/home/sri/.vimrc.backup');

Copy file with L<File::Copy> and return the destination as a L<Mojo::File> object.

=head2 dirname

  my $name = $path->dirname;

Return all but the last level of the path with L<File::Basename> as a L<Mojo::File> object.

  # "/home/sri" (on UNIX)
  path('/home/sri/.vimrc')->dirname;

=head2 extname

  my $ext = $path->extname;

Return file extension of the path. Note that this method is B<EXPERIMENTAL> and might change without warning!

  # "js"
  path('/home/sri/test.js')->extname;

=head2 is_abs

  my $bool = $path->is_abs;

Check if the path is absolute.

  # True (on UNIX)
  path('/home/sri/.vimrc')->is_abs;

  # False (on UNIX)
  path('.vimrc')->is_abs;

=head2 list

  my $collection = $path->list;
  my $collection = $path->list({hidden => 1});

List all files in the directory and return a L<Mojo::Collection> object containing the results as L<Mojo::File>
objects. The list does not include C<.> and C<..>.

  # List files
  say for path('/home/sri/myapp')->list->each;

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

List all files recursively in the directory and return a L<Mojo::Collection> object containing the results as
L<Mojo::File> objects. The list does not include C<.> and C<..>.

  # List all templates
  say for path('/home/sri/myapp/templates')->list_tree->each;

These options are currently available:

=over 2

=item dir

  dir => 1

Include directories.

=item dont_use_nlink

  dont_use_nlink => 1

Force L<File::Find> to always stat directories.

=item hidden

  hidden => 1

Include hidden files and directories.

=item max_depth

  max_depth => 3

Maximum number of levels to descend when searching for files.

=back

=head2 lstat

  my $stat = $path->lstat;

Return a L<File::stat> object for the symlink.

  # Get symlink size
  say path('/usr/sbin/sendmail')->lstat->size;

  # Get symlink modification time
  say path('/usr/sbin/sendmail')->lstat->mtime;

=head2 make_path

  $path = $path->make_path;
  $path = $path->make_path({mode => 0711});

Create the directories if they don't already exist, any additional arguments are passed through to L<File::Path>.

=head2 move_to

  my $destination = $path->move_to('/home/sri');
  my $destination = $path->move_to('/home/sri/.vimrc.backup');

Move file with L<File::Copy> and return the destination as a L<Mojo::File> object.

=head2 new

  my $path = Mojo::File->new;
  my $path = Mojo::File->new('/home/sri/.vimrc');
  my $path = Mojo::File->new('/home', 'sri', '.vimrc');
  my $path = Mojo::File->new(File::Temp->new);
  my $path = Mojo::File->new(File::Temp->newdir);

Construct a new L<Mojo::File> object, defaults to using the current working directory.

  # "foo/bar/baz.txt" (on UNIX)
  Mojo::File->new('foo', 'bar', 'baz.txt');

=head2 open

  my $handle = $path->open('+<');
  my $handle = $path->open('r+');
  my $handle = $path->open(O_RDWR);
  my $handle = $path->open('<:encoding(UTF-8)');

Open file with L<IO::File>.

  # Combine "fcntl.h" constants
  use Fcntl qw(O_CREAT O_EXCL O_RDWR);
  my $handle = path('/home/sri/test.pl')->open(O_RDWR | O_CREAT | O_EXCL);

=head2 realpath

  my $realpath = $path->realpath;

Resolve the path with L<Cwd> and return the result as a L<Mojo::File> object.

=head2 remove

  $path = $path->remove;

Delete file.

=head2 remove_tree

  $path = $path->remove_tree;
  $path = $path->remove_tree({keep_root => 1});

Delete this directory and any files and subdirectories it may contain, any additional arguments are passed through to
L<File::Path>.

=head2 sibling

  my $sibling = $path->sibling('.vimrc');

Return a new L<Mojo::File> object relative to the directory part of the path.

  # "/home/sri/.vimrc" (on UNIX)
  path('/home/sri/.bashrc')->sibling('.vimrc');

  # "/home/sri/.ssh/known_hosts" (on UNIX)
  path('/home/sri/.bashrc')->sibling('.ssh', 'known_hosts');

=head2 slurp

  my $bytes = $path->slurp;

Read all data at once from the file.

=head2 spurt

  $path = $path->spurt($bytes);
  $path = $path->spurt(@chunks_of_bytes);

Write all data at once to the file.

=head2 stat

  my $stat = $path->stat;

Return a L<File::stat> object for the path.

  # Get file size
  say path('/home/sri/.bashrc')->stat->size;

  # Get file modification time
  say path('/home/sri/.bashrc')->stat->mtime;

=head2 tap

  $path = $path->tap(sub {...});

Alias for L<Mojo::Base/"tap">.

=head2 to_abs

  my $absolute = $path->to_abs;

Return absolute path as a L<Mojo::File> object, the path does not need to exist on the file system.

=head2 to_array

  my $parts = $path->to_array;

Split the path on directory separators.

  # "home:sri:.vimrc" (on UNIX)
  join ':', @{path('/home/sri/.vimrc')->to_array};

=head2 to_rel

  my $relative = $path->to_rel('/some/base/path');

Return a relative path from the original path to the destination path as a L<Mojo::File> object.

  # "sri/.vimrc" (on UNIX)
  path('/home/sri/.vimrc')->to_rel('/home');

=head2 to_string

  my $str = $path->to_string;

Stringify the path.

=head2 touch

  $path = $path->touch;

Create file if it does not exist or change the modification and access time to the current time.

  # Safely read file
  say path('.bashrc')->touch->slurp;

=head2 with_roles

  my $new_class = Mojo::File->with_roles('Mojo::File::Role::One');
  my $new_class = Mojo::File->with_roles('+One', '+Two');
  $path         = $path->with_roles('+One', '+Two');

Alias for L<Mojo::Base/"with_roles">.

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

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
