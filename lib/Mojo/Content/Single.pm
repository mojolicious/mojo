# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Content::Single;

use strict;
use warnings;

use base 'Mojo::Content';
use bytes;

use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Content::MultiPart;

use constant MAX_MEMORY_SIZE => $ENV{MOJO_MAX_MEMORY_SIZE} || 10240;

__PACKAGE__->attr(asset => sub { Mojo::Asset::Memory->new });

sub body_contains {
    my ($self, $chunk) = @_;

    # Found
    return 1 if $self->asset->contains($chunk) >= 0;

    # Not found
    return 0;
}

sub body_size { shift->asset->size }

sub get_body_chunk {
    my ($self, $offset) = @_;

    # Progress
    $self->progress_cb->($self, 'body', $offset) if $self->progress_cb;

    # Body generator
    return $self->generate_body_chunk($offset) if $self->body_cb;

    # Normal content
    return $self->asset->get_chunk($offset);
}

sub parse {
    my $self = shift;

    # Parse headers and filter body
    $self->SUPER::parse(@_);

    # Still parsing headers or using a custom body parser
    return $self if $self->is_state('headers') || $self->body_cb;

    # Make sure we don't waste memory
    if ($self->asset->isa('Mojo::Asset::Memory')) {
        $self->asset(Mojo::Asset::File->new)
          if !$self->headers->content_length
              || $self->headers->content_length > MAX_MEMORY_SIZE;
    }

    # Content needs to be upgraded to multipart
    if ($self->is_multipart) {

        # Shortcut
        return $self if $self->isa('Mojo::Content::MultiPart');

        # Need to upgrade
        return Mojo::Content::MultiPart->new($self)->parse;
    }

    # Chunked body or relaxed content
    if ($self->is_chunked || $self->relaxed) {
        $self->asset->add_chunk($self->buffer->empty);
    }

    # Normal body
    else {

        # Slurp
        my $length = $self->headers->content_length || 0;
        my $need = $length - $self->asset->size;
        $self->asset->add_chunk($self->buffer->remove($need)) if $need > 0;

        # Done
        $self->done if $length <= $self->raw_body_size;
    }

    # With leftovers, maybe pipelined
    if ($self->is_done) {
        $self->state('done_with_leftovers') if $self->has_leftovers;
    }

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Content::Single - HTTP Content

=head1 SYNOPSIS

    use Mojo::Content::Single;

    my $content = Mojo::Content::Single->new;
    $content->parse("Content-Length: 12\r\n\r\nHello World!");

=head1 DESCRIPTION

L<Mojo::Content::Single> is a container for HTTP content.

=head1 ATTRIBUTES

L<Mojo::Content::Single> inherits all attributes from L<Mojo::Content> and
implements the following new ones.

=head2 C<asset>

    my $asset = $content->asset;
    $content  = $content->asset(Mojo::Asset::Memory->new);

=head1 METHODS

L<Mojo::Content::Single> inherits all methods from L<Mojo::Content> and
implements the following new ones.

=head2 C<body_contains>

    my $found = $content->body_contains;

=head2 C<body_size>

    my $size = $content->body_size;

=head2 C<get_body_chunk>

    my $chunk = $content->get_body_chunk(0);

=head2 C<parse>

    $content = $content->parse("Content-Length: 12\r\n\r\nHello World!");

=cut
