# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::File;

use strict;
use warnings;

use base 'Mojo::Base';
use bytes;

# We can't use File::Temp because there is no seek support in the version
# shipped with Perl 5.8
use Carp 'croak';
use File::Copy ();
use File::Spec;
use IO::File;
use Mojo::ByteStream 'b';

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 4096;
use constant TMPDIR     => $ENV{MOJO_TMPDIR}     || File::Spec->tmpdir;

__PACKAGE__->attr([qw/cleanup path/]);
__PACKAGE__->attr(
    'handle',
    default => sub {
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
        my $base = File::Spec->catfile(TMPDIR, 'mojo.tmp');
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

    # Shortcut
    return unless $chunk;

    # Seek to end
    $self->handle->seek(0, SEEK_END);

    # Store
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
    while ($offset < $self->length) {
        $read = $self->handle->sysread($buffer, length($bytestream));
        $offset += $read;
        $window .= $buffer;
        my $pos = index $window, $bytestream;
        return $pos if $pos >= 0;
        substr $window, 0, $read, '';
    }

    return;
}

sub copy_to {
    my ($self, $path) = @_;
    my $src = $self->path;

    # Copy
    File::Copy::copy($src, $path)
      or croak qq/Can't copy file "$src" to "$path": $!/;

    return $self;
}

sub get_chunk {
    my ($self, $offset) = @_;

    # Seek to start
    $self->handle->seek($offset, SEEK_SET);

    # Read
    $self->handle->sysread(my $buffer, CHUNK_SIZE);
    return $buffer;
}

sub length {
    my $self = shift;

    # File size
    my $file = $self->path;
    return -s $file if $file;

    return 0;
}

sub move_to {
    my ($self, $path) = @_;
    my $src = $self->path;

    # Move
    File::Copy::move($src, $path)
      or croak qq/Can't move file "$src" to "$path": $!/;

    return $self;
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

Mojo::File - File

=head1 SYNOPSIS

    use Mojo::File;

    my $file = Mojo::File->new;
    $file->add_chunk('World!');
    print $file->slurp;

    my $file = Mojo::File->new(path => '/foo/bar.txt');
    print $file->slurp;

=head1 DESCRIPTION

L<Mojo::File> is a container for files.

=head1 ATTRIBUTES

L<Mojo::File> implements the following attributes.

=head2 C<cleanup>

    my $cleanup = $file->cleanup;
    $file       = $file->cleanup(1);

=head2 C<handle>

    my $handle = $file->handle;
    $file      = $file->handle(IO::File->new);

=head2 C<path>

    my $path = $file->path;
    $file    = $file->path('/foo/bar.txt');

=head1 METHODS

L<Mojo::File> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<add_chunk>

    $file = $file->add_chunk('test 123');

=head2 C<contains>

    my $position = $file->contains('random string');

=head2 C<copy_to>

    $file = $file->copy_to('/foo/bar/baz.txt');

=head2 C<get_chunk>

    my $chunk = $file->get_chunk($offset);

=head2 C<length>

    my $length = $file->length;

=head2 C<move_to>

    $file = $file->move_to('/foo/bar/baz.txt');

=head2 C<slurp>

    my $string = $file->slurp;

=cut
