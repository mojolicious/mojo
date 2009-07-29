# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Buffer;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;
use bytes;

__PACKAGE__->attr('raw_length', default => 0);

sub add_chunk {
    my ($self, $chunk) = @_;

    # Raw length
    $self->raw_length($self->raw_length + length $chunk);

    # Store
    $self->{_buffer} .= $chunk;

    return $self;
}

sub contains {
    my ($self, $chunk) = @_;

    # Search
    return index $self->{_buffer}, $chunk;
}

sub empty {
    my $self = shift;

    # Cleanup
    my $buffer = $self->{_buffer};
    $self->{_buffer} = '';

    return $buffer;
}

sub get_line {
    my $self = shift;

    # No full line in buffer
    return unless $self->{_buffer} =~ /\x0d?\x0a/;

    # Locate line ending
    my $pos = index $self->{_buffer}, "\x0a";

    # Extract line and ending
    my $line = substr $self->{_buffer}, 0, $pos + 1, '';
    $line =~ s/(\x0d?\x0a)\z//;

    return $line;
}

sub length {
    my $self = shift;
    $self->{_buffer} ||= '';
    return length $self->{_buffer};
}

sub remove {
    my ($self, $length, $chunk) = @_;

    # Chunk to replace?
    $chunk ||= '';

    # Extract and replace
    $self->{_buffer} ||= '';
    return substr $self->{_buffer}, 0, $length, $chunk;
}

sub to_string { shift->{_buffer} || '' }

1;
__END__

=head1 NAME

Mojo::Buffer - A Simple In-Memory Buffer

=head1 SYNOPSIS

    use Mojo::Buffer;

    my $buffer = Mojo::Buffer->new;
    $buffer->add_chunk('bar');
    my $foo = $buffer->remove(3);
    my $bar = $buffer->empty;

=head1 DESCRIPTION

L<Mojo::Buffer> is a simple in-memory buffer.

=head1 ATTRIBUTES

L<Mojo::Buffer> implements the following attributes.

=head2 C<raw_length>

    my $length = $buffer->raw_length;
    $buffer    = $buffer->raw_length;

=head1 METHODS

L<Mojo::Buffer> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

    my $buffer = Mojo::Buffer->new;
    my $buffer = Mojo::Buffer->new('foobarbaz');

=head2 C<add_chunk>

    $buffer = $buffer->add_chunk('foo');

=head2 C<contains>

    my $position = $buffer->contains('something');

=head2 C<empty>

    my $chunk = $buffer->empty;

=head2 C<get_line>

   my $line = $buffer->get_line;

=head2 C<length>

    my $length = $buffer->length;

=head2 C<remove>

    my $chunk = $buffer->remove(4);
    my $chunk = $buffer->remove(4, 'abcd');

=head2 C<to_string>

    my $string = $buffer->to_string;
    my $string = "$buffer";

=cut
