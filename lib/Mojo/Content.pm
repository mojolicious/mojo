package Mojo::Content;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::Headers;

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 131072;

has [qw/auto_relax relaxed/] => 0;
has headers => sub { Mojo::Headers->new };
has 'on_read';

sub body_contains {
  croak 'Method "body_contains" not implemented by subclass';
}

sub body_size { croak 'Method "body_size" not implemented by subclass' }

# "Operator! Give me the number for 911!"
sub build_body {
  my $self = shift;

  # Concatenate all chunks in memory
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

  # Concatenate all chunks in memory
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

# "Aren't we forgetting the true meaning of Christmas?
#  You know, the birth of Santa."
sub generate_body_chunk {
  my ($self, $offset) = @_;

  # Callback
  if (!delete $self->{delay} && !length $self->{b2}) {
    my $cb = delete $self->{drain};
    $self->$cb($offset) if $cb;
  }

  # Get chunk
  my $chunk = $self->{b2};
  $chunk = '' unless defined $chunk;
  $self->{b2} = '';

  # EOF or delay
  return $self->{eof} ? '' : undef unless length $chunk;

  return $chunk;
}

sub get_body_chunk {
  croak 'Method "get_body_chunk" not implemented by subclass';
}

sub get_header_chunk {
  my ($self, $offset) = @_;

  # Normal headers
  my $copy = $self->{b1} ||= $self->_build_headers;
  return substr($copy, $offset, CHUNK_SIZE);
}

sub has_leftovers {
  my $self = shift;
  return 1 if length $self->{b2} || length $self->{b1};
  return;
}

sub header_size { length shift->build_headers }

sub is_chunked {
  my $self = shift;
  my $encoding = $self->headers->transfer_encoding || '';
  return $encoding =~ /chunked/i ? 1 : 0;
}

sub is_done {
  return 1 if (shift->{state} || '') eq 'done';
  return;
}

sub is_dynamic {
  my $self = shift;
  return 1 if $self->on_read && !defined $self->headers->content_length;
  return;
}

sub is_multipart {
  my $self = shift;
  my $type = $self->headers->content_type || '';
  $type =~ /multipart.*boundary=\"*([a-zA-Z0-9\'\(\)\,\.\:\?\-\_\+\/]+)/i
    and return $1;
  return;
}

sub is_parsing_body {
  return 1 if (shift->{state} || '') eq 'body';
  return;
}

sub leftovers {
  my $self = shift;

  # Chunked leftovers are in the chunked buffer, and so are those from a
  # HEAD request
  return $self->{b1} if length $self->{b1};

  # Normal leftovers
  return $self->{b2};
}

sub parse {
  my $self = shift;

  # Parse headers
  $self->parse_until_body(@_);

  # Still parsing headers
  return $self if $self->{state} eq 'headers';

  # Relaxed parsing for wonky web servers
  if ($self->auto_relax) {
    my $headers    = $self->headers;
    my $connection = $headers->connection || '';
    my $len        = $headers->content_length;
    $len = '' unless defined $len;
    $self->relaxed(1)
      if !length $len
        && ($connection =~ /close/i || $headers->content_type);
  }

  # Parse chunked content
  $self->{real_size} = 0 unless exists $self->{real_size};
  if ($self->is_chunked && ($self->{state} || '') ne 'headers') {
    $self->_parse_chunked;
    $self->{state} = 'done' if ($self->{chunked} || '') eq 'done';
  }

  # Not chunked, pass through to second buffer
  else {
    $self->{real_size} += length $self->{b1};
    $self->{b2} .= $self->{b1};
    $self->{b1} = '';
  }

  # Custom body parser callback
  if (my $cb = $self->on_read) {

    # Chunked or relaxed content
    if ($self->is_chunked || $self->relaxed) {
      $self->{b2} = '' unless defined $self->{b2};
      $self->$cb($self->{b2});
      $self->{b2} = '';
    }

    # Normal content
    else {

      # Bytes needed
      my $len = $self->headers->content_length || 0;
      $self->{size} ||= 0;
      my $need = $len - $self->{size};

      # Slurp
      if ($need > 0) {
        my $chunk = substr $self->{b2}, 0, $need, '';
        $self->{size} = $self->{size} + length $chunk;
        $self->$cb($chunk);
      }

      # Done
      $self->{state} = 'done' if $len <= $self->progress;
    }
  }

  return $self;
}

sub parse_body {
  my $self = shift;
  $self->{state} = 'body';
  $self->parse(@_);
}

sub parse_body_once {
  my $self = shift;
  $self->parse_body(@_);
  $self->{state} = 'done';
  return $self;
}

# "Quick Smithers. Bring the mind eraser device!
#  You mean the revolver, sir?
#  Precisely."
sub parse_until_body {
  my ($self, $chunk) = @_;

  # Prepare first buffer
  $self->{b1}       = '' unless defined $self->{b1};
  $self->{raw_size} = 0  unless exists $self->{raw_size};

  # Add chunk
  if (defined $chunk) {
    $self->{raw_size} += length $chunk;
    $self->{b1} .= $chunk;
  }

  # Parser started
  unless ($self->{state}) {

    # Update size
    $self->{header_size} = $self->{raw_size} - length $self->{b1};

    # Headers
    $self->{state} = 'headers';
  }

  # Parse headers
  $self->_parse_headers if ($self->{state} || '') eq 'headers';

  return $self;
}

sub progress {
  my $self = shift;
  return $self->{raw_size} - ($self->{header_size} || 0);
}

sub write {
  my ($self, $chunk, $cb) = @_;

  # Dynamic content
  $self->on_read(sub { });

  # Add chunk
  if (defined $chunk) {
    $self->{b2} = '' unless defined $self->{b2};
    $self->{b2} .= $chunk;
  }

  # Delay
  else { $self->{delay} = 1 }

  # Drain callback
  $self->{drain} = $cb if $cb;

  # Finish
  $self->{eof} = 1 if defined $chunk && $chunk eq '';
}

# "Here's to alcohol, the cause of—and solution to—all life's problems."
sub write_chunk {
  my ($self, $chunk, $cb) = @_;

  # Chunked transfer encoding
  $self->headers->transfer_encoding('chunked') unless $self->is_chunked;

  # Write
  $self->write(defined $chunk ? $self->_build_chunk($chunk) : $chunk, $cb);

  # Finish
  $self->{eof} = 1 if defined $chunk && $chunk eq '';
}

sub _build_chunk {
  my ($self, $chunk) = @_;

  # End
  my $formatted = '';
  if (length $chunk == 0) { $formatted = "\x0d\x0a0\x0d\x0a\x0d\x0a" }

  # Separator
  else {

    # First chunk has no leading CRLF
    $formatted = "\x0d\x0a" if $self->{chunks};
    $self->{chunks} = 1;

    # Chunk
    $formatted .= sprintf('%x', length $chunk) . "\x0d\x0a$chunk";
  }

  return $formatted;
}

sub _build_headers {
  my $self    = shift;
  my $headers = $self->headers->to_string;
  return "\x0d\x0a" unless $headers;
  return "$headers\x0d\x0a\x0d\x0a";
}

sub _parse_chunked {
  my $self = shift;

  # Trailing headers
  if (($self->{chunked} || '') eq 'trailing_headers') {
    $self->_parse_chunked_trailing_headers;
    return $self;
  }

  # New chunk (ignore the chunk extension)
  while ($self->{b1} =~ /^((?:\x0d?\x0a)?([\da-fA-F]+).*\x0d?\x0a)/) {
    my $header = $1;
    my $len    = hex($2);

    # Whole chunk
    if (length($self->{b1}) >= (length($header) + $len)) {

      # Remove header
      substr $self->{b1}, 0, length $header, '';

      # Last chunk
      if ($len == 0) {
        $self->{chunked} = 'trailing_headers';
        last;
      }

      # Remove payload
      $self->{real_size} += $len;
      $self->{b2} .= substr $self->{b1}, 0, $len, '';

      # Remove newline at end of chunk
      $self->{b1} =~ s/^(\x0d?\x0a)//;
    }

    # Not a whole chunk, wait for more data
    else {last}
  }

  # Trailing headers
  $self->_parse_chunked_trailing_headers
    if ($self->{chunked} || '') eq 'trailing_headers';
}

sub _parse_chunked_trailing_headers {
  my $self = shift;

  # Parse
  my $headers = $self->headers;
  $headers->parse($self->{b1});
  $self->{b1} = '';

  # Done
  if ($headers->is_done) {

    # Remove Transfer-Encoding
    my $headers  = $self->headers;
    my $encoding = $headers->transfer_encoding;
    $encoding =~ s/,?\s*chunked//ig;
    $encoding
      ? $headers->transfer_encoding($encoding)
      : $headers->remove('Transfer-Encoding');
    $headers->content_length($self->{real_size});

    $self->{chunked} = 'done';
  }
}

sub _parse_headers {
  my $self = shift;

  # Parse
  my $headers = $self->headers;
  $headers->parse($self->{b1});
  $self->{b1} = '';

  # Done
  if ($headers->is_done) {
    my $leftovers = $headers->leftovers;
    $self->{header_size} = $self->{raw_size} - length $leftovers;
    $self->{b1}          = $leftovers;
    $self->{state}       = 'body';
  }
}

1;
__END__

=head1 NAME

Mojo::Content - HTTP 1.1 Content Base Class

=head1 SYNOPSIS

  use Mojo::Base 'Mojo::Content';

=head1 DESCRIPTION

L<Mojo::Content> is an abstract base class for HTTP 1.1 content as described
in RFC 2616.

=head1 ATTRIBUTES

L<Mojo::Content> implements the following attributes.

=head2 C<auto_relax>

  my $relax = $content->auto_relax;
  $content  = $content->auto_relax(1);

Try to detect broken web servers and turn on relaxed parsing automatically.

=head2 C<headers>

  my $headers = $content->headers;
  $content    = $content->headers(Mojo::Headers->new);

Content headers, defaults to a L<Mojo::Headers> object.

=head2 C<on_read>

  my $cb   = $content->on_read;
  $content = $content->on_read(sub {...});

Callback to be invoked when new content arrives.

  $content = $content->on_read(sub {
    my ($self, $chunk) = @_;
    print $chunk;
  });

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

Check if there are leftovers.

=head2 C<header_size>

  my $size = $content->header_size;

Size of headers in bytes.

=head2 C<is_chunked>

  my $chunked = $content->is_chunked;

Check if content is chunked.

=head2 C<is_done>

  my $done = $content->is_done;

Check if parser is done.

=head2 C<is_dynamic>

  my $dynamic = $content->is_dynamic;

Check if content will be dynamic.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<is_multipart>

  my $multipart = $content->is_multipart;

Check if content is multipart.

=head2 C<is_parsing_body>

  my $body = $content->is_parsing_body;

Check if body parsing started yet.

=head2 C<leftovers>

  my $bytes = $content->leftovers;

Remove leftover data from content parser.

=head2 C<parse>

  $content = $content->parse("Content-Length: 12\r\n\r\nHello World!");

Parse content chunk.

=head2 C<parse_body>

  $content = $content->parse_body("Hi!");

Parse body chunk.

=head2 C<parse_body_once>

  $content = $content->parse_body_once("Hi!");

Parse body chunk once.

=head2 C<parse_until_body>

  $content = $content->parse_until_body(
    "Content-Length: 12\r\n\r\nHello World!"
  );

Parse chunk and stop after headers.

=head2 C<progress>

  my $bytes = $content->progress;

Number of bytes already received from message content.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<write>

  $content->write('Hello!');
  $content->write('Hello!', sub {...});

Write dynamic content, the optional drain callback will be invoked once all
data has been written.

=head2 C<write_chunk>

  $content->write_chunk('Hello!');
  $content->write_chunk('Hello!', sub {...});

Write chunked content, the optional drain callback will be invoked once all
data has been written.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
