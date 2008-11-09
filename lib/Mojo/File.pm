# Copyright (C) 2008, Sebastian Riedel.

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
use Mojo::ByteStream;

use constant TMPDIR => $ENV{MOJO_TMPDIR} || File::Spec->tmpdir;

__PACKAGE__->attr('cleanup', chained => 1);
__PACKAGE__->attr('handle',
    chained => 1, 
    default => sub {
        my $self = shift;
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
              or die qq/Can't open file "$file": $!/;
            return $handle;
        }

        # Generate temporary file
        my $base = File::Spec->catfile(TMPDIR, 'mojo.tmp');
        $file = $base;
        while (-e $file) {
            my $sum = Mojo::ByteStream->new(time . rand(999999999))->md5_sum;
            $file = "$base.$sum";
        }

        $self->path($file);
        $self->cleanup(1);

        # Open for read/write access
        $handle->open("+> $file") or die qq/Can't open file "$file": $!/;
        return $handle;
    }
);

sub DESTROY {
    my $self = shift;
    my $file = $self->path;
    unlink $file if $self->cleanup && -f $file;
}

# Hi, Super Nintendo Chalmers!
sub new {
    my $self = shift->SUPER::new();
    $self->add_chunk(join '', @_) if @_;
    return $self;
}

sub add_chunk {
    my $self  = shift;
    my $chunk = join '', @_ if @_;

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
        return 1 if $pos >= 0;
        substr $window, 0, $read, '';
    }

    return 0;
}

sub copy_to {
    my ($self, $path) = @_;
    my $src = $self->path;
    File::Copy::copy($src, $path)
      || croak qq/Couldn't copy file "$src" to "$path": $!/;
    return $self;
}

sub get_chunk {
    my ($self, $offset) = @_;

    # Seek to start
    $self->handle->seek($offset, SEEK_SET);

    # Read
    $self->handle->sysread(my $buffer, 4096);
    return $buffer;
}

sub length {
    my $self = shift;

    my $file = $self->path;
    return -s $file if $file;

    return 0;
}

sub move_to {
    my ($self, $path) = @_;
    my $src = $self->path;
    File::Copy::move($src, $path)
      || croak qq/Couldn't move file "$src" to "$path": $!/;
    return $self;
}

sub path {
    my ($self, $file) = @_;

    # Set
    if ($file) {
        $self->{path} = $file;
        return $self;
    }

    # Get
    return $self->{path};
}

sub slurp {
    my $self = shift;

    # Seek to start
    $self->handle->seek(0, SEEK_SET);

    # Slurp
    my $content = '';
    while ($self->handle->sysread(my $buffer, 4096)) {
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

    my $file = Mojo::File->new('Hello!');
    $file->add_chunk('World!');
    print $file->slurp;

=head1 DESCRIPTION

L<Mojo::File> is a container for files.

=head1 ATTRIBUTES

=head2 C<cleanup>

    my $cleanup = $file->cleanup;
    $file       = $file->cleanup(1);

=head2 C<handle>

    my $handle = $file->handle;
    $file      = $file->handle(IO::File->new);

Returns a L<IO::File> object representing a file upload if called without
arguments.
Returns the invocant if called with arguments.

=head2 C<path>

    my $path = $file->path;
    $file    = $file->path('/foo/bar.txt');

=head1 METHODS

L<Mojo::File> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $file = Mojo::File->new('Hello World!');

=head2 C<add_chunk>

    $file = $file->add_chunk('test 123');

=head2 C<contains>

    my $contains = $file->contains('random string');

=head2 C<copy_to>

    $file = $file->copy_to('/foo/bar/baz.txt');

Copies the uploaded file contents to the given path and returns the invocant.

=head2 C<get_chunk>

    my $chunk = $file->get_chunk($offset);

=head2 C<length>

    my $length = $file->length;

=head2 C<move_to>

    $file = $file->move_to('/foo/bar/baz.txt');

Moves the uploaded file contents to the given path and returns the invocant.

=head2 C<slurp>

    my $string = $file->slurp;

Returns the entire file content as a string.

=cut