package Mojo::Asset::File;
use Mojo::Base 'Mojo::Asset';

use Carp 'croak';
use Errno 'EEXIST';
use Fcntl qw(O_CREAT O_EXCL O_RDWR);
use File::Copy 'move';
use File::Spec::Functions 'catfile';
use IO::File;
use Mojo::Util 'md5_sum';

has [qw(cleanup path)];
has handle => sub {
  my $self = shift;

  # Open existing file
  my $handle = IO::File->new;
  my $path   = $self->path;
  if (defined $path && -f $path) {
    $handle->open($path, '<') or croak qq{Can't open file "$path": $!};
    return $handle;
  }

  # Open new or temporary file
  my $base = catfile $self->tmpdir, 'mojo.tmp';
  my $name = $path // $base;
  until ($handle->open($name, O_CREAT | O_EXCL | O_RDWR)) {
    croak qq{Can't open file "$name": $!} if defined $path || $! != $!{EEXIST};
    $name = "$base." . md5_sum(time . $$ . rand 9999999);
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
  close $self->handle;
  unlink $path if -w $path;
}

sub add_chunk {
  my ($self, $chunk) = @_;

  my $handle = $self->handle;
  $handle->sysseek(0, SEEK_END);
  $chunk //= '';
  croak "Can't write to asset: $!"
    unless defined $handle->syswrite($chunk, length $chunk);

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
    $offset += $read;
    return -1 if $read == 0 || $offset == $end;

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
    my $chunk = $end + 1 - $offset;
    return '' if $chunk <= 0;
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
  my $from = $self->path;
  move($from, $to) or croak qq{Can't move file "$from" to "$to": $!};
  return $self->path($to)->cleanup(0);
}

sub size {
  return 0 unless defined(my $file = shift->path);
  return -s $file;
}

sub slurp {
  my $handle = shift->handle;
  $handle->sysseek(0, SEEK_SET);
  my $content = '';
  while ($handle->sysread(my $buffer, 131072)) { $content .= $buffer }
  return $content;
}

1;

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

L<Mojo::Asset::File> inherits all attributes from L<Mojo::Asset> and
implements the following new ones.

=head2 cleanup

  my $cleanup = $file->cleanup;
  $file       = $file->cleanup(1);

Delete file automatically once it's not used anymore.

=head2 handle

  my $handle = $file->handle;
  $file      = $file->handle(IO::File->new);

File handle, created on demand.

=head2 path

  my $path = $file->path;
  $file    = $file->path('/home/sri/foo.txt');

File path used to create C<handle>, can also be automatically generated if
necessary.

=head2 tmpdir

  my $tmpdir = $file->tmpdir;
  $file      = $file->tmpdir('/tmp');

Temporary directory used to generate C<path>, defaults to the value of the
MOJO_TMPDIR environment variable or auto detection.

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
chunk size of C<131072> bytes.

=head2 is_file

  my $true = $file->is_file;

True.

=head2 move_to

  $file = $file->move_to('/home/sri/bar.txt');

Move asset data into a specific file and disable C<cleanup>.

=head2 size

  my $size = $file->size;

Size of asset data in bytes.

=head2 slurp

  my $bytes = $file->slurp;

Read all asset data at once.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
