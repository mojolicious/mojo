package Mojo::Content;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';
use Mojo::ByteStream;
use Mojo::Filter::Chunked;
use Mojo::Headers;

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 262144;

__PACKAGE__->attr([qw/body_cb filter/]);
__PACKAGE__->attr([qw/buffer filter_buffer/] => sub { Mojo::ByteStream->new }
);
__PACKAGE__->attr(headers => sub { Mojo::Headers->new });
__PACKAGE__->attr(raw_header_size => 0);
__PACKAGE__->attr(relaxed         => 0);

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
    my $buffer = $self->buffer;
    my $written = $offset - ($buffer->raw_size - $buffer->size);
    $buffer->remove($written);

    # Fill buffer
    if (!$self->{_eof} && $buffer->size < CHUNK_SIZE) {

        # Generate
        my $chunk = $self->body_cb->($self, $buffer->raw_size);

        # EOF
        if (defined $chunk && !length $chunk) { $self->{_eof} = 1 }

        # Buffer chunk
        else { $buffer->add_chunk($chunk) }
    }

    # Get chunk
    my $chunk = $buffer->to_string;

    # Pause or EOF
    return $self->{_eof} ? '' : undef unless length $chunk;

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

    # Leftovers
    return 1 if $self->buffer->size || $self->filter_buffer->size;

    # Empty buffer
    return;
}

sub header_size { length shift->build_headers }

sub is_chunked {
    my $self = shift;

    # Chunked
    my $encoding = $self->headers->transfer_encoding || '';
    return $encoding =~ /chunked/i ? 1 : 0;
}

sub is_done {
    return 1 if (shift->{_state} || '') eq 'done';
    return;
}

sub is_multipart {
    my $self = shift;

    # Multipart
    my $type = $self->headers->content_type || '';
    return $type =~ /multipart/i ? 1 : 0;
}

sub is_parsing_body {
    return 1 if (shift->{_state} || '') eq 'body';
    return;
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
    my $fbuffer = $self->filter_buffer;
    $fbuffer->add_chunk($chunk);

    # Parse headers
    $self->parse_until_body;

    # Still parsing headers
    return $self if $self->{_state} eq 'headers';

    # Chunked, need to filter
    if ($self->is_chunked && ($self->{_state} || '') ne 'headers') {

        # Initialize filter
        $self->filter(
            Mojo::Filter::Chunked->new(
                headers       => $self->headers,
                input_buffer  => $fbuffer,
                output_buffer => $self->buffer
            )
        ) unless $self->filter;

        # Filter
        $self->filter->parse;
        $self->{_state} = 'done' if $self->filter->is_done;
    }

    # Not chunked, pass through
    else { $self->buffer($fbuffer) }

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
            $self->{_size} ||= 0;
            my $need = $length - $self->{_size};

            # Slurp
            if ($need > 0) {
                my $chunk = $self->buffer->remove($need);
                $self->{_size} = $self->{_size} + length $chunk;
                $self->$cb($chunk);
            }

            # Done
            $self->{_state} = 'done' if $length <= $self->raw_body_size;
        }
    }

    return $self;
}

sub parse_body {
    my $self = shift;
    $self->{_state} = 'body';
    $self->parse(@_);
}

sub parse_body_once {
    my $self = shift;
    $self->parse_body(@_);
    $self->{_state} = 'done';
    return $self;
}

sub parse_until_body {
    my ($self, $chunk) = @_;

    # Buffer
    my $fbuffer = $self->filter_buffer;
    $fbuffer->add_chunk($chunk);

    # Parser started
    unless ($self->{_state}) {

        # Update size
        my $length            = $fbuffer->size;
        my $raw_length        = $fbuffer->raw_size;
        my $raw_header_length = $raw_length - $length;
        $self->raw_header_size($raw_header_length);

        # Headers
        $self->{_state} = 'headers';
    }

    # Parse headers
    $self->_parse_headers if ($self->{_state} || '') eq 'headers';

    return $self;
}

sub raw_body_size {
    my $self = shift;

    # Calculate
    my $length        = $self->filter_buffer->raw_size;
    my $header_length = $self->raw_header_size;
    return $length - $header_length;
}

sub _build_headers {
    my $self = shift;

    # Build
    my $headers = $self->headers->to_string;

    # Empty
    return "\x0d\x0a" unless $headers;

    return "$headers\x0d\x0a\x0d\x0a";
}

sub _parse_headers {
    my $self = shift;

    # Parse
    my $headers = $self->headers;
    $headers->buffer($self->filter_buffer);
    $headers->parse;

    # Update size
    my $buffer            = $headers->buffer;
    my $length            = $buffer->size;
    my $raw_length        = $buffer->raw_size;
    my $raw_header_length = $raw_length - $length;
    $self->raw_header_size($raw_header_length);

    # Done
    $self->{_state} = 'body' if $headers->is_done;
}

1;
__END__

=head1 NAME

Mojo::Content - HTTP 1.1 Content Base Class

=head1 SYNOPSIS

    use base 'Mojo::Content';

=head1 DESCRIPTION

L<Mojo::Content> is an abstract base class for HTTP 1.1 content as described
in RFC 2616.

=head1 ATTRIBUTES

L<Mojo::Content> implements the following attributes.

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

Content generator callback.

=head2 C<buffer>

    my $buffer = $content->buffer;
    $content   = $content->buffer(Mojo::ByteStream->new);

Parser buffer.

=head2 C<filter>

    my $filter = $content->filter;
    $content   = $content->filter(Mojo::Filter::Chunked->new);

Input filter.

=head2 C<filter_buffer>

    my $filter_buffer = $content->filter_buffer;
    $content          = $content->filter_buffer(Mojo::ByteStream->new);

Input buffer for filtering.

=head2 C<headers>

    my $headers = $content->headers;
    $content    = $content->headers(Mojo::Headers->new);

The headers.

=head2 C<relaxed>

    my $relaxed = $content->relaxed;
    $content    = $content->relaxed(1);

Activate relaxed filtering for HTTP 0.9.

=head2 C<raw_header_size>

    my $size = $content->raw_header_size;

Raw size of headers in bytes.

=head1 METHODS

L<Mojo::Content> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<body_contains>

    my $found = $content->body_contains('foo bar baz');

Check if content contains a specific string.

=head2 C<body_size>

    my $size = $content->body_size;

Content size in bytes.

=head2 C<build_body>

    my $string = $content->build_body;

Render whole body.

=head2 C<build_headers>

    my $string = $content->build_headers;

Render all headers.

=head2 C<generate_body_chunk>

    my $chunk = $content->generate_body_chunk(0);

Generate content from C<body_cb>.

=head2 C<get_body_chunk>

    my $chunk = $content->get_body_chunk(0);

Get a chunk of content starting from a specfic position.

=head2 C<get_header_chunk>

    my $chunk = $content->get_header_chunk(13);

Get a chunk of the headers starting from a specfic position.

=head2 C<has_leftovers>

    my $leftovers = $content->has_leftovers;

Check if there are leftovers in the buffer.

=head2 C<header_size>

    my $size = $content->header_size;

Size of headers in bytes.

=head2 C<is_chunked>

    my $chunked = $content->is_chunked;

Chunked transfer encoding.

=head2 C<is_done>

    my $done = $content->is_done;

Check if parser is done.

=head2 C<is_multipart>

    my $multipart = $content->is_multipart;

Multipart content.

=head2 C<is_parsing_body>

    my $body = $content->is_parsing_body;

Check if body parsing started yet.

=head2 C<leftovers>

    my $bytes = $content->leftovers;

Leftovers for next HTTP message in buffer.

=head2 C<parse>

    $content = $content->parse("Content-Length: 12\r\n\r\nHello World!");

Parse content.

=head2 C<parse_body>

    $content = $content->parse_body("Hi!");

Parse body.

=head2 C<parse_body_once>

    $content = $content->parse_body_once("Hi!");

Parse body once.

=head2 C<parse_until_body>

    $content = $content->parse_until_body(
        "Content-Length: 12\r\n\r\nHello World!"
    );

Parse and stop after headers.

=head2 C<raw_body_size>

    my $size = $content->raw_body_size;

Raw size of body in bytes.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
