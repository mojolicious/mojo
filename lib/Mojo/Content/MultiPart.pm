package Mojo::Content::MultiPart;
use Mojo::Base 'Mojo::Content';

use Mojo::Util 'b64_encode';

has parts => sub { [] };

sub new {
  shift->SUPER::new(@_)->tap(sub { $_->on(read => \&_read) });
}

sub body_contains {
  my ($self, $chunk) = @_;
  for my $part (@{$self->parts}) {
    return 1 if index($part->build_headers, $chunk) >= 0;
    return 1 if $part->body_contains($chunk);
  }
  return;
}

sub body_size {
  my $self = shift;

  # Check for Content-Lenght header
  my $content_len = $self->headers->content_length;
  return $content_len if $content_len;

  # Calculate length of whole body
  my $boundary_len = length($self->build_boundary) + 6;
  my $len          = $boundary_len - 2;
  $len += $_->header_size + $_->body_size + $boundary_len for @{$self->parts};

  return $len;
}

sub build_boundary {
  my $self = shift;

  # Check for existing boundary
  my $headers = $self->headers;
  my $type = $headers->content_type || '';
  $type =~ /boundary="?([^\s"]+)"?/i and return $1;

  # Generate and check boundary
  my $boundary;
  my $size = 1;
  while (1) {
    $boundary = b64_encode join('', map chr(rand(256)), 1 .. $size++ * 3);
    $boundary =~ s/\W/X/g;
    last unless $self->body_contains($boundary);
  }

  # Add boundary to Content-Type header
  $type =~ m!^(.*multipart/[^;]+)(.*)$!;
  my $before = $1 || 'multipart/mixed';
  my $after  = $2 || '';
  $headers->content_type("$before; boundary=$boundary$after");

  return $boundary;
}

sub clone {
  my $self = shift;
  return unless my $clone = $self->SUPER::clone();
  return $clone->parts($self->parts);
}

sub get_body_chunk {
  my ($self, $offset) = @_;

  # Body generator
  return $self->generate_body_chunk($offset) if $self->{dynamic};

  # First boundary
  my $boundary     = $self->build_boundary;
  my $boundary_len = length($boundary) + 6;
  my $len          = $boundary_len - 2;
  return substr "--$boundary\x0d\x0a", $offset if $len > $offset;

  # Parts
  my $parts = $self->parts;
  for (my $i = 0; $i < @$parts; $i++) {
    my $part = $parts->[$i];

    # Headers
    my $header_len = $part->header_size;
    return $part->get_header_chunk($offset - $len)
      if ($len + $header_len) > $offset;
    $len += $header_len;

    # Content
    my $content_len = $part->body_size;
    return $part->get_body_chunk($offset - $len)
      if ($len + $content_len) > $offset;
    $len += $content_len;

    # Boundary
    if (($len + $boundary_len) > $offset) {

      # Last boundary
      return substr "\x0d\x0a--$boundary--", $offset - $len
        if $#{$parts} == $i;

      # Middle boundary
      return substr "\x0d\x0a--$boundary\x0d\x0a", $offset - $len;
    }
    $len += $boundary_len;
  }
}

sub is_multipart {1}

sub _parse_multipart_body {
  my ($self, $boundary) = @_;

  # Whole part in buffer
  my $pos = index $self->{multipart}, "\x0d\x0a--$boundary";
  if ($pos < 0) {
    my $len = length($self->{multipart}) - (length($boundary) + 8);
    return unless $len > 0;

    # Store chunk
    my $chunk = substr $self->{multipart}, 0, $len, '';
    $self->parts->[-1] = $self->parts->[-1]->parse($chunk);
    return;
  }

  # Store chunk
  my $chunk = substr $self->{multipart}, 0, $pos, '';
  $self->parts->[-1] = $self->parts->[-1]->parse($chunk);
  return $self->{multi_state} = 'multipart_boundary';
}

sub _parse_multipart_boundary {
  my ($self, $boundary) = @_;

  # Boundary begins
  if ((index $self->{multipart}, "\x0d\x0a--$boundary\x0d\x0a") == 0) {
    substr $self->{multipart}, 0, length($boundary) + 6, '';

    # New part
    my $part = Mojo::Content::Single->new(relaxed => 1);
    $self->emit(part => $part);
    push @{$self->parts}, $part;
    return $self->{multi_state} = 'multipart_body';
  }

  # Boundary ends
  my $end = "\x0d\x0a--$boundary--";
  if ((index $self->{multipart}, $end) == 0) {
    substr $self->{multipart}, 0, length $end, '';

    # Finished
    $self->{state} = $self->{multi_state} = 'finished';
  }

  return;
}

sub _parse_multipart_preamble {
  my ($self, $boundary) = @_;

  # Replace preamble with carriage return and line feed
  my $pos = index $self->{multipart}, "--$boundary";
  unless ($pos < 0) {
    substr $self->{multipart}, 0, $pos, "\x0d\x0a";

    # Parse boundary
    return $self->{multi_state} = 'multipart_boundary';
  }

  # No boundary yet
  return;
}

sub _read {
  my ($self, $chunk) = @_;

  # Parse
  $self->{multipart} .= $chunk;
  $self->{multi_state} ||= 'multipart_preamble';
  my $boundary = $self->boundary;
  until ($self->is_finished) {

    # Preamble
    if (($self->{multi_state} // '') eq 'multipart_preamble') {
      last unless $self->_parse_multipart_preamble($boundary);
    }

    # Boundary
    elsif (($self->{multi_state} // '') eq 'multipart_boundary') {
      last unless $self->_parse_multipart_boundary($boundary);
    }

    # Body
    elsif (($self->{multi_state} // '') eq 'multipart_body') {
      last unless $self->_parse_multipart_body($boundary);
    }
  }
}

1;

=head1 NAME

Mojo::Content::MultiPart - HTTP multipart content

=head1 SYNOPSIS

  use Mojo::Content::MultiPart;

  my $multi = Mojo::Content::MultiPart->new;
  $multi->parse('Content-Type: multipart/mixed; boundary=---foobar');
  my $single = $multi->parts->[4];

=head1 DESCRIPTION

L<Mojo::Content::MultiPart> is a container for HTTP multipart content as
described in RFC 2616.

=head1 EVENTS

L<Mojo::Content::Multipart> inherits all events from L<Mojo::Content> and can
emit the following new ones.

=head2 C<part>

  $multi->on(part => sub {
    my ($multi, $single) = @_;
    ...
  });

Emitted when a new L<Mojo::Content::Single> part starts.

  $multi->on(part => sub {
    my ($multi, $single) = @_;
    return unless $single->headers->content_disposition =~ /name="([^"]+)"/;
    say "Field: $1";
  });

=head1 ATTRIBUTES

L<Mojo::Content::MultiPart> inherits all attributes from L<Mojo::Content> and
implements the following new ones.

=head2 C<parts>

  my $parts = $multi->parts;
  $multi    = $multi->parts([]);

Content parts embedded in this multipart content, usually
L<Mojo::Content::Single> objects.

=head1 METHODS

L<Mojo::Content::MultiPart> inherits all methods from L<Mojo::Content> and
implements the following new ones.

=head2 C<new>

  my $multi = Mojo::Content::MultiPart->new;

Construct a new L<Mojo::Content::MultiPart> object and subscribe to C<read>
event with default content parser.

=head2 C<body_contains>

  my $success = $multi->body_contains('foobarbaz');

Check if content parts contain a specific string.

=head2 C<body_size>

  my $size = $multi->body_size;

Content size in bytes.

=head2 C<build_boundary>

  my $boundary = $multi->build_boundary;

Generate a suitable boundary for content.

=head2 C<clone>

  my $clone = $multi->clone;

Clone content if possible, otherwise return C<undef>.

=head2 C<get_body_chunk>

  my $chunk = $multi->get_body_chunk(0);

Get a chunk of content starting from a specfic position.

=head2 C<is_multipart>

  my $true = $multi->is_multipart;

True.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
