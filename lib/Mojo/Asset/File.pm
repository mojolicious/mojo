package Mojo::Asset::File;
use Mojo::Base 'Mojo::Asset';

use Carp qw(croak);
use Fcntl qw(SEEK_SET);
use File::Spec::Functions ();
use Mojo::File qw(tempfile);

has [qw(cleanup path)];
has handle => sub {
  my $self = shift;

  # Open existing file
  my $path = $self->path;
  return Mojo::File->new($path)->open('<') if defined $path && -e $path;

  $self->cleanup(1) unless defined $self->cleanup;

  # Create a specific file
  return Mojo::File->new($path)->open('+>>') if defined $path;

  # Create a temporary file
  my $file = tempfile DIR => $self->tmpdir, TEMPLATE => 'mojo.tmp.XXXXXXXXXXXXXXXX', UNLINK => 0;
  $self->path($file->to_string);
  return $file->open('+>>');
};
has tmpdir => sub { $ENV{MOJO_TMPDIR} || File::Spec::Functions::tmpdir };

sub DESTROY {
  my $self = shift;

  return unless $self->cleanup && defined(my $path = $self->path);
  if (my $handle = $self->handle) { close $handle }

  # Only the process that created the file is allowed to remove it
  Mojo::File->new($path)->remove if -w $path && ($self->{pid} // $$) == $$;
}

sub add_chunk {
  my ($self, $chunk) = @_;
  ($self->handle->syswrite($chunk) // -1) == length $chunk or croak "Can't write to asset: $!";
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
  my $start  = $handle->sysread(my $window, $len);
  while ($offset < $end) {

    # Read as much as possible
    my $diff = $end - ($start + $offset);
    my $read = $handle->sysread(my $buffer, $diff < $size ? $diff : $size);
    $window .= $buffer;

    # Search window
    my $pos = index $window, $str;
    return $offset + $pos if $pos >= 0;
    return -1             if $read == 0 || ($offset += $read) == $end;

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

sub new {
  my $file = shift->SUPER::new(@_);
  $file->{pid} = $$;
  return $file;
}

sub size { -s shift->handle }

sub slurp {
  my $handle = shift->handle;
  $handle->sysseek(0, SEEK_SET);
  my $ret = my $content = '';
  while ($ret = $handle->sysread(my $buffer, 131072, 0)) { $content .= $buffer }
  return defined $ret ? $content : croak "Can't read from asset: $!";
}

sub to_file {shift}

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

L<Mojo::Asset::File> inherits all attributes from L<Mojo::Asset> and implements the following new ones.

=head2 cleanup

  my $bool = $file->cleanup;
  $file    = $file->cleanup($bool);

Delete L</"path"> automatically once the file is not used anymore.

=head2 handle

  my $handle = $file->handle;
  $file      = $file->handle(IO::File->new);

Filehandle, created on demand for L</"path">, which can be generated automatically and safely based on L</"tmpdir">.

=head2 path

  my $path = $file->path;
  $file    = $file->path('/home/sri/foo.txt');

File path used to create L</"handle">.

=head2 tmpdir

  my $tmpdir = $file->tmpdir;
  $file      = $file->tmpdir('/tmp');

Temporary directory used to generate L</"path">, defaults to the value of the C<MOJO_TMPDIR> environment variable or
auto-detection.

=head1 METHODS

L<Mojo::Asset::File> inherits all methods from L<Mojo::Asset> and implements the following new ones.

=head2 add_chunk

  $file = $file->add_chunk('foo bar baz');

Add chunk of data.

=head2 contains

  my $position = $file->contains('bar');

Check if asset contains a specific string.

=head2 get_chunk

  my $bytes = $file->get_chunk($offset);
  my $bytes = $file->get_chunk($offset, $max);

Get chunk of data starting from a specific position, defaults to a maximum chunk size of C<131072> bytes (128KiB).

=head2 is_file

  my $bool = $file->is_file;

True, this is a L<Mojo::Asset::File> object.

=head2 move_to

  $file = $file->move_to('/home/sri/bar.txt');

Move asset data into a specific file and disable L</"cleanup">.

=head2 mtime

  my $mtime = $file->mtime;

Modification time of asset.

=head2 new

  my $file = Mojo::Asset::File->new;
  my $file = Mojo::Asset::File->new(path => '/home/sri/test.txt');
  my $file = Mojo::Asset::File->new({path => '/home/sri/test.txt'});

Construct a new L<Mojo::Asset::File> object.

=head2 size

  my $size = $file->size;

Size of asset data in bytes.

=head2 slurp

  my $bytes = $file->slurp;

Read all asset data at once.

=head2 to_file

  $file = $file->to_file;

Does nothing but return the invocant, since we already have a L<Mojo::Asset::File> object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
