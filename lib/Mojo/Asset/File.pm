package Mojo::Asset::File;
use Mojo::Base 'Mojo::Asset';

# We can't use File::Temp because there is no seek support in the version
# shipped with Perl 5.8
use Carp 'croak';
use File::Copy ();
use File::Spec;
use IO::File;
use Mojo::Util 'md5_sum';

has [qw/cleanup path/];
has handle => sub {
    my $self   = shift;
    my $handle = IO::File->new;

    # Already got a file without handle
    my $file = $self->path;
    if ($file) {

        # New file
        my $mode = '+>>';

        # File exists
        $mode = '<' if -s $file;

        # Open
        $handle->open("$mode $file")
          or croak qq/Can't open file "$file": $!/;
        return $handle;
    }

    # Generate temporary file
    my $base = File::Spec->catfile($self->tmpdir, 'mojo.tmp');
    $file = $base;
    while (-e $file) {
        my $sum = md5_sum time . rand 999999999;
        $file = "$base.$sum";
    }
    $self->path($file);

    # Enable automatic cleanup
    $self->cleanup(1);

    # Open for read/write access
    $handle->open("+> $file") or croak qq/Can't open file "$file": $!/;
    return $handle;
};
has tmpdir => sub { $ENV{MOJO_TMPDIR} || File::Spec->tmpdir };

sub DESTROY {
    my $self = shift;
    my $file = $self->path;

    # Cleanup
    unlink $file if $self->cleanup && -f $file;
}

sub add_chunk {
    my ($self, $chunk) = @_;

    # Seek to end
    $self->handle->sysseek(0, SEEK_END);

    # Store
    $chunk = '' unless defined $chunk;
    utf8::encode $chunk if utf8::is_utf8 $chunk;
    $self->handle->syswrite($chunk, length $chunk);

    return $self;
}

sub contains {
    my ($self, $bytestream) = @_;
    my ($buffer, $window);

    # Seek to start
    $self->handle->sysseek($self->start_range, SEEK_SET);
    my $end = defined $self->end_range ? $self->end_range : $self->size;
    my $rlen = length($bytestream) * 2;
    if ($rlen > $end - $self->start_range) {
        $rlen = $end - $self->start_range;
    }

    # Read
    my $read    = $self->handle->sysread($window, $rlen);
    my $offset  = $read;
    my $readlen = length($bytestream);

    # Moving window search
    my $range = $self->end_range;
    while ($offset <= $end) {
        if (defined $range) {
            $readlen = $end + 1 - $offset;
            return -1 if $readlen <= 0;
        }
        $read = $self->handle->sysread($buffer, $readlen);
        $offset += $read;
        $window .= $buffer;
        my $pos = index $window, $bytestream;
        return $pos if $pos >= 0;
        return -1   if $read == 0;
        substr $window, 0, $read, '';
    }

    return -1;
}

sub get_chunk {
    my ($self, $offset) = @_;

    # Seek to start
    my $off = $offset + $self->start_range;
    $self->handle->sysseek($off, SEEK_SET);
    my $end = $self->end_range;
    my $buffer;

    # Chunk size
    my $size = $ENV{MOJO_CHUNK_SIZE} || 262144;

    # Range support
    if (defined $end) {
        my $chunk = $end + 1 - $off;
        return '' if $chunk <= 0;
        $chunk = $size if $chunk > $size;
        $self->handle->sysread($buffer, $chunk);
    }
    else { $self->handle->sysread($buffer, $size) }

    return $buffer;
}

sub move_to {
    my ($self, $path) = @_;
    my $src = $self->path;

    # Close handle
    close $self->handle;
    $self->handle(undef);

    # Move
    File::Copy::move($src, $path)
      or croak qq/Can't move file "$src" to "$path": $!/;

    # Set new path
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
    while ($self->handle->sysread(my $buffer, 262144)) { $content .= $buffer }

    return $content;
}

1;
__END__

=head1 NAME

Mojo::Asset::File - File Asset

=head1 SYNOPSIS

    use Mojo::Asset::File;

    my $asset = Mojo::Asset::File->new;
    $asset->add_chunk('foo bar baz');
    print $asset->slurp;

    my $asset = Mojo::Asset::File->new(path => '/foo/bar/baz.txt');
    print $asset->slurp;

=head1 DESCRIPTION

L<Mojo::Asset::File> is a container for file assets.

=head1 ATTRIBUTES

L<Mojo::Asset::File> implements the following attributes.

=head2 C<cleanup>

    my $cleanup = $asset->cleanup;
    $asset      = $asset->cleanup(1);

Delete file automatically once it's not used anymore.

=head2 C<handle>

    my $handle = $asset->handle;
    $asset     = $asset->handle(IO::File->new);

Actual file handle.

=head2 C<path>

    my $path = $asset->path;
    $asset   = $asset->path('/foo/bar/baz.txt');

Actual file path.

=head2 C<tmpdir>

    my $tmpdir = $asset->tmpdir;
    $asset     = $asset->tmpdir('/tmp');

Temporary directory.

=head1 METHODS

L<Mojo::Asset::File> inherits all methods from L<Mojo::Asset> and implements
the following new ones.

=head2 C<add_chunk>

    $asset = $asset->add_chunk('foo bar baz');

Add chunk of data to asset.

=head2 C<contains>

    my $position = $asset->contains('bar');

Check if asset contains a specific string.

=head2 C<get_chunk>

    my $chunk = $asset->get_chunk($offset);

Get chunk of data starting from a specific position.

=head2 C<move_to>

    $asset = $asset->move_to('/foo/bar/baz.txt');

Move asset data into a specific file.

=head2 C<size>

    my $size = $asset->size;

Size of asset data in bytes.

=head2 C<slurp>

    my $string = $file->slurp;

Read all asset data at once.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
