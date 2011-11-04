package Mojo::Asset::File;
use Mojo::Base 'Mojo::Asset';

use Carp 'croak';
use Errno;
use Fcntl;
use File::Copy ();
use File::Spec;
use IO::File;
use Mojo::Util 'md5_sum';

has [qw/cleanup path/];
has handle => sub {
  my $self = shift;

  # Already got a file without handle
  my $handle = IO::File->new;
  my $file   = $self->path;
  if ($file && -f $file) {
    $handle->open("< $file")
      or croak qq/Can't open file "$file": $!/;
    return $handle;
  }

  # Open existing or temporary file
  my $base = File::Spec->catfile($self->tmpdir, 'mojo.tmp');
  my $name = $file || $base;
  my $fh;
  until (sysopen $fh, $name, O_CREAT | O_EXCL | O_RDWR) {
    croak qq/Can't open file "$name": $!/ if $file || $! != $!{EEXIST};
    $name = "$base." . md5_sum(time . $$ . rand 9999999);
  }
  $file = $name;
  $self->path($file);

  # Enable automatic cleanup
  $self->cleanup(1);

  # Open for read/write access
  $handle->fdopen(fileno($fh), "+>") or croak qq/Can't open file "$name": $!/;

  return $handle;
};
has tmpdir => sub { $ENV{MOJO_TMPDIR} || File::Spec->tmpdir };

# "The only monster here is the gambling monster that has enslaved your
#  mother!
#  I call him Gamblor, and it's time to snatch your mother from his neon
#  claws!"
sub DESTROY {
  my $self = shift;
  my $path = $self->path;
  if ($self->cleanup && -f $path) {
    close $self->handle;
    unlink $path;
  }
}

sub add_chunk {
  my ($self, $chunk) = @_;

  # Seek to end
  $self->handle->sysseek(0, SEEK_END);

  # Append to file
  $chunk //= '';
  $self->handle->syswrite($chunk, length $chunk);

  return $self;
}

sub contains {
  my ($self, $pattern) = @_;

  # Seek to start
  $self->handle->sysseek($self->start_range, SEEK_SET);
  my $end = $self->end_range // $self->size;
  my $window_size = length($pattern) * 2;
  $window_size = $end - $self->start_range
    if $window_size > $end - $self->start_range;

  # Read
  my $read         = $self->handle->sysread(my $window, $window_size);
  my $offset       = $read;
  my $pattern_size = length($pattern);

  # Moving window search
  my $range = $self->end_range;
  while ($offset <= $end) {
    if (defined $range) {
      $pattern_size = $end + 1 - $offset;
      return -1 if $pattern_size <= 0;
    }
    $read = $self->handle->sysread(my $buffer, $pattern_size);
    $offset += $read;
    $window .= $buffer;
    my $pos = index $window, $pattern;
    return $pos if $pos >= 0;
    return -1   if $read == 0;
    substr $window, 0, $read, '';
  }

  return -1;
}

sub get_chunk {
  my ($self, $start) = @_;

  # Seek to start
  $start += $self->start_range;
  $self->handle->sysseek($start, SEEK_SET);
  my $end = $self->end_range;
  my $buffer;

  # Chunk size
  my $size = $ENV{MOJO_CHUNK_SIZE} || 131072;

  # Range support
  if (defined $end) {
    my $chunk = $end + 1 - $start;
    return '' if $chunk <= 0;
    $chunk = $size if $chunk > $size;
    $self->handle->sysread($buffer, $chunk);
  }
  else { $self->handle->sysread($buffer, $size) }

  return $buffer;
}

sub is_file {1}

sub move_to {
  my ($self, $path) = @_;

  # Windows requires that the handle is closed
  close $self->handle;
  delete $self->{handle};

  # Move
  my $src = $self->path;
  File::Copy::move($src, $path)
    or croak qq/Can't move file "$src" to "$path": $!/;
  $self->path($path);

  # Don't clean up a moved file
  $self->cleanup(0);

  return $self;
}

sub size {
  my $self = shift;

  # File size
  my $file = $self->path;
  return -s $file if $file;

  return 0;
}

sub slurp {
  my $self = shift;

  # Seek to start
  $self->handle->sysseek(0, SEEK_SET);

  # Slurp
  my $content = '';
  while ($self->handle->sysread(my $buffer, 131072)) { $content .= $buffer }

  return $content;
}

1;
__END__

=head1 NAME

Mojo::Asset::File - File storage for HTTP 1.1 content

=head1 SYNOPSIS

  use Mojo::Asset::File;

  my $file = Mojo::Asset::File->new;
  $file->add_chunk('foo bar baz');
  say $file->slurp;

  my $file = Mojo::Asset::File->new(path => '/foo/bar/baz.txt');
  say $file->slurp;

=head1 DESCRIPTION

L<Mojo::Asset::File> is a file storage backend for HTTP 1.1 content.

=head1 ATTRIBUTES

L<Mojo::Asset::File> inherits all attributes from L<Mojo::Asset> and
implements the following new ones.

=head2 C<cleanup>

  my $cleanup = $file->cleanup;
  $file       = $file->cleanup(1);

Delete file automatically once it's not used anymore.

=head2 C<handle>

  my $handle = $file->handle;
  $file      = $file->handle(IO::File->new);

Actual file handle.

=head2 C<path>

  my $path = $file->path;
  $file    = $file->path('/foo/bar/baz.txt');

Actual file path.

=head2 C<tmpdir>

  my $tmpdir = $file->tmpdir;
  $file      = $file->tmpdir('/tmp');

Temporary directory.

=head1 METHODS

L<Mojo::Asset::File> inherits all methods from L<Mojo::Asset> and implements
the following new ones.

=head2 C<add_chunk>

  $file = $file->add_chunk('foo bar baz');

Add chunk of data.

=head2 C<contains>

  my $position = $file->contains('bar');

Check if asset contains a specific string.

=head2 C<get_chunk>

  my $chunk = $file->get_chunk($start);

Get chunk of data starting from a specific position.

=head2 C<is_file>

  my $true = $file->is_file;

True.

=head2 C<move_to>

  $file = $file->move_to('/foo/bar/baz.txt');

Move asset data into a specific file.

=head2 C<size>

  my $size = $file->size;

Size of asset data in bytes.

=head2 C<slurp>

  my $string = $file->slurp;

Read all asset data at once.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
