# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Content;

use strict;
use warnings;

use base 'Mojo::Stateful';
use bytes;

use Mojo::Buffer;
use Mojo::Filter::Chunked;
use Mojo::File;
use Mojo::File::Memory;
use Mojo::Content::MultiPart;
use Mojo::Headers;

use constant MAX_MEMORY_SIZE => $ENV{MOJO_MAX_MEMORY_SIZE} || 10240;

__PACKAGE__->attr(
    [qw/buffer filter_buffer/] => (default => sub { Mojo::Buffer->new }));
__PACKAGE__->attr([qw/body_cb filter builder_progress_cb/]);
__PACKAGE__->attr(file    => (default => sub { Mojo::File::Memory->new }));
__PACKAGE__->attr(headers => (default => sub { Mojo::Headers->new }));
__PACKAGE__->attr([qw/raw_header_length relaxed/] => (default => 0));

sub build_body {
    my $self = shift;

    my $body   = '';
    my $offset = 0;
    while (1) {
        my $chunk = $self->get_body_chunk($offset);

        # No content yet, try again
        next unless defined $chunk;

        # End of content
        last unless length $chunk;

        # Content
        $offset += length $chunk;
        $body .= $chunk;
    }

    return $body;
}

sub build_headers {
    my $self = shift;

    my $headers = '';
    my $offset  = 0;
    while (1) {
        my $chunk = $self->get_header_chunk($offset);

        # No headers yet, try again
        next unless defined $chunk;

        # End of headers
        last unless length $chunk;

        # Headers
        $offset += length $chunk;
        $headers .= $chunk;
    }

    return $headers;
}

sub body_contains {
    my ($self, $chunk) = @_;
    return $self->file->contains($chunk);
}

sub body_length { shift->file->length }

sub get_body_chunk {
    my ($self, $offset) = @_;

    # Progress
    $self->builder_progress_cb->($self, 'body', $offset)
      if $self->builder_progress_cb;

    # Body generator
    return $self->body_cb->($self, $offset) if $self->body_cb;

    # Normal content
    return $self->file->get_chunk($offset);
}

sub get_header_chunk {
    my ($self, $offset) = @_;

    # Normal headers
    my $copy = $self->_build_headers;
    return substr($copy, $offset, 4096);
}

sub has_leftovers {
    my $self = shift;
    return 1 if $self->buffer->length || $self->filter_buffer->length;
    return 0;
}

sub header_length { length shift->build_headers }

sub is_chunked {
    my $self = shift;
    my $encoding = $self->headers->transfer_encoding || '';
    return $encoding =~ /chunked/i ? 1 : 0;
}

sub is_multipart {
    my $self = shift;
    my $type = $self->headers->content_type || '';
    return $type =~ /multipart/i ? 1 : 0;
}

sub leftovers {
    my $self = shift;

    # Chunked leftovers are in the filter buffer, and so are those from a
    # HEAD request
    return $self->filter_buffer->to_string if $self->filter_buffer->length;

    # Normal leftovers
    return $self->buffer->to_string;
}

sub parse {
    my $self = shift;

    # Buffer
    $self->filter_buffer->add_chunk(join '', @_) if @_;

    # Parse headers
    $self->parse_until_body;

    # Still parsing headers
    return $self if $self->is_state('headers');

    # Chunked, need to filter
    if ($self->is_chunked && !$self->is_state('headers')) {

        # Initialize filter
        $self->filter(
            Mojo::Filter::Chunked->new(
                headers       => $self->headers,
                input_buffer  => $self->filter_buffer,
                output_buffer => $self->buffer
            )
        ) unless $self->filter;

        # Filter
        $self->filter->parse;
        $self->done if $self->filter->is_done;
    }

    # Not chunked, pass through
    else { $self->buffer($self->filter_buffer) }

    # Content needs to be upgraded to multipart
    if ($self->is_multipart) {

        # Shortcut
        return $self if $self->isa('Mojo::Content::MultiPart');

        # Need to upgrade
        return Mojo::Content::MultiPart->new($self)->parse;
    }

    # Chunked body or relaxed content
    if ($self->is_chunked || $self->relaxed) {
        $self->file->add_chunk($self->buffer->empty);
    }

    # Normal body
    else {

        # Slurp
        my $length = $self->headers->content_length || 0;
        my $need = $length - $self->file->length;
        $self->file->add_chunk($self->buffer->remove($need)) if $need > 0;

        # Done
        $self->done if $length <= $self->raw_body_length;
    }

    # With leftovers, maybe pipelined
    if ($self->is_done) {
        $self->state('done_with_leftovers') if $self->has_leftovers;
    }

    return $self;
}

sub parse_until_body {
    my $self = shift;

    # Buffer
    $self->filter_buffer->add_chunk(join '', @_) if @_;

    # Parser started
    if ($self->is_state('start')) {
        my $length            = length($self->filter_buffer->{buffer});
        my $raw_length        = $self->filter_buffer->raw_length;
        my $raw_header_length = $raw_length - $length;
        $self->raw_header_length($raw_header_length);
        $self->state('headers');
    }

    # Parse headers
    $self->_parse_headers if $self->is_state('headers');

    return $self;
}

sub raw_body_length {
    my $self          = shift;
    my $length        = $self->filter_buffer->raw_length;
    my $header_length = $self->raw_header_length;
    return $length - $header_length;
}

sub _build_headers {
    my $self    = shift;
    my $headers = $self->headers->to_string;
    return "\x0d\x0a" unless $headers;
    return "$headers\x0d\x0a\x0d\x0a";
}

sub _parse_headers {
    my $self = shift;

    $self->headers->buffer($self->filter_buffer);
    $self->headers->parse;

    my $length            = length($self->headers->buffer->{buffer});
    my $raw_length        = $self->headers->buffer->raw_length;
    my $raw_header_length = $raw_length - $length;

    $self->raw_header_length($raw_header_length);

    # Make sure we don't waste memory
    if ($self->file->isa('Mojo::File::Memory')) {
        $self->file(Mojo::File->new)
          if !$self->headers->content_length
              || $self->headers->content_length > MAX_MEMORY_SIZE;
    }

    $self->state('body') if $self->headers->is_done;
}

1;
__END__

=head1 NAME

Mojo::Content - Content

=head1 SYNOPSIS

    use Mojo::Content;

    my $content = Mojo::Content->new;
    $content->parse("Content-Length: 12\r\n\r\nHello World!");

=head1 DESCRIPTION

L<Mojo::Content> is a container for HTTP content.

=head1 ATTRIBUTES

L<Mojo::Content> inherits all attributes from L<Mojo::Stateful> and
implements the following new ones.

=head2 C<body_cb>

    my $cb = $content->body_cb;

    $counter = 1;
    $content = $content->body_cb(sub {
        my $self  = shift;
        my $chunk = '';
        $chunk    = "hello world!" if $counter == 1;
        $chunk    = "hello world2!\n\n" if $counter == 2;
        $counter++;
        return $chunk;
    });

=head2 C<body_length>

    my $body_length = $content->body_length;

=head2 C<buffer>

    my $buffer = $content->buffer;
    $content   = $content->buffer(Mojo::Buffer->new);

=head2 C<builder_progress_cb>

    my $cb   = $content->builder_progress_cb;
    $content = $content->builder_progress_cb(sub {
        my $self = shift;
        print '+';
    });

=head2 C<file>

    my $file = $content->file;
    $content = $content->file(Mojo::File::Memory->new);

=head2 C<filter_buffer>

    my $filter_buffer = $content->filter_buffer;
    $content          = $content->filter_buffer(Mojo::Buffer->new);

=head2 C<header_length>

    my $header_length = $content->header_length;

=head2 C<headers>

    my $headers = $content->headers;
    $content    = $content->headers(Mojo::Headers->new);

=head2 C<raw_header_length>

    my $raw_header_length = $content->raw_header_length;

=head2 C<raw_body_length>

    my $raw_body_length = $content->raw_body_length;

=head2 C<relaxed>

    my $relaxed = $content->relaxed;
    $content    = $content->relaxed(1);

=head1 METHODS

L<Mojo::Content> inherits all methods from L<Mojo::Stateful> and implements
the following new ones.

=head2 C<build_body>

    my $string = $content->build_body;

=head2 C<build_headers>

    my $string = $content->build_headers;

=head2 C<body_contains>

    my $found = $content->body_contains;

=head2 C<get_body_chunk>

    my $chunk = $content->get_body_chunk(0);

=head2 C<get_header_chunk>

    my $chunk = $content->get_header_chunk(13);

=head2 C<has_leftovers>

    my $leftovers = $content->has_leftovers;

=head2 C<is_chunked>

    my $chunked = $content->is_chunked;

=head2 C<is_multipart>

    my $multipart = $content->is_multipart;

=head2 C<leftovers>

    my $bytes = $content->leftovers;

=head2 C<parse>

    $content = $content->parse("Content-Length: 12\r\n\r\nHello World!");

=head2 C<parse_until_body>

    $content = $content->parse_until_body(
        "Content-Length: 12\r\n\r\nHello World!"
    );

=cut
