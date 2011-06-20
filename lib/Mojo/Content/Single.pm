package Mojo::Content::Single;
use Mojo::Base 'Mojo::Content';

use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Content::MultiPart;

has asset => sub { Mojo::Asset::Memory->new };

sub body_contains {
  my ($self, $chunk) = @_;
  return 1 if $self->asset->contains($chunk) >= 0;
  0;
}

sub body_size {
  my $self = shift;
  return ($self->headers->content_length || 0) if $self->on_read;
  $self->asset->size;
}

sub get_body_chunk {
  my ($self, $offset) = @_;

  # Body generator
  return $self->generate_body_chunk($offset) if $self->on_read;

  # Normal content
  $self->asset->get_chunk($offset);
}

sub parse {
  my $self = shift;

  # Parse headers and chunked body
  $self->SUPER::parse(@_);

  # Still parsing headers or using a custom body parser
  return $self if ($self->{_state} || '') eq 'headers' || $self->on_read;

  # Content needs to be upgraded to multipart
  if ($self->is_multipart) {
    return $self if $self->isa('Mojo::Content::MultiPart');

    # Need to upgrade
    return Mojo::Content::MultiPart->new($self)->parse;
  }

  # Don't waste memory
  my $asset = $self->asset;
  if ($asset->isa('Mojo::Asset::Memory')) {

    # Upgrade to file based storage on demand
    if ($asset->size > ($ENV{MOJO_MAX_MEMORY_SIZE} || 262144)) {
      $self->asset(Mojo::Asset::File->new->add_chunk($asset->slurp));
    }
  }

  # Chunked body or relaxed content
  if ($self->is_chunked || $self->relaxed) {
    $self->asset->add_chunk($self->{_b2});
    $self->{_b2} = '';
  }

  # Normal body
  else {

    # Slurp
    my $len   = $self->headers->content_length || 0;
    my $asset = $self->asset;
    my $need  = $len - $asset->size;
    $asset->add_chunk(substr $self->{_b2}, 0, $need, '') if $need > 0;

    # Done
    $self->{_state} = 'done' if $len <= $self->progress;
  }

  $self;
}

1;
__END__

=head1 NAME

Mojo::Content::Single - HTTP 1.1 Content Container

=head1 SYNOPSIS

  use Mojo::Content::Single;

  my $content = Mojo::Content::Single->new;
  $content->parse("Content-Length: 12\r\n\r\nHello World!");

=head1 DESCRIPTION

L<Mojo::Content::Single> is a container for HTTP 1.1 content as described in
RFC 2616.

=head1 ATTRIBUTES

L<Mojo::Content::Single> inherits all attributes from L<Mojo::Content> and
implements the following new ones.

=head2 C<asset>

  my $asset = $content->asset;
  $content  = $content->asset(Mojo::Asset::Memory->new);

The actual content, defaults to a L<Mojo::Asset::Memory> object.

=head1 METHODS

L<Mojo::Content::Single> inherits all methods from L<Mojo::Content> and
implements the following new ones.

=head2 C<body_contains>

  my $found = $content->body_contains('1234567');

Check if content contains a specific string.

=head2 C<body_size>

  my $size = $content->body_size;

Content size in bytes.

=head2 C<get_body_chunk>

  my $chunk = $content->get_body_chunk(0);

Get a chunk of content starting from a specfic position.

=head2 C<parse>

  $content = $content->parse("Content-Length: 12\r\n\r\nHello World!");

Parse content chunk.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
