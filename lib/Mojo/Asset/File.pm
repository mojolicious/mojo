# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Asset::File;

use strict;
use warnings;

use base 'Mojo::Asset';
use bytes;

# We can't use File::Temp because there is no seek support in the version
# shipped with Perl 5.8
use Carp 'croak';
use File::Copy ();
use File::Spec;
use IO::File;
use Mojo::ByteStream 'b';

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 4096;

__PACKAGE__->attr([qw/cleanup path/]);
__PACKAGE__->attr(tmpdir => sub { $ENV{MOJO_TMPDIR} || File::Spec->tmpdir });
__PACKAGE__->attr(
    handle => sub {
        my $self   = shift;
        my $handle = IO::File->new;

        # Already got a file without handle
        my $file = $self->path;
        if ($file) {

            # New file
            my $mode = '+>';

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
            my $sum = b(time . rand(999999999))->md5_sum;
            $file = "$base.$sum";
        }
        $self->path($file);

        # Enable automatic cleanup
        $self->cleanup(1);

        # Open for read/write access
        $handle->open("+> $file") or croak qq/Can't open file "$file": $!/;
        return $handle;
    }
);

sub DESTROY {
    my $self = shift;
    my $file = $self->path;

    # Cleanup
    unlink $file if $self->cleanup && -f $file;
}

sub add_chunk {
    my ($self, $chunk) = @_;

    # Seek to end
    $self->handle->seek(0, SEEK_END);

    # Store
    $chunk = '' unless defined $chunk;
    $self->handle->syswrite($chunk, length $chunk);

    return $self;
}

sub contains {
    my ($self, $bytestream) = @_;
    my ($buffer, $window);

    # Seek to start
    $self->handle->seek(0, SEEK_SET);

    # Read
    my $read = $self->handle->sysread($window, length($bytestream) * 2);
    my $offset = $read;

    # Moving window search
    while ($offset <= $self->size) {
        $read = $self->handle->sysread($buffer, length($bytestream));
        $offset += $read;
        $window .= $buffer;
        my $pos = index $window, $bytestream;
        return $pos if $pos >= 0;
        return if $read == 0;
        substr $window, 0, $read, '';
    }

    return;
}

sub get_chunk {
    my ($self, $offset) = @_;

    # Seek to start
    $self->handle->seek($offset, SEEK_SET);

    # Read
    $self->handle->sysread(my $buffer, CHUNK_SIZE);
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
    $self->handle->seek(0, SEEK_SET);

    # Slurp
    my $content = '';
    while ($self->handle->sysread(my $buffer, CHUNK_SIZE)) {
        $content .= $buffer;
    }

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

=head2 C<handle>

    my $handle = $asset->handle;
    $asset     = $asset->handle(IO::File->new);

=head2 C<path>

    my $path = $asset->path;
    $asset   = $asset->path('/foo/bar/baz.txt');

=head2 C<tmpdir>

    my $tmpdir = $asset->tmpdir;
    $asset     = $asset->tmpdir('/tmp');

=head1 METHODS

L<Mojo::Asset::File> inherits all methods from L<Mojo::Asset> and implements
the following new ones.

=head2 C<add_chunk>

    $asset = $asset->add_chunk('foo bar baz');

=head2 C<contains>

    my $position = $asset->contains('bar');

=head2 C<get_chunk>

    my $chunk = $asset->get_chunk($offset);

=head2 C<move_to>

    $asset = $asset->move_to('/foo/bar/baz.txt');

=head2 C<size>

    my $size = $asset->size;

=head2 C<slurp>

    my $string = $file->slurp;

=cut
