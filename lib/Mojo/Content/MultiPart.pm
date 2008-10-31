# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Content::MultiPart;

use strict;
use warnings;

use base 'Mojo::Content';
use bytes;

use Mojo::ByteStream;
use Mojo::File;

__PACKAGE__->attr('parts', chained => 1, default => sub { [] });

sub body_contains {
    my ($self, $bytestream) = @_;

    # Check parts
    my $found = 0;
    for my $part (@{$self->parts}) {
        my $headers = $part->build_headers;
        $found += 1 if $headers =~ /$bytestream/g;
        $found += $part->body_contains($bytestream);
    }
    return $found ? 1 : 0;
}

sub body_length {
    my $self = shift;

    my $length = 0;

    # Check for Content-Lenght header
    my $content_length = $self->headers->content_length;
    return $content_length if $content_length;

    # Boundary
    my $boundary = $self->build_boundary;

    # Calculate length of whole body
    my $boundary_length = length($boundary) + 6;
    $length += $boundary_length;
    for my $part (@{$self->parts}) {
        $length += $part->header_length;
        $length += $part->body_length;
        $length += $boundary_length;
    }

    return $length;
}

sub build_boundary {
    my $self = shift;

    # Check for existing boundary
    ($self->headers->content_type || '') =~ /boundary=\"?([^\s\"]+)\"?/i;
    my $boundary = $1;
    return $boundary if $boundary;

    # Generate and check boundary
    my $size = 1;
    while (1) {

        # Mostly taken from LWP
        $boundary = Mojo::ByteStream->new(
          join('', map chr(rand(256)), 1..$size * 3)
        )->b64_encode;
        $boundary =~ s/\W/X/g;

        # Check parts for boundary
        last unless $self->body_contains($boundary);
        $size++;
    }

    # Add boundary to Content-Type header
    ($self->headers->content_type || '') =~ /^(.*multipart\/[^;]+)(.*)$/;
    my $before = $1 || 'multipart/mixed';
    my $after = $2 || '';
    $self->headers->content_type("$before; boundary=$boundary$after");

    return $boundary;
}

sub get_body_chunk {
    my ($self, $offset) = @_;

    # Body generator
    return $self->build_body_cb->($self, $offset) if $self->build_body_cb;

    # Multipart
    my $boundary = $self->build_boundary;
    my $boundary_length = length($boundary) + 6;
    my $length = $boundary_length;

    # First boundary
    return substr "\x0d\x0a--$boundary\x0d\x0a", $offset
      if $length > $offset;

    # Parts
    for (my $i = 0; $i < @{$self->parts}; $i++) {
        my $part = $self->parts->[$i];

        # Headers
        my $header_length = $part->header_length;
        return $part->get_header_chunk($offset - $length)
          if ($length + $header_length) > $offset;
        $length += $header_length;

        # Content
        my $content_length = $part->body_length;
        return $part->get_body_chunk($offset - $length)
          if ($length + $content_length) > $offset;
        $length += $content_length;

        # Boundary
        if (($length + $boundary_length) > $offset) {

            # Last boundary
            return substr "\x0d\x0a--$boundary--", $offset - $length
              if $#{$self->parts} == $i;

            # Middle boundary
            return substr "\x0d\x0a--$boundary\x0d\x0a", $offset - $length;
        }
        $length += $boundary_length;
    }
}

sub parse {
    my $self = shift;

    # Upgrade state
    $self->state('multipart_preamble') if $self->is_state('body');

    # Parse headers and filter body
    $self->SUPER::parse(@_);

    $self->_parse_multipart;

    return $self;
}

sub _parse_multipart {
    my $self = shift;

    # We need a boundary
    $self->headers->content_type
      =~ /.*boundary=\"*([a-zA-Z0-9\'\(\)\,\.\:\?\-\_\+\/]+).*/;
    my $boundary = $1;

    # Boundary missing
    return $self->error('Parser error: Boundary missing or invalid')
      unless $boundary;

    # Spin
    while (1) {

        # Done?
        last if $self->is_state('done', 'error');

        # Preamble
        if ($self->is_state('multipart_preamble')) {
            last unless $self->_parse_multipart_preamble($boundary)
        }

        # Boundary
        elsif ($self->is_state('multipart_boundary')) {
            last unless $self->_parse_multipart_boundary($boundary)
        }

        # Body
        elsif ($self->is_state('multipart_body')) {
            last unless $self->_parse_multipart_body($boundary)
        }
    }
}

sub _parse_multipart_body {
    my ($self, $boundary) = @_;

    my $pos = index $self->buffer->{buffer}, "\x0d\x0a--$boundary";

    # Make sure we have enough buffer to detect end boundary
    if ($pos < 0) {
        my $length =
          length($self->buffer->{buffer}) - (length($boundary) + 8);
        return 0 unless $length > 0;

        # Store chunk
        my $chunk = substr $self->buffer->{buffer}, 0, $length, '';
        $self->parts->[-1] = $self->parts->[-1]->parse($chunk);
        return 0;
    }

    # Store chunk
    my $chunk = substr $self->buffer->{buffer}, 0, $pos, '';
    $self->parts->[-1] = $self->parts->[-1]->parse($chunk);
    $self->state('multipart_boundary');
    return 1;
}

sub _parse_multipart_boundary {
    my ($self, $boundary) = @_;

    # Begin
    if (index($self->buffer->{buffer}, "\x0d\x0a--$boundary\x0d\x0a") == 0) {
        substr $self->buffer->{buffer}, 0, length($boundary) + 6, '';
        push @{$self->parts}, Mojo::Content->new;
        $self->state('multipart_body');
        return 1;
    }

    # End
    if (index($self->buffer->{buffer}, "\x0d\x0a--$boundary--") == 0) {
        $self->buffer->empty;
        $self->done;
    }

    return 0;
}

sub _parse_multipart_preamble {
    my ($self, $boundary) = @_;

    # Replace preamble with CRLF
    my $pos = index $self->buffer->{buffer}, "--$boundary";
    unless ($pos < 0) {
        substr $self->buffer->{buffer}, 0, $pos, "\x0d\x0a";
        $self->state('multipart_boundary');
        return 1;
    }
    return 0;
}

1;
__END__

=head1 NAME

Mojo::Content::MultiPart - MultiPart Content

=head1 SYNOPSIS

    use Mojo::Content::MultiPart;

    my $content = Mojo::Content::MultiPart->new;
    $content->parse('Content-Type: multipart/mixed; boundary=---foobar');
    my $part = $content->parts->[4];

=head1 DESCRIPTION

L<Mojo::Content::MultiPart> is a container for HTTP multipart content.

=head1 ATTRIBUTES

L<Mojo::Content::MultiPart> inherits all attributes from L<Mojo::Content>
and implements the following new ones.

=head2 C<parts>

    my $parts = $content->parts;

=head2 C<body_length>

    my $body_length = $content->body_length;

=head1 METHODS

L<Mojo::Content::MultiPart> inherits all methods from L<Mojo::Content> and
implements the following new ones.

=head2 C<body_contains>

    my $found = $content->body_contains('foobarbaz');

=head2 C<build_boundary>

    my $boundary = $content->build_boundary;

=head2 C<get_body_chunk>

    my $chunk = $content->get_body_chunk(0);

=head2 C<parse>

    $content = $content->parse('Content-Type: multipart/mixed');

=cut