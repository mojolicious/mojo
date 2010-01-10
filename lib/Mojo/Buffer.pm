# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Buffer;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;
use bytes;

__PACKAGE__->attr(raw_size => 0);

sub new {
    my $self = shift->SUPER::new(@_);
    $self->{buffer} = '';
    return $self;
}

sub add_chunk {
    my ($self, $chunk) = @_;

    # Shortcut
    return $self unless defined $chunk;

    # Raw length
    $self->raw_size($self->raw_size + length $chunk);

    # Store
    $self->{buffer} .= $chunk;

    return $self;
}

sub contains { index shift->{buffer}, shift }

sub empty {
    my $self = shift;

    # Cleanup
    my $buffer = $self->{buffer};
    $self->{buffer} = '';

    return $buffer;
}

sub get_line {
    my $self = shift;

    # No full line in buffer
    return unless $self->{buffer} =~ /\x0d?\x0a/;

    # Locate line ending
    my $pos = index $self->{buffer}, "\x0a";

    # Extract line and ending
    my $line = substr $self->{buffer}, 0, $pos + 1, '';
    $line =~ s/(\x0d?\x0a)\z//;

    return $line;
}

sub remove {
    my ($self, $length, $chunk) = @_;

    # Chunk to replace?
    $chunk = '' unless defined $chunk;

    # Extract and replace
    return substr $self->{buffer}, 0, $length, $chunk;
}

sub size { length shift->{buffer} }

sub to_string { shift->{buffer} }

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

=head2 C<raw_size>

    my $size = $buffer->raw_size;
    $buffer  = $buffer->raw_size(23);

=head1 METHODS

L<Mojo::Buffer> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

    my $buffer = Mojo::Buffer->new;

=head2 C<add_chunk>

    $buffer = $buffer->add_chunk('foo');

=head2 C<contains>

    my $position = $buffer->contains('something');

=head2 C<empty>

    my $chunk = $buffer->empty;

=head2 C<get_line>

   my $line = $buffer->get_line;

=head2 C<remove>

    my $chunk = $buffer->remove(4);
    my $chunk = $buffer->remove(4, 'abcd');

=head2 C<size>

    my $size = $buffer->size;

=head2 C<to_string>

    my $string = $buffer->to_string;
    my $string = "$buffer";

=cut
