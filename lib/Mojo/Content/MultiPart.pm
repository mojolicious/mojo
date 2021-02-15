package Mojo::Content::MultiPart;
use Mojo::Base 'Mojo::Content';

use Mojo::Util qw(b64_encode);

has parts => sub { [] };

sub body_contains {
  my ($self, $chunk) = @_;
  ($_->headers_contain($chunk) or $_->body_contains($chunk)) and return 1 for @{$self->parts};
  return undef;
}

sub body_size {
  my $self = shift;

  # Check for existing Content-Length header
  if (my $len = $self->headers->content_length) { return $len }

  # Calculate length of whole body
  my $len = my $boundary_len = length($self->build_boundary) + 6;
  $len += $_->header_size + $_->body_size + $boundary_len for @{$self->parts};

  return $len;
}

sub build_boundary {
  my $self = shift;

  # Check for existing boundary
  my $boundary;
  return $boundary if defined($boundary = $self->boundary);

  # Generate and check boundary
  my $size = 1;
  do {
    $boundary = b64_encode join('', map chr(rand 256), 1 .. $size++ * 3);
    $boundary =~ s/\W/X/g;
  } while $self->body_contains($boundary);

  # Add boundary to Content-Type header
  my $headers = $self->headers;
  my ($before, $after) = ('multipart/mixed', '');
  ($before, $after) = ($1, $2) if ($headers->content_type // '') =~ m!^(.*multipart/[^;]+)(.*)$!;
  $headers->content_type("$before; boundary=$boundary$after");

  return $boundary;
}

sub clone {
  my $self = shift;
  return undef unless my $clone = $self->SUPER::clone();
  return $clone->parts($self->parts);
}

sub get_body_chunk {
  my ($self, $offset) = @_;

  # Body generator
  return $self->generate_body_chunk($offset) if $self->is_dynamic;

  # First boundary
  my $boundary     = $self->{boundary} //= $self->build_boundary;
  my $boundary_len = length($boundary) + 6;
  my $len          = $boundary_len - 2;
  return substr "--$boundary\x0d\x0a", $offset if $len > $offset;

  # Skip parts that have already been processed
  my $start = 0;
  ($len, $start) = ($self->{last_len}, $self->{last_part} + 1) if $self->{offset} && $offset > $self->{offset};

  # Prepare content part by part
  my $parts = $self->parts;
  for (my $i = $start; $i < @$parts; $i++) {
    my $part = $parts->[$i];

    # Headers
    my $header_len = $part->header_size;
    return $part->get_header_chunk($offset - $len) if ($len + $header_len) > $offset;
    $len += $header_len;

    # Content
    my $content_len = $part->body_size;
    return $part->get_body_chunk($offset - $len) if ($len + $content_len) > $offset;
    $len += $content_len;

    # Boundary
    if ($#$parts == $i) {
      $boundary .= '--';
      $boundary_len += 2;
    }
    return substr "\x0d\x0a--$boundary\x0d\x0a", $offset - $len if ($len + $boundary_len) > $offset;
    $len += $boundary_len;

    @{$self}{qw(last_len last_part offset)} = ($len, $i, $offset);
  }
}

sub is_multipart {1}

sub new {
  my $self = shift->SUPER::new(@_);
  $self->on(read => \&_read);
  return $self;
}

sub _parse_multipart_body {
  my ($self, $boundary) = @_;

  # Whole part in buffer
  my $pos = index $self->{multipart}, "\x0d\x0a--$boundary";
  if ($pos < 0) {
    my $len = length($self->{multipart}) - (length($boundary) + 8);
    return undef unless $len > 0;

    # Store chunk
    my $chunk = substr $self->{multipart}, 0, $len, '';
    $self->parts->[-1] = $self->parts->[-1]->parse($chunk);
    return undef;
  }

  # Store chunk
  my $chunk = substr $self->{multipart}, 0, $pos, '';
  $self->parts->[-1] = $self->parts->[-1]->parse($chunk);
  return !!($self->{multi_state} = 'multipart_boundary');
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
    return !!($self->{multi_state} = 'multipart_body');
  }

  # Boundary ends
  my $end = "\x0d\x0a--$boundary--";
  if ((index $self->{multipart}, $end) == 0) {
    substr $self->{multipart}, 0, length $end, '';
    $self->{multi_state} = 'finished';
  }

  return undef;
}

sub _parse_multipart_preamble {
  my ($self, $boundary) = @_;

  # No boundary yet
  return undef if (my $pos = index $self->{multipart}, "--$boundary") < 0;

  # Replace preamble with carriage return and line feed
  substr $self->{multipart}, 0, $pos, "\x0d\x0a";

  # Parse boundary
  return !!($self->{multi_state} = 'multipart_boundary');
}

sub _read {
  my ($self, $chunk) = @_;

  $self->{multipart} .= $chunk;
  my $boundary = $self->boundary;
  until (($self->{multi_state} //= 'multipart_preamble') eq 'finished') {

    # Preamble
    if ($self->{multi_state} eq 'multipart_preamble') { last unless $self->_parse_multipart_preamble($boundary) }

    # Boundary
    elsif ($self->{multi_state} eq 'multipart_boundary') { last unless $self->_parse_multipart_boundary($boundary) }

    # Body
    elsif ($self->{multi_state} eq 'multipart_body') { last unless $self->_parse_multipart_body($boundary) }
  }

  # Check buffer size
  @$self{qw(state limit)} = ('finished', 1) if length($self->{multipart} // '') > $self->max_buffer_size;
}

1;

=encoding utf8

=head1 NAME

Mojo::Content::MultiPart - HTTP multipart content

=head1 SYNOPSIS

  use Mojo::Content::MultiPart;

  my $multi = Mojo::Content::MultiPart->new;
  $multi->parse('Content-Type: multipart/mixed; boundary=---foobar');
  my $single = $multi->parts->[4];

=head1 DESCRIPTION

L<Mojo::Content::MultiPart> is a container for HTTP multipart content, based on L<RFC
7230|https://tools.ietf.org/html/rfc7230>, L<RFC 7231|https://tools.ietf.org/html/rfc7231> and L<RFC
2388|https://tools.ietf.org/html/rfc2388>.

=head1 EVENTS

L<Mojo::Content::MultiPart> inherits all events from L<Mojo::Content> and can emit the following new ones.

=head2 part

  $multi->on(part => sub ($multi, $single) {...});

Emitted when a new L<Mojo::Content::Single> part starts.

  $multi->on(part => sub ($multi, $single) {
    return unless $single->headers->content_disposition =~ /name="([^"]+)"/;
    say "Field: $1";
  });

=head1 ATTRIBUTES

L<Mojo::Content::MultiPart> inherits all attributes from L<Mojo::Content> and implements the following new ones.

=head2 parts

  my $parts = $multi->parts;
  $multi    = $multi->parts([Mojo::Content::Single->new]);

Content parts embedded in this multipart content, usually L<Mojo::Content::Single> objects.

=head1 METHODS

L<Mojo::Content::MultiPart> inherits all methods from L<Mojo::Content> and implements the following new ones.

=head2 body_contains

  my $bool = $multi->body_contains('foobarbaz');

Check if content parts contain a specific string.

=head2 body_size

  my $size = $multi->body_size;

Content size in bytes.

=head2 build_boundary

  my $boundary = $multi->build_boundary;

Generate a suitable boundary for content and add it to C<Content-Type> header.

=head2 clone

  my $clone = $multi->clone;

Return a new L<Mojo::Content::MultiPart> object cloned from this content if possible, otherwise return C<undef>.

=head2 get_body_chunk

  my $bytes = $multi->get_body_chunk(0);

Get a chunk of content starting from a specific position. Note that it might not be possible to get the same chunk
twice if content was generated dynamically.

=head2 is_multipart

  my $bool = $multi->is_multipart;

True, this is a L<Mojo::Content::MultiPart> object.

=head2 new

  my $multi = Mojo::Content::MultiPart->new;
  my $multi
    = Mojo::Content::MultiPart->new(parts => [Mojo::Content::Single->new]);
  my $multi
    = Mojo::Content::MultiPart->new({parts => [Mojo::Content::Single->new]});

Construct a new L<Mojo::Content::MultiPart> object and subscribe to event L<Mojo::Content/"read"> with default content
parser.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
