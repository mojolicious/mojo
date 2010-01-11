# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Content;

use strict;
use warnings;

use base 'Mojo::Stateful';
use bytes;

use Carp 'croak';
use Mojo::Buffer;
use Mojo::Filter::Chunked;
use Mojo::Headers;

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 8192;

__PACKAGE__->attr([qw/body_cb filter progress_cb/]);
__PACKAGE__->attr([qw/buffer filter_buffer/] => sub { Mojo::Buffer->new });
__PACKAGE__->attr(headers                    => sub { Mojo::Headers->new });
__PACKAGE__->attr(raw_header_size            => 0);
__PACKAGE__->attr(relaxed                    => 0);

__PACKAGE__->attr(_body_size => 0);
__PACKAGE__->attr('_eof');

sub body_contains {
    croak 'Method "body_contains" not implemented by subclass';
}

sub body_size { croak 'Method "body_size" not implemented by subclass' }

# Operator! Give me the number for 911!
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

sub generate_body_chunk {
    my ($self, $offset) = @_;

    # Shortcut
    return '' unless $self->body_cb;

    # Remove written
    my $written = $offset - ($self->buffer->raw_size - $self->buffer->size);
    $self->buffer->remove($written);

    # Enough in buffer?
    if (!$self->_eof && $self->buffer->size < CHUNK_SIZE) {

        # Generate
        my $chunk = $self->body_cb->($self, $self->buffer->raw_size);

        # EOF
        if (defined $chunk && !length $chunk) { $self->_eof(1) }

        # Buffer chunk
        else { $self->buffer->add_chunk($chunk) }
    }

    # Get chunk
    my $chunk = $self->buffer->to_string;

    # Pause or EOF
    return $self->_eof ? '' : undef unless length $chunk;

    return $chunk;
}

sub get_body_chunk {
    croak 'Method "get_body_chunk" not implemented by subclass';
}

sub get_header_chunk {
    my ($self, $offset) = @_;

    # Normal headers
    my $copy = $self->_build_headers;
    return substr($copy, $offset, CHUNK_SIZE);
}

sub has_leftovers {
    my $self = shift;
    return 1 if $self->buffer->size || $self->filter_buffer->size;
    return;
}

sub header_size { length shift->build_headers }

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
    return $self->filter_buffer->to_string if $self->filter_buffer->size;

    # Normal leftovers
    return $self->buffer->to_string;
}

sub parse {
    my ($self, $chunk) = @_;

    # Buffer
    $self->filter_buffer->add_chunk($chunk);

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

    # Custom body parser
    if (my $cb = $self->body_cb) {

        # Chunked or relaxed content
        if ($self->is_chunked || $self->relaxed) {
            $self->$cb($self->buffer->empty);
        }

        # Normal content
        else {

            # Need
            my $length = $self->headers->content_length || 0;
            my $need = $length - $self->_body_size;

            # Slurp
            if ($need > 0) {
                my $chunk = $self->buffer->remove($need);
                $self->_body_size($self->_body_size + length $chunk);
                $self->$cb($chunk);
            }

            # Done
            $self->done if $length <= $self->raw_body_size;
        }
    }

    # Leftovers
    if ($self->is_done) {
        $self->state('done_with_leftovers') if $self->has_leftovers;
    }

    return $self;
}

sub parse_until_body {
    my ($self, $chunk) = @_;

    # Buffer
    $self->filter_buffer->add_chunk($chunk);

    # Parser started
    if ($self->is_state('start')) {
        my $length            = $self->filter_buffer->size;
        my $raw_length        = $self->filter_buffer->raw_size;
        my $raw_header_length = $raw_length - $length;
        $self->raw_header_size($raw_header_length);
        $self->state('headers');
    }

    # Parse headers
    $self->_parse_headers if $self->is_state('headers');

    return $self;
}

sub raw_body_size {
    my $self          = shift;
    my $length        = $self->filter_buffer->raw_size;
    my $header_length = $self->raw_header_size;
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

    my $length            = $self->headers->buffer->size;
    my $raw_length        = $self->headers->buffer->raw_size;
    my $raw_header_length = $raw_length - $length;

    $self->raw_header_size($raw_header_length);
    $self->state('body') if $self->headers->is_done;
}

1;
__END__

=head1 NAME

Mojo::Content - HTTP Content Base Class

=head1 SYNOPSIS

    use base 'Mojo::Content';

=head1 DESCRIPTION

L<Mojo::Content> is a HTTP content base class.

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

=head2 C<buffer>

    my $buffer = $content->buffer;
    $content   = $content->buffer(Mojo::Buffer->new);

=head2 C<filter>

    my $filter = $content->filter;
    $content   = $content->filter(Mojo::Filter::Chunked->new);

=head2 C<filter_buffer>

    my $filter_buffer = $content->filter_buffer;
    $content          = $content->filter_buffer(Mojo::Buffer->new);

=head2 C<headers>

    my $headers = $content->headers;
    $content    = $content->headers(Mojo::Headers->new);

=head2 C<progress_cb>

    my $cb   = $content->progress_cb;
    $content = $content->progress_cb(sub {
        my $self = shift;
        print '+';
    });

=head2 C<relaxed>

    my $relaxed = $content->relaxed;
    $content    = $content->relaxed(1);

=head2 C<raw_header_size>

    my $size = $content->raw_header_size;

=head1 METHODS

L<Mojo::Content> inherits all methods from L<Mojo::Stateful> and implements
the following new ones.

=head2 C<body_contains>

    my $found = $content->body_contains('foo bar baz');

=head2 C<body_size>

    my $size = $content->body_size;

=head2 C<build_body>

    my $string = $content->build_body;

=head2 C<build_headers>

    my $string = $content->build_headers;

=head2 C<generate_body_chunk>

    my $chunk = $content->generate_body_chunk(0);

=head2 C<get_body_chunk>

    my $chunk = $content->get_body_chunk(0);

=head2 C<get_header_chunk>

    my $chunk = $content->get_header_chunk(13);

=head2 C<has_leftovers>

    my $leftovers = $content->has_leftovers;

=head2 C<header_size>

    my $size = $content->header_size;

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

=head2 C<raw_body_size>

    my $size = $content->raw_body_size;

=cut
