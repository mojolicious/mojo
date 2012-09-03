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
use Mojo::Util qw(decode url_unescape);
use Scalar::Util 'weaken';

has content => sub { Mojo::Content::Single->new };
has default_charset  => 'UTF-8';
has max_line_size    => sub { $ENV{MOJO_MAX_LINE_SIZE} || 10240 };
has max_message_size => sub { $ENV{MOJO_MAX_MESSAGE_SIZE} || 5242880 };
has version          => '1.1';

sub body {
  my $self = shift;

  # Downgrade multipart content
  $self->content(Mojo::Content::Single->new) if $self->content->is_multipart;
  my $content = $self->content;

  # Get
  return $content->asset->slurp unless defined(my $new = shift);

  # Callback
  if (ref $new eq 'CODE') {
    weaken $self;
    return $content->unsubscribe('read')->on(read => sub { $self->$new(pop) });
  }

  # Set text content
  else { $content->asset(Mojo::Asset::Memory->new->add_chunk($new)) }

  return $self;
}

sub body_params {
  my $self = shift;

  # Cached
  return $self->{body_params} if $self->{body_params};

  # Charset
  my $p = $self->{body_params} = Mojo::Parameters->new;
  $p->charset($self->content->charset || $self->default_charset);

  # "x-application-urlencoded" and "application/x-www-form-urlencoded"
  my $type = $self->headers->content_type || '';
  if ($type =~ m!(?:x-application|application/x-www-form)-urlencoded!i) {
    $p->parse($self->content->asset->slurp);
  }

  # "multipart/formdata"
  elsif ($type =~ m!multipart/form-data!i) {
    my $formdata = $self->_parse_formdata;

    # Formdata
    for my $data (@$formdata) {
      my ($name, $filename, $value) = @$data;

      # File
      next if defined $filename;

      # Form value
      $p->append($name, $value);
    }
  }

  return $p;
}

sub body_size { shift->content->body_size }

sub build_body       { shift->_build('get_body_chunk') }
sub build_headers    { shift->_build('get_header_chunk') }
sub build_start_line { shift->_build('get_start_line_chunk') }

sub cookie {
  my ($self, $name) = @_;
  $self->{cookies} ||= _nest($self->cookies);
  return unless my $cookies = $self->{cookies}{$name};
  my @cookies = ref $cookies eq 'ARRAY' ? @$cookies : ($cookies);
  return wantarray ? @cookies : $cookies[0];
}

sub cookies { croak 'Method "cookies" not implemented by subclass' }

sub dom {
  my $self = shift;

  return if $self->is_multipart;
  my $dom = $self->{dom}
    ||= Mojo::DOM->new->charset($self->content->charset // undef)
    ->parse($self->body);

  return @_ ? $dom->find(@_) : $dom;
}

sub error {
  my ($self, @args) = @_;

  # Set
  return $self->tap(sub { $_->{error} = [@args] })->finish if @args;

  # Get
  return unless my $err = $self->{error};
  return wantarray ? @$err : $err->[0];
}

sub extract_start_line {
  croak 'Method "extract_start_line" not implemented by subclass';
}

sub finish {
  my $self = shift->tap(sub { $_->{state} = 'finished' });
  return $self->{finished}++ ? $self : $self->emit('finish');
}

sub fix_headers {
  my $self = shift;

  # Content-Length header or connection close is required unless the chunked
  # transfer encoding is used
  return $self if $self->{fix}++ || $self->is_chunked;
  my $headers = $self->headers;
  $self->is_dynamic
    ? $headers->connection('close')
    : $headers->content_length($self->body_size)
    unless $headers->content_length;

  return $self;
}

sub get_body_chunk {
  my ($self, $offset) = @_;

  # Progress
  $self->emit('progress', 'body', $offset);

  # Chunk
  my $chunk = $self->content->get_body_chunk($offset);
  return $chunk if !defined $chunk || length $chunk;

  # Finish
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

sub has_leftovers { shift->content->has_leftovers }

sub header_size { shift->fix_headers->content->header_size }

sub headers    { shift->content->headers }
sub is_chunked { shift->content->is_chunked }
sub is_dynamic { shift->content->is_dynamic }

sub is_finished { (shift->{state} // '') eq 'finished' }

sub is_limit_exceeded {
  return unless my $code = (shift->error)[1];
  return !!grep { $_ eq $code } 413, 431;
}

sub is_multipart { shift->content->is_multipart }

sub json {
  my ($self, $pointer) = @_;
  return if $self->is_multipart;
  my $data = $self->{json} ||= Mojo::JSON->new->decode($self->body);
  return $pointer ? Mojo::JSON::Pointer->new->get($data, $pointer) : $data;
}

sub leftovers { shift->content->leftovers }

sub param { shift->body_params->param(@_) }

sub parse {
  my ($self, $chunk) = @_;

  # Add chunk
  $self->{raw_size} += length($chunk //= '');
  $self->{buffer} .= $chunk;

  # Check message size
  return $self->error('Maximum message size exceeded', 413)
    if $self->{raw_size} > $self->max_message_size;

  # Start line
  unless ($self->{state}) {

    # Check line size
    my $len = index $self->{buffer}, "\x0a";
    $len = length $self->{buffer} if $len < 0;
    return $self->error('Maximum line size exceeded', 431)
      if $len > $self->max_line_size;

    # Extract
    $self->{state} = 'content' if $self->extract_start_line(\$self->{buffer});
  }

  # Content
  $self->content($self->content->parse(delete $self->{buffer}))
    if grep { $_ eq ($self->{state} // '') } qw(content finished);

  # Check line size
  return $self->error('Maximum line size exceeded', 431)
    if $self->headers->is_limit_exceeded;

  # Progress
  $self->emit('progress');

  return $self->content->is_finished ? $self->finish : $self;
}

sub start_line_size { length shift->build_start_line }

sub to_string {
  my $self = shift;
  return $self->build_start_line . $self->build_headers . $self->build_body;
}

sub upload {
  my ($self, $name) = @_;
  $self->{uploads} ||= _nest($self->uploads);
  return unless my $uploads = $self->{uploads}{$name};
  my @uploads = ref $uploads eq 'ARRAY' ? @$uploads : ($uploads);
  return wantarray ? @uploads : $uploads[0];
}

sub uploads {
  my $self = shift;

  # Only multipart messages have uploads
  my @uploads;
  return \@uploads unless $self->is_multipart;

  # Extract formdata
  my $formdata = $self->_parse_formdata;
  for my $data (@$formdata) {
    my ($name, $filename, $part) = @$data;

    # Just a form value
    next unless defined $filename;

    # Uploaded file
    my $upload = Mojo::Upload->new(
      name     => $name,
      asset    => $part->asset,
      filename => $filename,
      headers  => $part->headers
    );
    push @uploads, $upload;
  }

  return \@uploads;
}

sub write       { shift->_write(write       => @_) }
sub write_chunk { shift->_write(write_chunk => @_) }

sub _build {
  my ($self, $method) = @_;

  # Build part from chunks
  my $buffer = '';
  my $offset = 0;
  while (1) {

    # No chunk yet, try again
    next unless defined(my $chunk = $self->$method($offset));

    # End of part
    last unless my $len = length $chunk;

    # Part
    $offset += $len;
    $buffer .= $chunk;
  }

  return $buffer;
}

sub _nest {
  my $array = shift;

  # Turn array of objects into hash
  my $hash = {};
  for my $object (@$array) {
    my $name = $object->name;

    # Multiple objects with same name
    if (exists $hash->{$name}) {
      $hash->{$name} = [$hash->{$name}] unless ref $hash->{$name} eq 'ARRAY';
      push @{$hash->{$name}}, $object;
    }

    # Single object
    else { $hash->{$name} = $object }
  }

  return $hash;
}

sub _parse_formdata {
  my $self = shift;

  # Check content
  my @formdata;
  my $content = $self->content;
  return \@formdata unless $content->is_multipart;
  my $default = $content->charset || $self->default_charset;

  # Walk the tree
  my @parts;
  push @parts, $content;
  while (my $part = shift @parts) {

    # Multipart
    if ($part->is_multipart) {
      unshift @parts, @{$part->parts};
      next;
    }

    # Charset
    my $charset = $part->charset || $default;

    # Content-Disposition header
    my $disposition = $part->headers->content_disposition;
    next unless $disposition;
    my ($name)     = $disposition =~ /[; ]name="?([^";]+)"?/;
    my ($filename) = $disposition =~ /[; ]filename="?([^"]*)"?/;
    my $value      = $part;

    # Unescape
    $name     = url_unescape $name     if $name;
    $filename = url_unescape $filename if $filename;
    if ($charset) {
      $name     = decode($charset, $name)     // $name     if $name;
      $filename = decode($charset, $filename) // $filename if $filename;
    }

    # Form value
    unless (defined $filename) {
      $value = $part->asset->slurp;
      $value = decode($charset, $value) // $value if $charset;
    }

    push @formdata, [$name, $filename, $value];
  }

  return \@formdata;
}

sub _write {
  my ($self, $method, $chunk, $cb) = @_;
  weaken $self;
  $self->content->$method($chunk => sub { shift and $self->$cb(@_) if $cb });
  return $self;
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

L<Mojo::Message> can emit the following events.

=head2 C<finish>

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

=head2 C<progress>

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

=head2 C<content>

  my $msg = $msg->content;
  $msg    = $msg->content(Mojo::Content::Single->new);

Message content, defaults to a L<Mojo::Content::Single> object.

=head2 C<default_charset>

  my $charset = $msg->default_charset;
  $msg        = $msg->default_charset('UTF-8');

Default charset used for form data parsing, defaults to C<UTF-8>.

=head2 C<max_line_size>

  my $size = $msg->max_line_size;
  $msg     = $msg->max_line_size(1024);

Maximum start line size in bytes, defaults to the value of the
C<MOJO_MAX_LINE_SIZE> environment variable or C<10240>.

=head2 C<max_message_size>

  my $size = $msg->max_message_size;
  $msg     = $msg->max_message_size(1024);

Maximum message size in bytes, defaults to the value of the
C<MOJO_MAX_MESSAGE_SIZE> environment variable or C<5242880>. Note that
increasing this value can also drastically increase memory usage, should you
for example attempt to parse an excessively large message body with the
C<body_params>, C<dom> or C<json> methods.

=head2 C<version>

  my $version = $msg->version;
  $msg        = $msg->version('1.1');

HTTP version of message, defaults to C<1.1>.

=head1 METHODS

L<Mojo::Message> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 C<body>

  my $string = $msg->body;
  $msg       = $msg->body('Hello!');
  my $cb     = $msg->body(sub {...});

Access C<content> data or replace all subscribers of the C<read> event.

  $msg->body(sub {
    my ($msg, $chunk) = @_;
    say "Streaming: $chunk";
  });

=head2 C<body_params>

  my $p = $msg->body_params;

C<POST> parameters extracted from C<x-application-urlencoded>,
C<application/x-www-form-urlencoded> or C<multipart/form-data> message body,
usually a L<Mojo::Parameters> object. Note that this method caches all data,
so it should not be called before the entire message body has been received.

  # Get POST parameter value
  say $msg->body_params->param('foo');

=head2 C<body_size>

  my $size = $msg->body_size;

Content size in bytes.

=head2 C<build_body>

  my $string = $msg->build_body;

Render whole body.

=head2 C<build_headers>

  my $string = $msg->build_headers;

Render all headers.

=head2 C<build_start_line>

  my $string = $msg->build_start_line;

Render start line.

=head2 C<cookie>

  my $cookie  = $msg->cookie('foo');
  my @cookies = $msg->cookie('foo');

Access message cookies, usually L<Mojo::Cookie::Request> or
L<Mojo::Cookie::Response> objects. Note that this method caches all data, so
it should not be called before all headers have been received.

  # Get cookie value
  say $msg->cookie('foo')->value;

=head2 C<cookies>

  my $cookies = $msg->cookies;

Access message cookies. Meant to be overloaded in a subclass.

=head2 C<dom>

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

=head2 C<error>

  my $err          = $msg->error;
  my ($err, $code) = $msg->error;
  $msg             = $msg->error('Parser error');
  $msg             = $msg->error('Parser error', 500);

Parser errors and codes.

=head2 C<extract_start_line>

  my $success = $msg->extract_start_line(\$string);

Extract start line from string. Meant to be overloaded in a subclass.

=head2 C<finish>

  $msg = $msg->finish;

Finish message parser/generator.

=head2 C<fix_headers>

  $msg = $msg->fix_headers;

Make sure message has all required headers for the current HTTP version.

=head2 C<get_body_chunk>

  my $string = $msg->get_body_chunk($offset);

Get a chunk of body data starting from a specific position.

=head2 C<get_header_chunk>

  my $string = $msg->get_header_chunk($offset);

Get a chunk of header data, starting from a specific position.

=head2 C<get_start_line_chunk>

  my $string = $msg->get_start_line_chunk($offset);

Get a chunk of start line data starting from a specific position. Meant to be
overloaded in a subclass.

=head2 C<has_leftovers>

  my $success = $msg->has_leftovers;

Check if there are leftovers.

=head2 C<header_size>

  my $size = $msg->header_size;

Size of headers in bytes.

=head2 C<headers>

  my $headers = $msg->headers;

Message headers, usually a L<Mojo::Headers> object.

=head2 C<is_chunked>

  my $success = $msg->is_chunked;

Check if content is chunked.

=head2 C<is_dynamic>

  my $success = $msg->is_dynamic;

Check if content will be dynamically generated, which prevents C<clone> from
working.

=head2 C<is_finished>

  my $success = $msg->is_finished;

Check if message parser/generator is finished.

=head2 C<is_limit_exceeded>

  my $success = $msg->is_limit_exceeded;

Check if message has exceeded C<max_line_size> or C<max_message_size>.

=head2 C<is_multipart>

  my $success = $msg->is_multipart;

Check if content is a L<Mojo::Content::MultiPart> object.

=head2 C<json>

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

=head2 C<leftovers>

  my $bytes = $msg->leftovers;

Get leftover data from content parser.

=head2 C<param>

  my @names = $msg->param;
  my $foo   = $msg->param('foo');
  my @foo   = $msg->param('foo');

Access C<POST> parameters. Note that this method caches all data, so it should
not be called before the entire message body has been received.

=head2 C<parse>

  $msg = $msg->parse('HTTP/1.1 200 OK...');

Parse message chunk.

=head2 C<start_line_size>

  my $size = $msg->start_line_size;

Size of the start line in bytes.

=head2 C<to_string>

  my $string = $msg->to_string;

Render whole message.

=head2 C<upload>

  my $upload  = $msg->upload('foo');
  my @uploads = $msg->upload('foo');

Access C<multipart/form-data> file uploads, usually L<Mojo::Upload> objects.
Note that this method caches all data, so it should not be called before the
entire message body has been received.

  # Get content of uploaded file
  say $msg->upload('foo')->asset->slurp;

=head2 C<uploads>

  my $uploads = $msg->uploads;

All C<multipart/form-data> file uploads, usually L<Mojo::Upload> objects.

=head2 C<write>

  $msg = $msg->write('Hello!');
  $msg = $msg->write('Hello!' => sub {...});

Write dynamic content non-blocking, the optional drain callback will be
invoked once all data has been written.

=head2 C<write_chunk>

  $msg = $msg->write_chunk('Hello!');
  $msg = $msg->write_chunk('Hello!' => sub {...});

Write dynamic content non-blocking with C<chunked> transfer encoding, the
optional drain callback will be invoked once all data has been written.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
