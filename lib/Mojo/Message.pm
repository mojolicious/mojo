package Mojo::Message;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Mojo::Asset::Memory;
use Mojo::Content::Single;
use Mojo::DOM;
use Mojo::JSON;
use Mojo::JSON::Pointer;
use Mojo::Parameters;
use Mojo::Upload;
use Mojo::Util 'decode';

has content => sub { Mojo::Content::Single->new };
has default_charset  => 'UTF-8';
has max_line_size    => sub { $ENV{MOJO_MAX_LINE_SIZE} || 10240 };
has max_message_size => sub { $ENV{MOJO_MAX_MESSAGE_SIZE} || 5242880 };
has version          => '1.1';

sub body {
  my $self = shift;

  # Downgrade multipart content
  my $content = $self->content;
  $content = $self->content(Mojo::Content::Single->new)->content
    if $content->is_multipart;

  # Get
  return $content->asset->slurp unless @_;

  # Set raw content
  $content->asset(Mojo::Asset::Memory->new->add_chunk(@_));

  return $self;
}

sub body_params {
  my $self = shift;

  return $self->{body_params} if $self->{body_params};
  my $params = $self->{body_params} = Mojo::Parameters->new;
  $params->charset($self->content->charset || $self->default_charset);

  # "x-application-urlencoded" and "application/x-www-form-urlencoded"
  my $type = $self->headers->content_type // '';
  if ($type =~ m!(?:x-application|application/x-www-form)-urlencoded!i) {
    $params->parse($self->content->asset->slurp);
  }

  # "multipart/formdata"
  elsif ($type =~ m!multipart/form-data!i) {
    for my $data (@{$self->_parse_formdata}) {
      $params->append($data->[0], $data->[2]) unless defined $data->[1];
    }
  }

  return $params;
}

sub body_size { shift->content->body_size }

sub build_body       { shift->_build('get_body_chunk') }
sub build_headers    { shift->_build('get_header_chunk') }
sub build_start_line { shift->_build('get_start_line_chunk') }

sub cookie { shift->_cache(cookies => @_) }

sub cookies { croak 'Method "cookies" not implemented by subclass' }

sub dom {
  my $self = shift;

  return undef if $self->content->is_multipart;
  my $html    = $self->body;
  my $charset = $self->content->charset;
  $html = decode($charset, $html) // $html if $charset;
  my $dom = $self->{dom} ||= Mojo::DOM->new($html);

  return @_ ? $dom->find(@_) : $dom;
}

sub error {
  my $self = shift;

  # Set
  if (@_) {
    $self->{error} = [@_];
    return $self->finish;
  }

  # Get
  return unless my $err = $self->{error};
  return wantarray ? @$err : $err->[0];
}

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

  # Content-Length or Connection (unless chunked transfer encoding is used)
  my $content = $self->content;
  return $self if $self->{fix}++ || $content->is_chunked;
  my $headers = $self->headers;
  $content->is_dynamic
    ? $headers->connection('close')
    : $headers->content_length($self->body_size)
    unless $headers->content_length;

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
  my $data = $self->{json} ||= Mojo::JSON->new->decode($self->body);
  return $pointer ? Mojo::JSON::Pointer->new->get($data, $pointer) : $data;
}

sub param { shift->body_params->param(@_) }

sub parse {
  my ($self, $chunk) = @_;

  # Check message size
  return $self->_limit('Maximum message size exceeded', 413)
    if ($self->{raw_size} += length($chunk //= '')) > $self->max_message_size;

  $self->{buffer} .= $chunk;

  # Start line
  unless ($self->{state}) {

    # Check line size
    my $len = index $self->{buffer}, "\x0a";
    $len = length $self->{buffer} if $len < 0;
    return $self->_limit('Maximum line size exceeded', 431)
      if $len > $self->max_line_size;

    $self->{state} = 'content' if $self->extract_start_line(\$self->{buffer});
  }

  # Content
  my $state = $self->{state} // '';
  $self->content($self->content->parse(delete $self->{buffer}))
    if $state eq 'content' || $state eq 'finished';

  # Check line size
  return $self->_limit('Maximum line size exceeded', 431)
    if $self->headers->is_limit_exceeded;

  # Check buffer size
  return $self->error('Maximum buffer size exceeded', 400)
    if $self->content->is_limit_exceeded;

  return $self->emit('progress')->content->is_finished ? $self->finish : $self;
}

sub start_line_size { length shift->build_start_line }

sub to_string {
  my $self = shift;
  return $self->build_start_line . $self->build_headers . $self->build_body;
}

sub upload { shift->_cache(uploads => @_) }

sub uploads {
  my $self = shift;

  my @uploads;
  for my $data (@{$self->_parse_formdata}) {

    # Just a form value
    next unless defined $data->[1];

    # Uploaded file
    my $upload = Mojo::Upload->new(
      name     => $data->[0],
      filename => $data->[1],
      asset    => $data->[2]->asset,
      headers  => $data->[2]->headers
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
  my ($self, $method, $name) = @_;

  # Cache objects by name
  unless ($self->{$method}) {
    $self->{$method} = {};
    push @{$self->{$method}{$_->name}}, $_ for @{$self->$method};
  }

  return unless my $objects = $self->{$method}{$name};
  return wantarray ? @$objects : $objects->[0];
}

sub _limit {
  my $self = shift;
  $self->{limit} = 1;
  $self->error(@_);
}

sub _parse_formdata {
  my $self = shift;

  # Check for multipart content
  my @formdata;
  my $content = $self->content;
  return \@formdata unless $content->is_multipart;
  my $charset = $content->charset || $self->default_charset;

  # Check all parts for form data
  my @parts = ($content);
  while (my $part = shift @parts) {

    # Nested multipart content
    if ($part->is_multipart) {
      unshift @parts, @{$part->parts};
      next;
    }

    # Extract information from Content-Disposition header
    next unless my $disposition = $part->headers->content_disposition;
    my ($name)     = $disposition =~ /[; ]name="?([^";]+)"?/;
    my ($filename) = $disposition =~ /[; ]filename="?([^"]*)"?/;
    if ($charset) {
      $name     = decode($charset, $name)     // $name     if $name;
      $filename = decode($charset, $filename) // $filename if $filename;
    }

    # Check for file upload
    my $value = $part;
    unless (defined $filename) {
      $value = $part->asset->slurp;
      $value = decode($charset, $value) // $value if $charset;
    }

    push @formdata, [$name, $filename, $value];
  }

  return \@formdata;
}

1;

=head1 NAME

Mojo::Message - HTTP message base class

=head1 SYNOPSIS

  package Mojo::Message::MyMessage;
  use Mojo::Base 'Mojo::Message';

  sub cookies              {...}
  sub extract_start_line   {...}
  sub get_start_line_chunk {...}

=head1 DESCRIPTION

L<Mojo::Message> is an abstract base class for HTTP messages as described in
RFC 2616 and RFC 2388.

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

Default charset used for form data parsing, defaults to C<UTF-8>.

=head2 max_line_size

  my $size = $msg->max_line_size;
  $msg     = $msg->max_line_size(1024);

Maximum start line size in bytes, defaults to the value of the
MOJO_MAX_LINE_SIZE environment variable or C<10240>.

=head2 max_message_size

  my $size = $msg->max_message_size;
  $msg     = $msg->max_message_size(1024);

Maximum message size in bytes, defaults to the value of the
MOJO_MAX_MESSAGE_SIZE environment variable or C<5242880>. Note that increasing
this value can also drastically increase memory usage, should you for example
attempt to parse an excessively large message body with the C<body_params>,
C<dom> or C<json> methods.

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

Slurp or replace C<content>.

=head2 body_params

  my $params = $msg->body_params;

C<POST> parameters extracted from C<x-application-urlencoded>,
C<application/x-www-form-urlencoded> or C<multipart/form-data> message body,
usually a L<Mojo::Parameters> object. Note that this method caches all data,
so it should not be called before the entire message body has been received.

  # Get POST parameter value
  say $msg->body_params->param('foo');

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

Render start line.

=head2 cookie

  my $cookie  = $msg->cookie('foo');
  my @cookies = $msg->cookie('foo');

Access message cookies, usually L<Mojo::Cookie::Request> or
L<Mojo::Cookie::Response> objects. Note that this method caches all data, so
it should not be called before all headers have been received.

  # Get cookie value
  say $msg->cookie('foo')->value;

=head2 cookies

  my $cookies = $msg->cookies;

Access message cookies. Meant to be overloaded in a subclass.

=head2 dom

  my $dom        = $msg->dom;
  my $collection = $msg->dom('a[href]');

Turns message body into a L<Mojo::DOM> object and takes an optional selector
to perform a C<find> on it right away, which returns a L<Mojo::Collection>
object. Note that this method caches all data, so it should not be called
before the entire message body has been received.

  # Perform "find" right away
  say $msg->dom('h1, h2, h3')->pluck('text');

  # Use everything else Mojo::DOM has to offer
  say $msg->dom->at('title')->text;
  say $msg->dom->html->body->children->pluck('type')->uniq;

=head2 error

  my $err          = $msg->error;
  my ($err, $code) = $msg->error;
  $msg             = $msg->error('Parser error');
  $msg             = $msg->error('Parser error', 500);

Error and code.

=head2 extract_start_line

  my $success = $msg->extract_start_line(\$str);

Extract start line from string. Meant to be overloaded in a subclass.

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

Get a chunk of start line data starting from a specific position. Meant to be
overloaded in a subclass.

=head2 header_size

  my $size = $msg->header_size;

Size of headers in bytes.

=head2 headers

  my $headers = $msg->headers;

Message headers, usually a L<Mojo::Headers> object.

=head2 is_finished

  my $success = $msg->is_finished;

Check if message parser/generator is finished.

=head2 is_limit_exceeded

  my $success = $msg->is_limit_exceeded;

Check if message has exceeded C<max_line_size> or C<max_message_size>.

=head2 json

  my $hash  = $msg->json;
  my $array = $msg->json;
  my $value = $msg->json('/foo/bar');

Decode JSON message body directly using L<Mojo::JSON> if possible, returns
C<undef> otherwise. An optional JSON Pointer can be used to extract a specific
value with L<Mojo::JSON::Pointer>. Note that this method caches all data, so
it should not be called before the entire message body has been received.

  # Extract JSON values
  say $msg->json->{foo}{bar}[23];
  say $msg->json('/foo/bar/23');

=head2 param

  my @names = $msg->param;
  my $foo   = $msg->param('foo');
  my @foo   = $msg->param('foo');

Access C<POST> parameters. Note that this method caches all data, so it should
not be called before the entire message body has been received.

=head2 parse

  $msg = $msg->parse('HTTP/1.1 200 OK...');

Parse message chunk.

=head2 start_line_size

  my $size = $msg->start_line_size;

Size of the start line in bytes.

=head2 to_string

  my $str = $msg->to_string;

Render whole message.

=head2 upload

  my $upload  = $msg->upload('foo');
  my @uploads = $msg->upload('foo');

Access C<multipart/form-data> file uploads, usually L<Mojo::Upload> objects.
Note that this method caches all data, so it should not be called before the
entire message body has been received.

  # Get content of uploaded file
  say $msg->upload('foo')->asset->slurp;

=head2 uploads

  my $uploads = $msg->uploads;

All C<multipart/form-data> file uploads, usually L<Mojo::Upload> objects.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
