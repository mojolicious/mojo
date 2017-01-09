package Mojo::Asset::File;
use Mojo::Base 'Mojo::Asset';

use Carp 'croak';
use Errno 'EEXIST';
use Fcntl qw(O_APPEND O_CREAT O_EXCL O_RDONLY O_RDWR);
use File::Spec::Functions ();
use IO::File;
use Mojo::File;
use Mojo::Util 'md5_sum';

has [qw(cleanup path)];
has handle => sub {
  my $self = shift;

  # Open existing file
  my $handle = IO::File->new;
  my $path   = $self->path;
  if (defined $path && -f $path) {
    $handle->open($path, O_RDONLY) or croak qq{Can't open file "$path": $!};
    return $handle;
  }

  # Open new or temporary file
  my $base = Mojo::File->new($self->tmpdir, 'mojo.tmp')->to_string;
  my $name = $path // $base;
  until ($handle->open($name, O_APPEND | O_CREAT | O_EXCL | O_RDWR)) {
    croak qq{Can't open file "$name": $!} if defined $path || $! != $!{EEXIST};
    $name = "$base." . md5_sum(time . $$ . rand);
  }
  $self->path($name);

  # Enable automatic cleanup
  $self->cleanup(1) unless defined $self->cleanup;

  return $handle;
};
has tmpdir => sub { $ENV{MOJO_TMPDIR} || File::Spec::Functions::tmpdir };

sub DESTROY {
  my $self = shift;
  return unless $self->cleanup && defined(my $path = $self->path);
  if (my $handle = $self->handle) { close $handle }
  unlink $path if -w $path;
}

sub add_chunk {
  my ($self, $chunk) = @_;
  ($self->handle->syswrite($chunk) // -1) == length $chunk
    or croak "Can't write to asset: $!";
  return $self;
}

sub contains {
  my ($self, $str) = @_;

  my $handle = $self->handle;
  $handle->sysseek($self->start_range, SEEK_SET);

  # Calculate window size
  my $end  = $self->end_range // $self->size;
  my $len  = length $str;
  my $size = $len > 131072 ? $len : 131072;
  $size = $end - $self->start_range if $size > $end - $self->start_range;

  # Sliding window search
  my $offset = 0;
  my $start = $handle->sysread(my $window, $len);
  while ($offset < $end) {

    # Read as much as possible
    my $diff = $end - ($start + $offset);
    my $read = $handle->sysread(my $buffer, $diff < $size ? $diff : $size);
    $window .= $buffer;

    # Search window
    my $pos = index $window, $str;
    return $offset + $pos if $pos >= 0;
    return -1 if $read == 0 || ($offset += $read) == $end;

    # Resize window
    substr $window, 0, $read, '';
  }

  return -1;
}

sub get_chunk {
  my ($self, $offset, $max) = @_;
  $max //= 131072;

  $offset += $self->start_range;
  my $handle = $self->handle;
  $handle->sysseek($offset, SEEK_SET);

  my $buffer;
  if (defined(my $end = $self->end_range)) {
    return '' if (my $chunk = $end + 1 - $offset) <= 0;
    $handle->sysread($buffer, $chunk > $max ? $max : $chunk);
  }
  else { $handle->sysread($buffer, $max) }

  return $buffer;
}

sub is_file {1}

sub move_to {
  my ($self, $to) = @_;

  # Windows requires that the handle is closed
  close $self->handle;
  delete $self->{handle};

  # Move file and prevent clean up
  Mojo::File->new($self->path)->move_to($to);
  return $self->path($to)->cleanup(0);
}

sub mtime { (stat shift->handle)[9] }

sub size { -s shift->handle }

sub slurp {
  my $handle = shift->handle;
  $handle->sysseek(0, SEEK_SET);
  defined $handle->sysread(my $content, -s $handle, 0)
    or croak qq{Can't read from asset: $!};
  return $content;
}

1;

=encoding utf8

=head1 NAME

Mojo::Asset::File - File storage for HTTP content

=head1 SYNOPSIS

  use Mojo::Asset::File;

  # Temporary file
  my $file = Mojo::Asset::File->new;
  $file->add_chunk('foo bar baz');
  say 'File contains "bar"' if $file->contains('bar') >= 0;
  say $file->slurp;

  # Existing file
  my $file = Mojo::Asset::File->new(path => '/home/sri/foo.txt');
  $file->move_to('/yada.txt');
  say $file->slurp;

=head1 DESCRIPTION

L<Mojo::Asset::File> is a file storage backend for HTTP content.

=head1 EVENTS

L<Mojo::Asset::File> inherits all events from L<Mojo::Asset>.

=head1 ATTRIBUTES

L<Mojo::Asset::File> inherits all attributes from L<Mojo::Asset> and implements
the following new ones.

=head2 cleanup

  my $bool = $file->cleanup;
  $file    = $file->cleanup($bool);

Delete L</"path"> automatically once the file is not used anymore.

=head2 handle

  my $handle = $file->handle;
  $file      = $file->handle(IO::File->new);

Filehandle, created on demand for L</"path">, which can be generated
automatically and safely based on L</"tmpdir">.

=head2 path

  my $path = $file->path;
  $file    = $file->path('/home/sri/foo.txt');

File path used to create L</"handle">.

=head2 tmpdir

  my $tmpdir = $file->tmpdir;
  $file      = $file->tmpdir('/tmp');

Temporary directory used to generate L</"path">, defaults to the value of the
C<MOJO_TMPDIR> environment variable or auto-detection.

=head1 METHODS

L<Mojo::Asset::File> inherits all methods from L<Mojo::Asset> and implements
the following new ones.

=head2 add_chunk

  $file = $file->add_chunk('foo bar baz');

Add chunk of data.

=head2 contains

  my $position = $file->contains('bar');

Check if asset contains a specific string.

=head2 get_chunk

  my $bytes = $file->get_chunk($offset);
  my $bytes = $file->get_chunk($offset, $max);

Get chunk of data starting from a specific position, defaults to a maximum
chunk size of C<131072> bytes (128KB).

=head2 is_file

  my $bool = $file->is_file;

True, this is a L<Mojo::Asset::File> object.

=head2 move_to

  $file = $file->move_to('/home/sri/bar.txt');

Move asset data into a specific file and disable L</"cleanup">.

=head2 mtime

  my $mtime = $file->mtime;

Modification time of asset.

=head2 size

  my $size = $file->size;

Size of asset data in bytes.

=head2 slurp

  my $bytes = $file->slurp;

Read all asset data at once.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
