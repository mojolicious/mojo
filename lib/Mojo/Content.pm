package Mojo::Content;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Compress::Raw::Zlib qw(WANT_GZIP Z_STREAM_END);
use Mojo::Headers;

has [qw(auto_relax relaxed skip_body)];
has headers           => sub { Mojo::Headers->new };
has max_buffer_size   => sub { $ENV{MOJO_MAX_BUFFER_SIZE} || 262144 };
has max_leftover_size => sub { $ENV{MOJO_MAX_LEFTOVER_SIZE} || 262144 };

sub body_contains {
  croak 'Method "body_contains" not implemented by subclass';
}

sub body_size { croak 'Method "body_size" not implemented by subclass' }

sub boundary {
  return undef unless my $type = shift->headers->content_type;
  $type =~ m!multipart.*boundary=(?:"([^"]+)"|([\w'(),.:?\-+/]+))!i
    and return $1 // $2;
  return undef;
}

sub build_body    { shift->_build('get_body_chunk') }
sub build_headers { shift->_build('get_header_chunk') }

sub charset {
  my $type = shift->headers->content_type // '';
  return $type =~ /charset="?([^"\s;]+)"?/i ? $1 : undef;
}

sub clone {
  my $self = shift;
  return undef if $self->is_dynamic;
  return $self->new(headers => $self->headers->clone);
}

sub generate_body_chunk {
  my ($self, $offset) = @_;

  $self->emit(drain => $offset)
    if !delete $self->{delay} && !length($self->{body_buffer} // '');
  my $chunk = delete $self->{body_buffer} // '';
  return $self->{eof} ? '' : undef unless length $chunk;

  return $chunk;
}

sub get_body_chunk {
  croak 'Method "get_body_chunk" not implemented by subclass';
}

sub get_header_chunk {
  my ($self, $offset) = @_;

  unless (defined $self->{header_buffer}) {
    my $headers = $self->headers->to_string;
    $self->{header_buffer}
      = $headers ? "$headers\x0d\x0a\x0d\x0a" : "\x0d\x0a";
  }

  return substr $self->{header_buffer}, $offset, 131072;
}

sub header_size { length shift->build_headers }

sub is_chunked { !!shift->headers->transfer_encoding }

sub is_compressed { (shift->headers->content_encoding // '') =~ /^gzip$/i }

sub is_dynamic { $_[0]{dynamic} && !defined $_[0]->headers->content_length }

sub is_finished { (shift->{state} // '') eq 'finished' }

sub is_limit_exceeded { !!shift->{limit} }

sub is_multipart {undef}

sub is_parsing_body { (shift->{state} // '') eq 'body' }

sub leftovers { shift->{buffer} }

sub parse {
  my $self = shift;

  # Headers
  $self->_parse_until_body(@_);
  return $self if $self->{state} eq 'headers';
  $self->emit('body') unless $self->{body}++;

  # Chunked content
  $self->{real_size} //= 0;
  if ($self->is_chunked && $self->{state} ne 'headers') {
    $self->_parse_chunked;
    $self->{state} = 'finished' if ($self->{chunk_state} // '') eq 'finished';
  }

  # Not chunked, pass through to second buffer
  else {
    $self->{real_size} += length $self->{pre_buffer};
    my $limit = $self->is_finished
      && length($self->{buffer}) > $self->max_leftover_size;
    $self->{buffer} .= $self->{pre_buffer} unless $limit;
    $self->{pre_buffer} = '';
  }

  # No content
  if ($self->skip_body) {
    $self->{state} = 'finished';
    return $self;
  }

  # Relaxed parsing
  my $headers = $self->headers;
  if ($self->auto_relax) {
    my $connection = $headers->connection     // '';
    my $len        = $headers->content_length // '';
    $self->relaxed(1)
      if !length $len && ($connection =~ /close/i || $headers->content_type);
  }

  # Chunked or relaxed content
  if ($self->is_chunked || $self->relaxed) {
    $self->{size} += length($self->{buffer} //= '');
    $self->_uncompress($self->{buffer});
    $self->{buffer} = '';
  }

  # Normal content
  else {
    my $len = $headers->content_length || 0;
    $self->{size} ||= 0;
    if ((my $need = $len - $self->{size}) > 0) {
      my $len = length $self->{buffer};
      my $chunk = substr $self->{buffer}, 0, $need > $len ? $len : $need, '';
      $self->_uncompress($chunk);
      $self->{size} += length $chunk;
    }
    $self->{state} = 'finished' if $len <= $self->progress;
  }

  return $self;
}

sub parse_body {
  my $self = shift;
  $self->{state} = 'body';
  return $self->parse(@_);
}

sub progress {
  my $self = shift;
  return 0 unless my $state = $self->{state};
  return 0 unless $state eq 'body' || $state eq 'finished';
  return $self->{raw_size} - ($self->{header_size} || 0);
}

sub write {
  my ($self, $chunk, $cb) = @_;

  $self->{dynamic} = 1;
  if (defined $chunk) { $self->{body_buffer} .= $chunk }
  else                { $self->{delay} = 1 }
  $self->once(drain => $cb) if $cb;
  $self->{eof} = 1 if defined $chunk && $chunk eq '';

  return $self;
}

sub write_chunk {
  my ($self, $chunk, $cb) = @_;
  $self->headers->transfer_encoding('chunked') unless $self->is_chunked;
  $self->write(defined $chunk ? $self->_build_chunk($chunk) : $chunk, $cb);
  $self->{eof} = 1 if defined $chunk && $chunk eq '';
  return $self;
}

sub _build {
  my ($self, $method) = @_;

  my $buffer = '';
  my $offset = 0;
  while (1) {

    # No chunk yet, try again
    next unless defined(my $chunk = $self->$method($offset));

    # End of part
    last unless my $len = length $chunk;

    $offset += $len;
    $buffer .= $chunk;
  }

  return $buffer;
}

sub _build_chunk {
  my ($self, $chunk) = @_;

  # End
  return "\x0d\x0a0\x0d\x0a\x0d\x0a" if length $chunk == 0;

  # First chunk has no leading CRLF
  my $crlf = $self->{chunks}++ ? "\x0d\x0a" : '';
  return $crlf . sprintf('%x', length $chunk) . "\x0d\x0a$chunk";
}

sub _parse_chunked {
  my $self = shift;

  # Trailing headers
  return $self->_parse_chunked_trailing_headers
    if ($self->{chunk_state} // '') eq 'trailing_headers';

  while (my $len = length $self->{pre_buffer}) {

    # Start new chunk (ignore the chunk extension)
    unless ($self->{chunk_len}) {
      last
        unless $self->{pre_buffer} =~ s/^(?:\x0d?\x0a)?([[:xdigit:]]+).*\x0a//;
      next if $self->{chunk_len} = hex $1;

      # Last chunk
      $self->{chunk_state} = 'trailing_headers';
      last;
    }

    # Remove as much as possible from payload
    $len = $self->{chunk_len} if $self->{chunk_len} < $len;
    $self->{buffer} .= substr $self->{pre_buffer}, 0, $len, '';
    $self->{real_size} += $len;
    $self->{chunk_len} -= $len;
  }

  # Trailing headers
  $self->_parse_chunked_trailing_headers
    if ($self->{chunk_state} // '') eq 'trailing_headers';

  # Check buffer size
  $self->{limit} = $self->{state} = 'finished'
    if length($self->{pre_buffer} // '') > $self->max_buffer_size;
}

sub _parse_chunked_trailing_headers {
  my $self = shift;

  my $headers = $self->headers->parse(delete $self->{pre_buffer});
  return unless $headers->is_finished;
  $self->{chunk_state} = 'finished';

  # Replace Transfer-Encoding with Content-Length
  $headers->remove('Transfer-Encoding');
  $headers->content_length($self->{real_size}) unless $headers->content_length;
}

sub _parse_headers {
  my $self = shift;

  my $headers = $self->headers->parse(delete $self->{pre_buffer});
  return unless $headers->is_finished;
  $self->{state} = 'body';

  # Take care of leftovers
  my $leftovers = $self->{pre_buffer} = $headers->leftovers;
  $self->{header_size} = $self->{raw_size} - length $leftovers;
  $self->emit('body') unless $self->{body}++;
}

sub _parse_until_body {
  my ($self, $chunk) = @_;

  $self->{raw_size} += length($chunk //= '');
  $self->{pre_buffer} .= $chunk;

  unless ($self->{state}) {
    $self->{header_size} = $self->{raw_size} - length $self->{pre_buffer};
    $self->{state}       = 'headers';
  }
  $self->_parse_headers if ($self->{state} // '') eq 'headers';
}

sub _uncompress {
  my ($self, $chunk) = @_;

  # No compression
  return $self->emit(read => $chunk) unless $self->is_compressed;

  # Uncompress
  $self->{post_buffer} .= $chunk;
  my $gz = $self->{gz}
    //= Compress::Raw::Zlib::Inflate->new(WindowBits => WANT_GZIP);
  my $status = $gz->inflate(\$self->{post_buffer}, my $out);
  $self->emit(read => $out) if defined $out;

  # Replace Content-Encoding with Content-Length
  $self->headers->content_length($gz->total_out)->remove('Content-Encoding')
    if $status == Z_STREAM_END;

  # Check buffer size
  $self->{limit} = $self->{state} = 'finished'
    if length($self->{post_buffer} // '') > $self->max_buffer_size;
}

1;

=head1 NAME

Mojo::Content - HTTP content base class

=head1 SYNOPSIS

  package Mojo::Content::MyContent;
  use Mojo::Base 'Mojo::Content';

  sub body_contains  {...}
  sub body_size      {...}
  sub get_body_chunk {...}

=head1 DESCRIPTION

L<Mojo::Content> is an abstract base class for HTTP content as described in
RFC 2616.

=head1 EVENTS

L<Mojo::Content> inherits all events from L<Mojo::EventEmitter> and can emit
the following new ones.

=head2 body

  $content->on(body => sub {
    my $content = shift;
    ...
  });

Emitted once all headers have been parsed and the body starts.

  $content->on(body => sub {
    my $content = shift;
    $content->auto_upgrade(0) if $content->headers->header('X-No-MultiPart');
  });

=head2 drain

  $content->on(drain => sub {
    my ($content, $offset) = @_;
    ...
  });

Emitted once all data has been written.

  $content->on(drain => sub {
    my $content = shift;
    $content->write_chunk(time);
  });

=head2 read

  $content->on(read => sub {
    my ($content, $bytes) = @_;
    ...
  });

Emitted when a new chunk of content arrives.

  $content->unsubscribe('read');
  $content->on(read => sub {
    my ($content, $bytes) = @_;
    say "Streaming: $bytes";
  });

=head1 ATTRIBUTES

L<Mojo::Content> implements the following attributes.

=head2 auto_relax

  my $relax = $content->auto_relax;
  $content  = $content->auto_relax(1);

Try to detect when relaxed parsing is necessary.

=head2 headers

  my $headers = $content->headers;
  $content    = $content->headers(Mojo::Headers->new);

Content headers, defaults to a L<Mojo::Headers> object.

=head2 max_buffer_size

  my $size = $content->max_buffer_size;
  $content = $content->max_buffer_size(1024);

Maximum size in bytes of buffer for content parser, defaults to the value of
the MOJO_MAX_BUFFER_SIZE environment variable or C<262144>.

=head2 max_leftover_size

  my $size = $content->max_leftover_size;
  $content = $content->max_leftover_size(1024);

Maximum size in bytes of buffer for pipelined HTTP requests, defaults to the
value of the MOJO_MAX_LEFTOVER_SIZE environment variable or C<262144>.

=head2 relaxed

  my $relaxed = $content->relaxed;
  $content    = $content->relaxed(1);

Activate relaxed parsing for responses that are terminated with a connection
close.

=head2 skip_body

  my $skip = $content->skip_body;
  $content = $content->skip_body(1);

Skip body parsing and finish after headers.

=head1 METHODS

L<Mojo::Content> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 body_contains

  my $success = $content->body_contains('foo bar baz');

Check if content contains a specific string. Meant to be overloaded in a
subclass.

=head2 body_size

  my $size = $content->body_size;

Content size in bytes. Meant to be overloaded in a subclass.

=head2 boundary

  my $boundary = $content->boundary;

Extract multipart boundary from C<Content-Type> header.

=head2 build_body

  my $str = $content->build_body;

Render whole body.

=head2 build_headers

  my $str = $content->build_headers;

Render all headers.

=head2 charset

  my $charset = $content->charset;

Extract charset from C<Content-Type> header.

=head2 clone

  my $clone = $content->clone;

Clone content if possible, otherwise return C<undef>.

=head2 generate_body_chunk

  my $bytes = $content->generate_body_chunk(0);

Generate dynamic content.

=head2 get_body_chunk

  my $bytes = $content->get_body_chunk(0);

Get a chunk of content starting from a specific position. Meant to be
overloaded in a subclass.

=head2 get_header_chunk

  my $bytes = $content->get_header_chunk(13);

Get a chunk of the headers starting from a specific position.

=head2 header_size

  my $size = $content->header_size;

Size of headers in bytes.

=head2 is_chunked

  my $success = $content->is_chunked;

Check if content is chunked.

=head2 is_compressed

  my $success = $content->is_compressed;

Check if content is C<gzip> compressed.

=head2 is_dynamic

  my $success = $content->is_dynamic;

Check if content will be dynamically generated, which prevents C<clone> from
working.

=head2 is_finished

  my $success = $content->is_finished;

Check if parser is finished.

=head2 is_limit_exceeded

  my $success = $content->is_limit_exceeded;

Check if buffer has exceeded C<max_buffer_size>.

=head2 is_multipart

  my $false = $content->is_multipart;

False.

=head2 is_parsing_body

  my $success = $content->is_parsing_body;

Check if body parsing started yet.

=head2 leftovers

  my $bytes = $content->leftovers;

Get leftover data from content parser.

=head2 parse

  $content
    = $content->parse("Content-Length: 12\x0d\x0a\x0d\x0aHello World!");

Parse content chunk.

=head2 parse_body

  $content = $content->parse_body('Hi!');

Parse body chunk and skip headers.

=head2 progress

  my $size = $content->progress;

Size of content already received from message in bytes.

=head2 write

  $content = $content->write($bytes);
  $content = $content->write($bytes => sub {...});

Write dynamic content non-blocking, the optional drain callback will be
invoked once all data has been written.

=head2 write_chunk

  $content = $content->write_chunk($bytes);
  $content = $content->write_chunk($bytes => sub {...});

Write dynamic content non-blocking with C<chunked> transfer encoding, the
optional drain callback will be invoked once all data has been written.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
