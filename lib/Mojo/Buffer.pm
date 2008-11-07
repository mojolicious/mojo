# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Buffer;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;
use bytes;

__PACKAGE__->attr('raw_length', chained => 1, default => sub { 0 });

sub new {
    my $self = shift->SUPER::new();
    $self->add_chunk(join '', @_) if @_;
    $self->{buffer} ||= '';
    return $self;
}

sub add_chunk {
    my ($self, $chunk) = @_;
    $self->raw_length($self->raw_length + length $chunk);
    $self->{buffer} .= $chunk;
    return $self;
}

sub empty {
    my $self = shift;
    my $buffer = $self->{buffer};
    $self->{buffer} = '';
    return $buffer;
}

sub get_line {
    my $self = shift;

    # No full line in buffer
    return undef unless $self->{buffer} =~ /\x0d?\x0a/;

    # Locate line ending
    my $pos = index $self->{buffer}, "\x0a";

    # Extract line and ending
    my $line = substr $self->{buffer}, 0, $pos + 1, '';
    $line =~ s/(\x0d?\x0a)\z//;

    return $line;
}

sub length {
    my $self = shift;
    $self->{buffer} ||= '';
    return length $self->{buffer};
}

sub remove {
    my ($self, $length) = @_;
    return substr $self->{buffer}, 0, $length, '';
}

sub replace {
    my ($self, $buffer) = @_;
    $self->raw_length(CORE::length($buffer));
    $self->{buffer} = $buffer;
    return $self;
}

sub to_string { return shift->{buffer} || '' }

1;
__END__

=head1 NAME

Mojo::Buffer - Buffer

=head1 SYNOPSIS

    use Mojo::Buffer;

    my $buffer = Mojo::Buffer->new('foo');
    $buffer->add_chunk('bar');
    my $foo = $buffer->remove(3);
    my $bar = $buffer->empty;

=head1 DESCRIPTION

L<Mojo::Buffer> is a simple in-memory buffer.

=head1 ATTRIBUTES

=head2 C<length>

    my $length = $buffer->length;

=head2 C<raw_length>

    my $raw_length = $buffer->raw_length;

=head1 METHODS

L<Mojo::Buffer> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

    my $buffer = Mojo::Buffer->new;
    my $buffer = Mojo::Buffer->new('foobarbaz');

=head2 C<add_chunk>

    $buffer = $buffer->add_chunk('foo');

=head2 C<empty>

    my $string = $buffer->empty;

=head2 C<get_line>

   my $line = $buffer->get_line;

=head2 C<remove>

    my $string = $buffer->remove(4);

=head2 C<replace>

    $buffer = $buffer->replace('foobarbaz');

=head2 C<to_string>

    my $string = $buffer->to_string;

=cut