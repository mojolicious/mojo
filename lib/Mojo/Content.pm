package Mojo::Content;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';
use Mojo::ByteStream 'b';
use Mojo::Headers;

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 262144;

__PACKAGE__->attr([qw/auto_relax relaxed/] => 0);
__PACKAGE__->attr([qw/buffer chunked_buffer/] => sub { b() });
__PACKAGE__->attr(headers => sub { Mojo::Headers->new });
__PACKAGE__->attr('on_read');

# DEPRECATED in Comet!
*read_cb = \&on_read;

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

sub finish { shift->{_eof} = 1 }

sub generate_body_chunk {
    my ($self, $offset) = @_;

    # Buffer
    my $buffer = $self->buffer;

    # Delay
    my $delay = delete $self->{_delay};

    # Callback
    if (!$delay && !$buffer->size && (my $cb = delete $self->{_drain})) {
        $self->$cb($offset);
    }

    # Get chunk
    my $chunk = $buffer->empty;

    # EOF
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
    return 1 if $self->buffer->size || $self->chunked_buffer->size;

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

    # Chunked leftovers are in the chunked buffer, and so are those from a
    # HEAD request
    return $self->chunked_buffer->to_string if $self->chunked_buffer->size;

    # Normal leftovers
    return $self->buffer->to_string;
}

sub parse {
    my ($self, $chunk) = @_;

    # Buffer
    my $buffer = $self->chunked_buffer;
    $buffer->add_chunk($chunk);

    # Parse headers
    $self->parse_until_body;

    # Still parsing headers
    return $self if $self->{_state} eq 'headers';

    # Relaxed parsing for broken web servers
    if ($self->auto_relax) {
        my $headers = $self->headers;
        $self->relaxed(1)
          if !defined $headers->content_length
              && ($headers->connection || '') =~ /close/i;
    }

    # Chunked
    if ($self->is_chunked && ($self->{_state} || '') ne 'headers') {
        $self->_parse_chunked;
        $self->{_state} = 'done' if ($self->{_chunked} || '') eq 'done';
    }

    # Not chunked, pass through
    else { $self->buffer($buffer) }

    # Custom body parser
    if (my $cb = $self->on_read) {

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
            $self->{_state} = 'done' if $length <= $self->progress;
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

# Quick Smithers. Bring the mind eraser device!
# You mean the revolver, sir?
# Precisely.
sub parse_until_body {
    my ($self, $chunk) = @_;

    # Buffer
    my $buffer = $self->chunked_buffer;
    $buffer->add_chunk($chunk);

    # Parser started
    unless ($self->{_state}) {

        # Update size
        $self->{_header_size} = $buffer->raw_size - $buffer->size;

        # Headers
        $self->{_state} = 'headers';
    }

    # Parse headers
    $self->_parse_headers if ($self->{_state} || '') eq 'headers';

    return $self;
}

sub progress {
    my $self = shift;
    $self->chunked_buffer->raw_size - ($self->{_header_size} || 0);
}

sub write {
    my ($self, $chunk, $cb) = @_;

    # Dynamic content
    $self->on_read(sub { });

    # Buffer
    $self->buffer->add_chunk($chunk);

    # Delay
    $self->{_delay} = 1 unless defined $chunk;

    # Drain callback
    $self->{_drain} = $cb if $cb;
}

# Here's to alcohol, the cause of—and solution to—all life's problems.
sub write_chunk {
    my ($self, $chunk, $cb) = @_;

    # Chunked transfer encoding
    $self->headers->transfer_encoding('chunked') unless $self->is_chunked;

    # Write
    $self->write(defined $chunk ? $self->_build_chunk($chunk) : $chunk, $cb);

    # Finish
    $self->finish if defined $chunk && $chunk eq '';
}

sub _build_chunk {
    my ($self, $chunk) = @_;

    # End
    my $formatted = '';
    if (length $chunk == 0) { $formatted = "\x0d\x0a0\x0d\x0a\x0d\x0a" }

    # Separator
    else {

        # First chunk has no leading CRLF
        $formatted = "\x0d\x0a" if $self->{_chunks};
        $self->{_chunks} = 1;

        # Chunk
        $formatted .= sprintf('%x', length $chunk) . "\x0d\x0a$chunk";
    }

    return $formatted;
}

sub _build_headers {
    my $self = shift;

    # Build
    my $headers = $self->headers->to_string;

    # Empty
    return "\x0d\x0a" unless $headers;

    return "$headers\x0d\x0a\x0d\x0a";
}

sub _parse_chunked {
    my $self = shift;

    # Trailing headers
    if (($self->{_chunked} || '') eq 'trailing_headers') {
        $self->_parse_chunked_trailing_headers;
        return $self;
    }

    # New chunk (ignore the chunk extension)
    my $chunked = $self->chunked_buffer;
    my $content = $chunked->to_string;
    my $buffer  = $self->buffer;
    while ($content =~ /^((?:\x0d?\x0a)?([\da-fA-F]+).*\x0d?\x0a)/) {
        my $header = $1;
        my $length = hex($2);

        # Last chunk
        if ($length == 0) {
            $chunked->remove(length $header);
            $self->{_chunked} = 'trailing_headers';
            last;
        }

        # Read chunk
        else {

            # Whole chunk
            if (length $content >= (length($header) + $length)) {

                # Remove header
                $content =~ s/^$header//;
                $chunked->remove(length $header);

                # Remove payload
                substr $content, 0, $length, '';
                $buffer->add_chunk($chunked->remove($length));

                # Remove newline at end of chunk
                $content =~ s/^(\x0d?\x0a)//
                  and $chunked->remove(length $1);
            }

            # Not a whole chunk, wait for more data
            else {last}
        }
    }

    # Trailing headers
    $self->_parse_chunked_trailing_headers
      if ($self->{_chunked} || '') eq 'trailing_headers';
}

sub _parse_chunked_trailing_headers {
    my $self = shift;

    # Parse
    my $headers = $self->headers;
    $headers->parse;

    # Done
    if ($headers->is_done) {

        # Remove Transfer-Encoding
        my $headers  = $self->headers;
        my $encoding = $headers->transfer_encoding;
        $encoding =~ s/,?\s*chunked//ig;
        $encoding
          ? $headers->transfer_encoding($encoding)
          : $headers->remove('Transfer-Encoding');
        $headers->content_length($self->buffer->raw_size);

        $self->{_chunked} = 'done';
    }
}

sub _parse_headers {
    my $self = shift;

    # Parse
    my $headers = $self->headers;
    $headers->buffer($self->chunked_buffer);
    $headers->parse;

    # Update size
    my $buffer = $headers->buffer;
    $self->{_header_size} = $buffer->raw_size - $buffer->size;

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

=head2 C<auto_relax>

    my $relax = $content->auto_relax;
    $content  = $content->auto_relax(1);

Try to detect broken web servers and turn on relaxed parsing automatically.

=head2 C<buffer>

    my $buffer = $content->buffer;
    $content   = $content->buffer(Mojo::ByteStream->new);

Parser buffer.

=head2 C<chunked_buffer>

    my $buffer = $content->chunked_buffer;
    $content   = $content->chunked_buffer(Mojo::ByteStream->new);

Parser buffer for chunked transfer encoding.

=head2 C<headers>

    my $headers = $content->headers;
    $content    = $content->headers(Mojo::Headers->new);

The headers.

=head2 C<on_read>

    my $cb   = $content->on_read;
    $content = $content->on_read(sub {...});

Content parser callback.

    $content = $content->on_read(sub {
        my ($self, $chunk) = @_;
        print $chunk;
    });

Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<relaxed>

    my $relaxed = $content->relaxed;
    $content    = $content->relaxed(1);

Activate relaxed parsing for HTTP 0.9 and broken web servers.

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

=head2 C<finish>

    $content->finish;

Finish dynamic content generation.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<generate_body_chunk>

    my $chunk = $content->generate_body_chunk(0);

Generate dynamic content.

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

=head2 C<progress>

    my $bytes = $content->progress;

Number of bytes already received from message content.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<write>

    $content->write('Hello!');
    $content->write('Hello!', sub {...});

Write dynamic content, the optional drain callback will be invoked once all
data has been written.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<write_chunk>

    $content->write_chunk('Hello!');
    $content->write_chunk('Hello!', sub {...});

Write chunked content, the optional drain callback will be invoked once all
data has been written.
Note that this method is EXPERIMENTAL and might change without warning!

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
