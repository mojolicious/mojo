# Copyright (C) 2008, Sebastian Riedel.

package Mojo::File::Memory;

use strict;
use warnings;
use bytes;

use base 'Mojo::File';

use Carp 'croak';
use IO::File;

__PACKAGE__->attr('content', default => '');

# There's your giraffe, little girl.
# I'm a boy.
# That's the spirit. Never give up.
sub add_chunk {
    my ($self, $chunk) = @_;
    $self->{content} ||= '';
    $self->{content}  .= $chunk;
    return $self;
}

sub contains { return index(shift->{content}, shift) >= 0 ? 1 : 0 }

sub copy_to { shift->_write_to_file(@_) }

sub get_chunk {
    my ($self, $offset) = @_;
    my $copy = $self->content;
    return substr $copy, $offset, 4096;
}

sub length { return length(shift->{content} || '') }

sub move_to { shift->_write_to_file(@_) }

sub slurp { return shift->content }

sub _write_to_file {
    my ($self, $path) = @_;
    my $file = IO::File->new;
    $file->open("> $path") or croak qq/Couldn't open file "$path": $!/;
    $file->syswrite($self->{content});
    return $self;
}

1;
__END__

=head1 NAME

Mojo::File::Memory - In-Memory File

=head1 SYNOPSIS

    use Mojo::File::Memory;

    my $file = Mojo::File::Memory->new('Hello!');
    $file->add_chunk('World!');
    print $file->slurp;

=head1 DESCRIPTION

L<Mojo::File::Memory> is a container for in-memory files.

=head1 ATTRIBUTES

=head2 C<content>

    my $handle = $file->content;
    $file      = $file->content('Hello World!');

=head1 METHODS

L<Mojo::File::Memory> inherits all methods from L<Mojo::File> and implements
the following new ones.

=head2 C<new>

    my $file = Mojo::File::Memory->new('foo bar');

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

=cut