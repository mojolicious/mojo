# Copyright (C) 2008, Sebastian Riedel.

package Mojo::File;

use strict;
use warnings;

use base 'Mojo::Base';
use bytes;

# We can't use File::Temp because there is no seek support in the version
# shipped with Perl 5.8
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
        my $file = $self->file_name;
        if ($file) {
            $handle->open("+>> $file") or die qq/Can't open file "$file": $!/;
            return $handle;
        }

        # Generate temporary file
        my $base = File::Spec->catfile(TMPDIR, 'mojo.tmp');
        $file = $base;
        while (-e $file) {
            my $sum = Mojo::ByteStream->new(time . rand(999999999))->md5_sum;
            $file = "$base.$sum";
        }

        $self->file_name($file);
        $self->cleanup(1);

        # Open for read/write access
        $handle->open("+> $file") or die qq/Can't open file "$file": $!/;
        return $handle;
    }
);

sub DESTROY {
    my $self = shift;
    my $file = $self->file_name;
    unlink $file if $self->cleanup && $file;
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
    while ($offset < $self->file_length) {
        $read = $self->handle->sysread($buffer, length($bytestream));
        $offset += $read;
        $window .= $buffer;
        my $pos = index $window, $bytestream;
        return 1 if $pos >= 0;
        substr $window, 0, $read, '';
    }

    return 0;
}

sub file_length {
    my ($self, $length) = @_;

    # Set
    if ($length) {
        $self->{file_length} = $length;
        return $self;
    }

    # User defined
    return $self->{file_length} if $self->{file_length};

    # From file
    my $file = $self->file_name;
    return -s $file if $file;

    # None
    return 0;
}

sub file_name {
    my ($self, $file) = @_;

    # Set
    if ($file) {
        $self->{file_name} = $file;
        return $self;
    }

    # Get
    return $self->{file_name};
}

sub get_chunk {
    my ($self, $offset) = @_;

    # Seek to start
    $self->handle->seek(0, SEEK_SET);

    # Read
    $self->handle->sysread(my $buffer, 4096, $offset);
    return $buffer;
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

=head C<cleanup>

    my $cleanup = $file->cleanup;
    $file       = $file->cleanup(1);

=head2 C<handle>

    my $handle = $file->handle;
    $file      = $file->handle(IO::File->new);

=head2 C<file_length>

    my $file_length = $file->file_length;
    $file           = $file->file_length(9000);

=head2 C<file_name>

    my $file_name = $file->file_name;
    $file         = $file->file_name(9000);

=head1 METHODS

L<Mojo::File> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $file = Mojo::File->new('Hello World!');

=head2 C<add_chunk>

    $file = $file->add_chunk('test 123');

=head2 C<contains>

    my $contains = $file->contains('random string');

=head2 C<get_chunk>

    my $chunk = $file->get_chunk($offset);

=head2 C<slurp>

    my $string = $file->slurp;

=cut