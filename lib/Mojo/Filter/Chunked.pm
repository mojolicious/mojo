# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Filter::Chunked;

use strict;
use warnings;

use base 'Mojo::Filter';
use bytes;

# Here's to alcohol, the cause of—and solution to—all life's problems.
sub build {
    my ($self, $chunk) = @_;

    # Done
    return '' if $self->is_done;

    # Shortcut
    return unless defined $chunk;

    my $chunk_length = length $chunk;

    # Trailing headers?
    my $headers = ref $chunk && $chunk->isa('Mojo::Headers') ? 1 : 0;

    my $formatted = '';

    # End
    if ($headers || ($chunk_length == 0)) {
        $self->done;

        # Normal end
        $formatted = "\x0d\x0a0\x0d\x0a";

        # Trailing headers
        $formatted .= $headers ? "$chunk\x0d\x0a\x0d\x0a" : "\x0d\x0a";
    }

    # Separator
    else {

        # First chunk has no leading CRLF
        $formatted = "\x0d\x0a" unless $self->is_state('start');
        $self->state('chunks');

        # Chunk
        $formatted .= sprintf('%x', length $chunk) . "\x0d\x0a$chunk";
    }

    return $formatted;
}

sub parse {
    my $self = shift;

    # Trailing headers
    if ($self->is_state('trailing_headers')) {
        $self->_parse_trailing_headers;
        return $self;
    }

    # Got a chunk (we ignore the chunk extension)
    my $filter  = $self->input_buffer;
    my $content = $filter->to_string;
    while ($content =~ /^((?:\x0d?\x0a)?([\da-fA-F]+).*\x0d?\x0a)/) {
        my $header = $1;
        my $length = hex($2);

        # Last chunk
        if ($length == 0) {
            $filter->remove(length $header);
            $self->state('trailing_headers');
            last;
        }

        # Read chunk
        else {

            # We have a whole chunk
            if (length $content >= (length($header) + $length)) {

                # Remove header
                $content =~ s/^$header//;
                $filter->remove(length $header);

                # Remove payload
                substr $content, 0, $length, '';
                $self->output_buffer->add_chunk($filter->remove($length));

                # Remove newline at end of chunk
                $content =~ s/^(\x0d?\x0a)//;
                $filter->remove(length $1) if $1;
            }

            # Not a whole chunk, need to wait for more data
            else {last}
        }
    }

    # Trailing headers
    $self->_parse_trailing_headers if $self->is_state('trailing_headers');
}

sub _parse_trailing_headers {
    my $self = shift;
    $self->headers->state('headers');
    $self->headers->parse;
    if ($self->headers->is_done) {
        $self->_remove_chunked_encoding;
        $self->done;
    }
}

sub _remove_chunked_encoding {
    my $self     = shift;
    my $encoding = $self->headers->transfer_encoding;
    $encoding =~ s/,?\s*chunked//ig;
    $encoding
      ? $self->headers->transfer_encoding($encoding)
      : $self->headers->remove('Transfer-Encoding');
    $self->headers->content_length($self->output_buffer->raw_size);
}

1;
__END__

=head1 NAME

Mojo::Filter::Chunked - Chunked Filter

=head1 SYNOPSIS

    use Mojo::Filter::Chunked;

    my $chunked = Mojo::Filter::Chunked->new;

    $chunked->headers(Mojo::Headers->new);
    $chunked->input_buffer(Mojo::Buffer->new);
    $chunked->output_buffer(Mojo::Buffer->new);

    $chunked->input_buffer->add_chunk("6\r\nHello!")
    $chunked->parse;
    print $chunked->output_buffer->empty;

    print $chunked->build('Hello World!');

=head1 DESCRIPTION

L<Mojo::Filter::Chunked> is a filter for the chunked transfer encoding.

=head1 ATTRIBUTES

L<Mojo::Filter::Chunked> inherits all attributes from L<Mojo::Filter>.

=head1 METHODS

L<Mojo::Filter::Chunked> inherits all methods from L<Mojo::Filter> and
implements the following new ones.

=head2 C<build>

    my $formatted = $filter->build('Hello World!');

=head2 C<parse>

    $filter = $filter->parse;

=cut
