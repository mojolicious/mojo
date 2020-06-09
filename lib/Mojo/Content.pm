package Mojo::Content;
use Mojo::Base 'Mojo::EventEmitter';

use Carp qw(croak);
use Compress::Raw::Zlib qw(WANT_GZIP Z_STREAM_END);
use Mojo::Headers;
use Scalar::Util qw(looks_like_number);

has [qw(auto_decompress auto_relax relaxed skip_body)];
has headers           => sub { Mojo::Headers->new };
has max_buffer_size   => sub { $ENV{MOJO_MAX_BUFFER_SIZE} || 262144 };
has max_leftover_size => sub { $ENV{MOJO_MAX_LEFTOVER_SIZE} || 262144 };

my $BOUNDARY_RE = qr!multipart.*boundary\s*=\s*(?:"([^"]+)"|([\w'(),.:?\-+/]+))!i;

sub body_contains { croak 'Method "body_contains" not implemented by subclass' }
sub body_size     { croak 'Method "body_size" not implemented by subclass' }

sub boundary { (shift->headers->content_type // '') =~ $BOUNDARY_RE ? $1 // $2 : undef }

sub charset {
  my $type = shift->headers->content_type // '';
  return $type =~ /charset\s*=\s*"?([^"\s;]+)"?/i ? $1 : undef;
}

sub clone {
  my $self = shift;
  return undef if $self->is_dynamic;
  return $self->new(headers => $self->headers->clone);
}

sub generate_body_chunk {
  my ($self, $offset) = @_;

  $self->emit(drain => $offset) unless length($self->{body_buffer} //= '');
  return delete $self->{body_buffer} if length $self->{body_buffer};
  return ''                          if $self->{eof};

  my $len = $self->headers->content_length;
  return looks_like_number $len && $len == $offset ? '' : undef;
}

sub get_body_chunk { croak 'Method "get_body_chunk" not implemented by subclass' }

sub get_header_chunk { substr shift->_headers->{header_buffer}, shift, 131072 }

sub header_size { length shift->_headers->{header_buffer} }

sub headers_contain { index(shift->_headers->{header_buffer}, shift) >= 0 }

sub is_chunked { !!shift->headers->transfer_encoding }

sub is_compressed { lc(shift->headers->content_encoding // '') eq 'gzip' }

sub is_dynamic { !!$_[0]{dynamic} }

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

  # Chunked content
  $self->{real_size} //= 0;
  if ($self->is_chunked && $self->{state} ne 'headers') {
    $self->_parse_chunked;
    $self->{state} = 'finished' if ($self->{chunk_state} // '') eq 'finished';
  }

  # Not chunked, pass through to second buffer
  else {
    $self->{real_size} += length $self->{pre_buffer};
    my $limit = $self->is_finished && length($self->{buffer}) > $self->max_leftover_size;
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
  my $len     = $headers->content_length // '';
  if ($self->auto_relax && !length $len) {
    my $connection = lc($headers->connection // '');
    $self->relaxed(1) if $connection eq 'close' || !$connection;
  }

  # Chunked or relaxed content
  if ($self->is_chunked || $self->relaxed) {
    $self->_decompress($self->{buffer} //= '');
    $self->{size} += length $self->{buffer};
    $self->{buffer} = '';
    return $self;
  }

  # Normal content
  $len = 0 unless looks_like_number $len;
  if ((my $need = $len - ($self->{size} ||= 0)) > 0) {
    my $len   = length $self->{buffer};
    my $chunk = substr $self->{buffer}, 0, $need > $len ? $len : $need, '';
    $self->_decompress($chunk);
    $self->{size} += length $chunk;
  }
  $self->{state} = 'finished' if $len <= $self->progress;

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
  $self->{body_buffer} .= $chunk if defined $chunk;
  $self->once(drain => $cb) if $cb;
  $self->{eof} = 1 if defined $chunk && !length $chunk;

  return $self;
}

sub write_chunk {
  my ($self, $chunk, $cb) = @_;

  $self->headers->transfer_encoding('chunked') unless $self->{chunked};
  @{$self}{qw(chunked dynamic)} = (1, 1);

  $self->{body_buffer} .= $self->_build_chunk($chunk) if defined $chunk;
  $self->once(drain => $cb) if $cb;
  $self->{eof} = 1 if defined $chunk && !length $chunk;

  return $self;
}

sub _build_chunk {
  my ($self, $chunk) = @_;

  # End
  return "\x0d\x0a0\x0d\x0a\x0d\x0a" unless length $chunk;

  # First chunk has no leading CRLF
  my $crlf = $self->{chunks}++ ? "\x0d\x0a" : '';
  return $crlf . sprintf('%x', length $chunk) . "\x0d\x0a$chunk";
}

sub _decompress {
  my ($self, $chunk) = @_;

  # No compression
  return $self->emit(read => $chunk) unless $self->auto_decompress && $self->is_compressed;

  # Decompress
  $self->{post_buffer} .= $chunk;
  my $gz     = $self->{gz} //= Compress::Raw::Zlib::Inflate->new(WindowBits => WANT_GZIP);
  my $status = $gz->inflate(\$self->{post_buffer}, my $out);
  $self->emit(read => $out) if defined $out;

  # Replace Content-Encoding with Content-Length
  $self->headers->content_length($gz->total_out)->remove('Content-Encoding') if $status == Z_STREAM_END;

  # Check buffer size
  @$self{qw(state limit)} = ('finished', 1) if length($self->{post_buffer} // '') > $self->max_buffer_size;
}

sub _headers {
  my $self = shift;
  return $self if defined $self->{header_buffer};
  my $headers = $self->headers->to_string;
  $self->{header_buffer} = $headers ? "$headers\x0d\x0a\x0d\x0a" : "\x0d\x0a";
  return $self;
}

sub _parse_chunked {
  my $self = shift;

  # Trailing headers
  return $self->_parse_chunked_trailing_headers if ($self->{chunk_state} // '') eq 'trailing_headers';

  while (my $len = length $self->{pre_buffer}) {

    # Start new chunk (ignore the chunk extension)
    unless ($self->{chunk_len}) {
      last unless $self->{pre_buffer} =~ s/^(?:\x0d?\x0a)?([0-9a-fA-F]+).*\x0a//;
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
  $self->_parse_chunked_trailing_headers if ($self->{chunk_state} // '') eq 'trailing_headers';

  # Check buffer size
  @$self{qw(state limit)} = ('finished', 1) if length($self->{pre_buffer} // '') > $self->max_buffer_size;
}

sub _parse_chunked_trailing_headers {
  my $self = shift;

  my $headers = $self->headers->parse(delete $self->{pre_buffer});
  return unless $headers->is_finished;
  $self->{chunk_state} = 'finished';

  # Take care of leftover and replace Transfer-Encoding with Content-Length
  $self->{buffer} .= $headers->leftovers;
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
}

sub _parse_until_body {
  my ($self, $chunk) = @_;

  $self->{raw_size} += length($chunk //= '');
  $self->{pre_buffer} .= $chunk;
  $self->_parse_headers if ($self->{state} ||= 'headers') eq 'headers';
  $self->emit('body')   if $self->{state} ne 'headers' && !$self->{body}++;
}

1;

=encoding utf8

=head1 NAME

Mojo::Content - HTTP content base class

=head1 SYNOPSIS

  package Mojo::Content::MyContent;
  use Mojo::Base 'Mojo::Content';

  sub body_contains  {...}
  sub body_size      {...}
  sub get_body_chunk {...}

=head1 DESCRIPTION

L<Mojo::Content> is an abstract base class for HTTP content containers, based on L<RFC
7230|http://tools.ietf.org/html/rfc7230> and L<RFC 7231|http://tools.ietf.org/html/rfc7231>, like
L<Mojo::Content::MultiPart> and L<Mojo::Content::Single>.

=head1 EVENTS

L<Mojo::Content> inherits all events from L<Mojo::EventEmitter> and can emit the following new ones.

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

  $content->on(read => sub {
    my ($content, $bytes) = @_;
    say "Streaming: $bytes";
  });

=head1 ATTRIBUTES

L<Mojo::Content> implements the following attributes.

=head2 auto_decompress

  my $bool = $content->auto_decompress;
  $content = $content->auto_decompress($bool);

Decompress content automatically if L</"is_compressed"> is true.

=head2 auto_relax

  my $bool = $content->auto_relax;
  $content = $content->auto_relax($bool);

Try to detect when relaxed parsing is necessary.

=head2 headers

  my $headers = $content->headers;
  $content    = $content->headers(Mojo::Headers->new);

Content headers, defaults to a L<Mojo::Headers> object.

=head2 max_buffer_size

  my $size = $content->max_buffer_size;
  $content = $content->max_buffer_size(1024);

Maximum size in bytes of buffer for content parser, defaults to the value of the C<MOJO_MAX_BUFFER_SIZE> environment
variable or C<262144> (256KiB).

=head2 max_leftover_size

  my $size = $content->max_leftover_size;
  $content = $content->max_leftover_size(1024);

Maximum size in bytes of buffer for pipelined HTTP requests, defaults to the value of the C<MOJO_MAX_LEFTOVER_SIZE>
environment variable or C<262144> (256KiB).

=head2 relaxed

  my $bool = $content->relaxed;
  $content = $content->relaxed($bool);

Activate relaxed parsing for responses that are terminated with a connection close.

=head2 skip_body

  my $bool = $content->skip_body;
  $content = $content->skip_body($bool);

Skip body parsing and finish after headers.

=head1 METHODS

L<Mojo::Content> inherits all methods from L<Mojo::EventEmitter> and implements the following new ones.

=head2 body_contains

  my $bool = $content->body_contains('foo bar baz');

Check if content contains a specific string. Meant to be overloaded in a subclass.

=head2 body_size

  my $size = $content->body_size;

Content size in bytes. Meant to be overloaded in a subclass.

=head2 boundary

  my $boundary = $content->boundary;

Extract multipart boundary from C<Content-Type> header.

=head2 charset

  my $charset = $content->charset;

Extract charset from C<Content-Type> header.

=head2 clone

  my $clone = $content->clone;

Return a new L<Mojo::Content> object cloned from this content if possible, otherwise return C<undef>.

=head2 generate_body_chunk

  my $bytes = $content->generate_body_chunk(0);

Generate dynamic content.

=head2 get_body_chunk

  my $bytes = $content->get_body_chunk(0);

Get a chunk of content starting from a specific position. Meant to be overloaded in a subclass.

=head2 get_header_chunk

  my $bytes = $content->get_header_chunk(13);

Get a chunk of the headers starting from a specific position. Note that this method finalizes the content.

=head2 header_size

  my $size = $content->header_size;

Size of headers in bytes. Note that this method finalizes the content.

=head2 headers_contain

  my $bool = $content->headers_contain('foo bar baz');

Check if headers contain a specific string. Note that this method finalizes the content.

=head2 is_chunked

  my $bool = $content->is_chunked;

Check if C<Transfer-Encoding> header indicates chunked transfer encoding.

=head2 is_compressed

  my $bool = $content->is_compressed;

Check C<Content-Encoding> header for C<gzip> value.

=head2 is_dynamic

  my $bool = $content->is_dynamic;

Check if content will be dynamically generated, which prevents L</"clone"> from working.

=head2 is_finished

  my $bool = $content->is_finished;

Check if parser is finished.

=head2 is_limit_exceeded

  my $bool = $content->is_limit_exceeded;

Check if buffer has exceeded L</"max_buffer_size">.

=head2 is_multipart

  my $bool = $content->is_multipart;

False, this is not a L<Mojo::Content::MultiPart> object.

=head2 is_parsing_body

  my $bool = $content->is_parsing_body;

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

  $content = $content->write;
  $content = $content->write('');
  $content = $content->write($bytes);
  $content = $content->write($bytes => sub {...});

Write dynamic content non-blocking, the optional drain callback will be executed once all data has been written.
Calling this method without a chunk of data will finalize the L</"headers"> and allow for dynamic content to be written
later. You can write an empty chunk of data at any time to end the stream.

  # Make sure previous chunk of data has been written before continuing
  $content->write('He' => sub {
    my $content = shift;
    $content->write('llo!' => sub {
      my $content = shift;
      $content->write('');
    });
  });

=head2 write_chunk

  $content = $content->write_chunk;
  $content = $content->write_chunk('');
  $content = $content->write_chunk($bytes);
  $content = $content->write_chunk($bytes => sub {...});

Write dynamic content non-blocking with chunked transfer encoding, the optional drain callback will be executed once
all data has been written. Calling this method without a chunk of data will finalize the L</"headers"> and allow for
dynamic content to be written later. You can write an empty chunk of data at any time to end the stream.

  # Make sure previous chunk of data has been written before continuing
  $content->write_chunk('He' => sub {
    my $content = shift;
    $content->write_chunk('llo!' => sub {
      my $content = shift;
      $content->write_chunk('');
    });
  });

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
