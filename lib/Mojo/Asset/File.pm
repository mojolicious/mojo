package Mojo::Asset::File;
use Mojo::Base 'Mojo::Asset';

use Carp 'croak';
use Errno 'EEXIST';
use Fcntl qw(O_CREAT O_EXCL O_RDWR);
use File::Copy 'move';
use File::Spec;
use IO::File;
use Mojo::Util 'md5_sum';

has [qw(cleanup path)];
has handle => sub {
  my $self = shift;

  # Open existing file
  my $handle = IO::File->new;
  my $path   = $self->path;
  if (defined $path && -f $path) {
    $handle->open("< $path") or croak qq{Can't open file "$path": $!};
    return $handle;
  }

  # Open new or temporary file
  my $base = File::Spec->catfile($self->tmpdir, 'mojo.tmp');
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
has tmpdir => sub { $ENV{MOJO_TMPDIR} || File::Spec->tmpdir };

# "The only monster here is the gambling monster that has enslaved your
#  mother!
#  I call him Gamblor, and it's time to snatch your mother from his neon
#  claws!"
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
  my ($self, $pattern) = @_;

  # Seek to start
  my $handle = $self->handle;
  $handle->sysseek($self->start_range, SEEK_SET);

  # Calculate window
  my $end = $self->end_range // $self->size;
  my $window_size = length($pattern) * 2;
  $window_size = $end - $self->start_range
    if $window_size > $end - $self->start_range;
  my $read         = $handle->sysread(my $window, $window_size);
  my $offset       = $read;
  my $pattern_size = length $pattern;
  my $range        = $self->end_range;

  # Moving window search
  while ($offset <= $end) {
    return -1 if defined $range && ($pattern_size = $end + 1 - $offset) <= 0;
    $read = $handle->sysread(my $buffer, $pattern_size);
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
  my $handle = $self->handle;
  $handle->sysseek($start, SEEK_SET);

  # Range support
  my $buffer;
  my $size = $ENV{MOJO_CHUNK_SIZE} || 131072;
  if (defined(my $end = $self->end_range)) {
    my $chunk = $end + 1 - $start;
    return '' if $chunk <= 0;
    $chunk = $size if $chunk > $size;
    $handle->sysread($buffer, $chunk);
  }
  else { $handle->sysread($buffer, $size) }

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

Mojo::Asset::File - File storage for HTTP 1.1 content

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

File handle, created on demand.

=head2 C<path>

  my $path = $file->path;
  $file    = $file->path('/home/sri/foo.txt');

File path used to create C<handle>, can also be automatically generated if
necessary.

=head2 C<tmpdir>

  my $tmpdir = $file->tmpdir;
  $file      = $file->tmpdir('/tmp');

Temporary directory used to generate C<path>, defaults to the value of the
C<MOJO_TMPDIR> environment variable or auto detection.

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

  $file = $file->move_to('/home/sri/bar.txt');

Move asset data into a specific file and disable C<cleanup>.

=head2 C<size>

  my $size = $file->size;

Size of asset data in bytes.

=head2 C<slurp>

  my $string = $file->slurp;

Read all asset data at once.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
