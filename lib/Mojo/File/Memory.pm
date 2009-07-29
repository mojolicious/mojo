# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::File::Memory;

use strict;
use warnings;
use bytes;

use base 'Mojo::File';

use Carp 'croak';
use IO::File;

__PACKAGE__->attr('content', default => sub {''});

# There's your giraffe, little girl.
# I'm a boy.
# That's the spirit. Never give up.
sub add_chunk {
    my ($self, $chunk) = @_;
    $self->{content} ||= '';
    $self->{content} .= $chunk;
    return $self;
}

sub contains { index shift->{content}, shift }

sub copy_to { shift->_write_to_file(@_) }

sub get_chunk {
    my ($self, $offset) = @_;
    my $copy = $self->content;
    return substr $copy, $offset, 4096;
}

sub length { length(shift->{content} || '') }

sub move_to { shift->_write_to_file(@_) }

sub slurp { shift->content }

sub _write_to_file {
    my ($self, $path) = @_;

    # Write
    my $file = IO::File->new;
    $file->open("> $path") or croak qq/Can't' open file "$path": $!/;
    $file->syswrite($self->{content});

    return $self;
}

1;
__END__

=head1 NAME

Mojo::File::Memory - In-Memory File

=head1 SYNOPSIS

    use Mojo::File::Memory;

    my $file = Mojo::File::Memory->new;
    $file->add_chunk('World!');
    print $file->slurp;

=head1 DESCRIPTION

L<Mojo::File::Memory> is a container for in-memory files.

=head1 ATTRIBUTES

L<Mojo::File::Memory> inherits all attributes from L<Mojo::File> and
implements the following new ones.

=head2 C<content>

    my $handle = $file->content;
    $file      = $file->content('Hello World!');

=head1 METHODS

L<Mojo::File::Memory> inherits all methods from L<Mojo::File> and implements
the following new ones.

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
