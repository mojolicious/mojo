package Mojo::Message;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Mojo::Asset::Memory;
use Mojo::Content::Single;
use Mojo::DOM;
use Mojo::JSON 'j';
use Mojo::JSON::Pointer;
use Mojo::Parameters;
use Mojo::Upload;
use Mojo::Util 'decode';

has content => sub { Mojo::Content::Single->new };
has default_charset  => 'UTF-8';
has max_line_size    => sub { $ENV{MOJO_MAX_LINE_SIZE} || 8192 };
has max_message_size => sub { $ENV{MOJO_MAX_MESSAGE_SIZE} // 16777216 };
has version          => '1.1';

sub body {
  my $self = shift;

  # Downgrade multipart content
  my $content = $self->content;
  $content = $self->content(Mojo::Content::Single->new)->content
    if $content->is_multipart;

  # Get
  return $content->asset->slurp unless @_;

  # Set
  $content->asset(Mojo::Asset::Memory->new->add_chunk(@_));

  return $self;
}

sub body_params {
  my $self = shift;

  return $self->{body_params} if $self->{body_params};
  my $params = $self->{body_params} = Mojo::Parameters->new;
  $params->charset($self->content->charset || $self->default_charset);

  # "application/x-www-form-urlencoded"
  my $type = $self->headers->content_type // '';
  if ($type =~ m!application/x-www-form-urlencoded!i) {
    $params->parse($self->content->asset->slurp);
  }

  # "multipart/form-data"
  elsif ($type =~ m!multipart/form-data!i) {
    $params->append(@$_[0, 1]) for @{$self->_parse_formdata};
  }

  return $params;
}

sub body_size { shift->content->body_size }

sub build_body       { shift->_build('get_body_chunk') }
sub build_headers    { shift->_build('get_header_chunk') }
sub build_start_line { shift->_build('get_start_line_chunk') }

sub cookie { shift->_cache('cookie', 0, @_) }

sub cookies { croak 'Method "cookies" not implemented by subclass' }

sub dom {
  my $self = shift;
  return undef if $self->content->is_multipart;
  my $dom = $self->{dom} ||= Mojo::DOM->new($self->text);
  return @_ ? $dom->find(@_) : $dom;
}

sub error {
  my $self = shift;
  return $self->{error} unless @_;
  $self->{error} = shift;
  return $self->finish;
}

sub every_cookie { shift->_cache('cookie', 1, @_) }
sub every_upload { shift->_cache('upload', 1, @_) }

sub extract_start_line {
  croak 'Method "extract_start_line" not implemented by subclass';
}

sub finish {
  my $self = shift;
  $self->{state} = 'finished';
  return $self->{finished}++ ? $self : $self->emit('finish');
}

sub fix_headers {
  my $self = shift;
  return $self if $self->{fix}++;

  # Content-Length or Connection (unless chunked transfer encoding is used)
  my $content = $self->content;
  my $headers = $content->headers;
  if ($content->is_multipart) { $headers->remove('Content-Length') }
  elsif ($content->is_chunked || $headers->content_length) { return $self }
  if   ($content->is_dynamic) { $headers->connection('close') }
  else                        { $headers->content_length($self->body_size) }

  return $self;
}

sub get_body_chunk {
  my ($self, $offset) = @_;

  $self->emit('progress', 'body', $offset);
  my $chunk = $self->content->get_body_chunk($offset);
  return $chunk if !defined $chunk || length $chunk;
  $self->finish;

  return $chunk;
}

sub get_header_chunk {
  my ($self, $offset) = @_;
  $self->emit('progress', 'headers', $offset);
  return $self->fix_headers->content->get_header_chunk($offset);
}

sub get_start_line_chunk {
  croak 'Method "get_start_line_chunk" not implemented by subclass';
}

sub header_size { shift->fix_headers->content->header_size }

sub headers { shift->content->headers }

sub is_finished { (shift->{state} // '') eq 'finished' }

sub is_limit_exceeded { !!shift->{limit} }

sub json {
  my ($self, $pointer) = @_;
  return undef if $self->content->is_multipart;
  my $data = $self->{json} //= j($self->body);
  return $pointer ? Mojo::JSON::Pointer->new($data)->get($pointer) : $data;
}

sub parse {
  my $self = shift;

  return $self if $self->{error};
  $self->{raw_size} += length(my $chunk = shift // '');
  $self->{buffer} .= $chunk;

  # Start-line
  unless ($self->{state}) {

    # Check start-line size
    my $len = index $self->{buffer}, "\x0a";
    $len = length $self->{buffer} if $len < 0;
    return $self->_limit('Maximum start-line size exceeded')
      if $len > $self->max_line_size;

    $self->{state} = 'content' if $self->extract_start_line(\$self->{buffer});
  }

  # Content
  my $state = $self->{state} // '';
  $self->content($self->content->parse(delete $self->{buffer}))
    if $state eq 'content' || $state eq 'finished';

  # Check message size
  my $max = $self->max_message_size;
  return $self->_limit('Maximum message size exceeded')
    if $max && $max < $self->{raw_size};

  # Check header size
  return $self->_limit('Maximum header size exceeded')
    if $self->headers->is_limit_exceeded;

  # Check buffer size
  return $self->_limit('Maximum buffer size exceeded')
    if $self->content->is_limit_exceeded;

  return $self->emit('progress')->content->is_finished ? $self->finish : $self;
}

sub start_line_size { length shift->build_start_line }

sub text {
  my $self    = shift;
  my $body    = $self->body;
  my $charset = $self->content->charset;
  return $charset ? decode($charset, $body) // $body : $body;
}

sub to_string {
  my $self = shift;
  return $self->build_start_line . $self->build_headers . $self->build_body;
}

sub upload { shift->_cache('upload', 0, @_) }

sub uploads {
  my $self = shift;

  my @uploads;
  for my $data (@{$self->_parse_formdata(1)}) {
    my $upload = Mojo::Upload->new(
      name     => $data->[0],
      filename => $data->[2],
      asset    => $data->[1]->asset,
      headers  => $data->[1]->headers
    );
    push @uploads, $upload;
  }

  return \@uploads;
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

sub _cache {
  my ($self, $method, $all, $name) = @_;

  # Multiple names
  return map { $self->$method($_) } @$name if ref $name eq 'ARRAY';

  # Cache objects by name
  $method .= 's';
  unless ($self->{$method}) {
    $self->{$method} = {};
    push @{$self->{$method}{$_->name}}, $_ for @{$self->$method};
  }

  my $objects = $self->{$method}{$name} || [];
  return $all ? $objects : $objects->[-1];
}

sub _limit { ++$_[0]{limit} and return $_[0]->error({message => $_[1]}) }

sub _parse_formdata {
  my ($self, $upload) = @_;

  my @formdata;
  my $content = $self->content;
  return \@formdata unless $content->is_multipart;
  my $charset = $content->charset || $self->default_charset;

  # Check all parts recursively
  my @parts = ($content);
  while (my $part = shift @parts) {

    if ($part->is_multipart) {
      unshift @parts, @{$part->parts};
      next;
    }

    next unless my $disposition = $part->headers->content_disposition;
    my ($filename) = $disposition =~ /[; ]filename="((?:\\"|[^"])*)"/;
    next if $upload && !defined $filename || !$upload && defined $filename;
    my ($name) = $disposition =~ /[; ]name="((?:\\"|[^;"])*)"/;
    $part = $part->asset->slurp unless $upload;

    if ($charset) {
      $name     = decode($charset, $name)     // $name     if $name;
      $filename = decode($charset, $filename) // $filename if $filename;
      $part = decode($charset, $part) // $part unless $upload;
    }

    push @formdata, [$name, $part, $filename];
  }

  return \@formdata;
}

1;

=encoding utf8

=head1 NAME

Mojo::Message - HTTP message base class

=head1 SYNOPSIS

  package Mojo::Message::MyMessage;
  use Mojo::Base 'Mojo::Message';

  sub cookies              {...}
  sub extract_start_line   {...}
  sub get_start_line_chunk {...}

=head1 DESCRIPTION

L<Mojo::Message> is an abstract base class for HTTP messages based on
L<RFC 7230|http://tools.ietf.org/html/rfc7230>,
L<RFC 7231|http://tools.ietf.org/html/rfc7231> and
L<RFC 2388|http://tools.ietf.org/html/rfc2388>.

=head1 EVENTS

L<Mojo::Message> inherits all events from L<Mojo::EventEmitter> and can emit
the following new ones.

=head2 finish

  $msg->on(finish => sub {
    my $msg = shift;
    ...
  });

Emitted after message building or parsing is finished.

  my $before = time;
  $msg->on(finish => sub {
    my $msg = shift;
    $msg->headers->header('X-Parser-Time' => time - $before);
  });

=head2 progress

  $msg->on(progress => sub {
    my $msg = shift;
    ...
  });

Emitted when message building or parsing makes progress.

  # Building
  $msg->on(progress => sub {
    my ($msg, $state, $offset) = @_;
    say qq{Building "$state" at offset $offset};
  });

  # Parsing
  $msg->on(progress => sub {
    my $msg = shift;
    return unless my $len = $msg->headers->content_length;
    my $size = $msg->content->progress;
    say 'Progress: ', $size == $len ? 100 : int($size / ($len / 100)), '%';
  });

=head1 ATTRIBUTES

L<Mojo::Message> implements the following attributes.

=head2 content

  my $msg = $msg->content;
  $msg    = $msg->content(Mojo::Content::Single->new);

Message content, defaults to a L<Mojo::Content::Single> object.

=head2 default_charset

  my $charset = $msg->default_charset;
  $msg        = $msg->default_charset('UTF-8');

Default charset used for form-data parsing, defaults to C<UTF-8>.

=head2 max_line_size

  my $size = $msg->max_line_size;
  $msg     = $msg->max_line_size(1024);

Maximum start-line size in bytes, defaults to the value of the
C<MOJO_MAX_LINE_SIZE> environment variable or C<8192> (8KB).

=head2 max_message_size

  my $size = $msg->max_message_size;
  $msg     = $msg->max_message_size(1024);

Maximum message size in bytes, defaults to the value of the
C<MOJO_MAX_MESSAGE_SIZE> environment variable or C<16777216> (16MB). Setting
the value to C<0> will allow messages of indefinite size. Note that increasing
this value can also drastically increase memory usage, should you for example
attempt to parse an excessively large message body with the L</"body_params">,
L</"dom"> or L</"json"> methods.

=head2 version

  my $version = $msg->version;
  $msg        = $msg->version('1.1');

HTTP version of message, defaults to C<1.1>.

=head1 METHODS

L<Mojo::Message> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 body

  my $bytes = $msg->body;
  $msg      = $msg->body('Hello!');

Slurp or replace L</"content">, L<Mojo::Content::MultiPart> will be
automatically downgraded to L<Mojo::Content::Single>.

=head2 body_params

  my $params = $msg->body_params;

C<POST> parameters extracted from C<application/x-www-form-urlencoded> or
C<multipart/form-data> message body, usually a L<Mojo::Parameters> object.
Note that this method caches all data, so it should not be called before the
entire message body has been received. Parts of the message body need to be
loaded into memory to parse C<POST> parameters, so you have to make sure it is
not excessively large, there's a 16MB limit by default.

  # Get POST parameter names and values
  my $hash = $msg->body_params->to_hash;

=head2 body_size

  my $size = $msg->body_size;

Content size in bytes.

=head2 build_body

  my $bytes = $msg->build_body;

Render whole body.

=head2 build_headers

  my $bytes = $msg->build_headers;

Render all headers.

=head2 build_start_line

  my $bytes = $msg->build_start_line;

Render start-line.

=head2 cookie

  my $cookie      = $msg->cookie('foo');
  my ($foo, $bar) = $msg->cookie(['foo', 'bar']);

Access message cookies, usually L<Mojo::Cookie::Request> or
L<Mojo::Cookie::Response> objects. If there are multiple cookies sharing the
same name, and you want to access more than just the last one, you can use
L</"every_cookie">. Note that this method caches all data, so it should not be
called before all headers have been received.

  # Get cookie value
  say $msg->cookie('foo')->value;

=head2 cookies

  my $cookies = $msg->cookies;

Access message cookies. Meant to be overloaded in a subclass.

=head2 dom

  my $dom        = $msg->dom;
  my $collection = $msg->dom('a[href]');

Turns message body into a L<Mojo::DOM> object and takes an optional selector
to call the method L<Mojo::DOM/"find"> on it right away, which returns a
L<Mojo::Collection> object. Note that this method caches all data, so it
should not be called before the entire message body has been received. The
whole message body needs to be loaded into memory to parse it, so you have to
make sure it is not excessively large, there's a 16MB limit by default.

  # Perform "find" right away
  say $msg->dom('h1, h2, h3')->map('text')->join("\n");

  # Use everything else Mojo::DOM has to offer
  say $msg->dom->at('title')->text;
  say $msg->dom->at('body')->children->map('type')->uniq->join("\n");

=head2 error

  my $err = $msg->error;
  $msg    = $msg->error({message => 'Parser error'});

Get or set message error, an C<undef> return value indicates that there is no
error.

  # Connection or parser error
  $msg->error({message => 'Connection refused'});

  # 4xx/5xx response
  $msg->error({message => 'Internal Server Error', code => 500});

=head2 every_cookie

  my $cookies = $msg->every_cookie('foo');

Similar to L</"cookie">, but returns all message cookies sharing the same name
as an array reference.

  # Get first cookie value
  say $msg->every_cookie('foo')->[0]->value;

=head2 every_upload

  my $uploads = $msg->every_upload('foo');

Similar to L</"upload">, but returns all file uploads sharing the same name as
an array reference.

  # Get content of first uploaded file
  say $msg->every_upload('foo')->[0]->asset->slurp;

=head2 extract_start_line

  my $bool = $msg->extract_start_line(\$str);

Extract start-line from string. Meant to be overloaded in a subclass.

=head2 finish

  $msg = $msg->finish;

Finish message parser/generator.

=head2 fix_headers

  $msg = $msg->fix_headers;

Make sure message has all required headers.

=head2 get_body_chunk

  my $bytes = $msg->get_body_chunk($offset);

Get a chunk of body data starting from a specific position.

=head2 get_header_chunk

  my $bytes = $msg->get_header_chunk($offset);

Get a chunk of header data, starting from a specific position.

=head2 get_start_line_chunk

  my $bytes = $msg->get_start_line_chunk($offset);

Get a chunk of start-line data starting from a specific position. Meant to be
overloaded in a subclass.

=head2 header_size

  my $size = $msg->header_size;

Size of headers in bytes.

=head2 headers

  my $headers = $msg->headers;

Message headers, usually a L<Mojo::Headers> object.

=head2 is_finished

  my $bool = $msg->is_finished;

Check if message parser/generator is finished.

=head2 is_limit_exceeded

  my $bool = $msg->is_limit_exceeded;

Check if message has exceeded L</"max_line_size">, L</"max_message_size">,
L<Mojo::Content/"max_buffer_size"> or L<Mojo::Headers/"max_line_size">.

=head2 json

  my $value = $msg->json;
  my $value = $msg->json('/foo/bar');

Decode JSON message body directly using L<Mojo::JSON> if possible, an C<undef>
return value indicates a bare C<null> or that decoding failed. An optional
JSON Pointer can be used to extract a specific value with
L<Mojo::JSON::Pointer>. Note that this method caches all data, so it should
not be called before the entire message body has been received. The whole
message body needs to be loaded into memory to parse it, so you have to make
sure it is not excessively large, there's a 16MB limit by default.

  # Extract JSON values
  say $msg->json->{foo}{bar}[23];
  say $msg->json('/foo/bar/23');

=head2 parse

  $msg = $msg->parse('HTTP/1.1 200 OK...');

Parse message chunk.

=head2 start_line_size

  my $size = $msg->start_line_size;

Size of the start-line in bytes.

=head2 text

  my $str = $msg->text;

Retrieve L</"body"> and try to decode it if a charset could be extracted with
L<Mojo::Content/"charset">.

=head2 to_string

  my $str = $msg->to_string;

Render whole message.

=head2 upload

  my $upload      = $msg->upload('foo');
  my ($foo, $bar) = $msg->upload(['foo', 'bar']);

Access C<multipart/form-data> file uploads, usually L<Mojo::Upload> objects.
If there are multiple uploads sharing the same name, and you want to access
more than just the last one, you can use L</"every_upload">. Note that this
method caches all data, so it should not be called before the entire message
body has been received.

  # Get content of uploaded file
  say $msg->upload('foo')->asset->slurp;

=head2 uploads

  my $uploads = $msg->uploads;

All C<multipart/form-data> file uploads, usually L<Mojo::Upload> objects.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
