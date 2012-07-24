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
has max_message_size => sub { $ENV{MOJO_MAX_MESSAGE_SIZE} || 5242880 };
has version          => '1.1';

# "I'll keep it short and sweet. Family. Religion. Friendship.
#  These are the three demons you must slay if you wish to succeed in
#  business."
sub at_least_version { shift->version >= shift }

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

# "My new movie is me, standing in front of a brick wall for 90 minutes.
#  It cost 80 million dollars to make.
#  How do you sleep at night?
#  On top of a pile of money, with many beautiful women."
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

# DEPRECATED in Rainbow!
sub dom_class {
  warn "Mojo::Message->dom_class is DEPRECATED!\n";
  return @_ > 1 ? shift : 'Mojo::DOM';
}

sub error {
  my $self = shift;

  # Get
  unless (@_) {
    return unless my $err = $self->{error};
    return wantarray ? @$err : $err->[0];
  }

  # Set
  $self->{error} = [@_];
  $self->{state} = 'finished';

  return $self;
}

sub fix_headers {
  my $self = shift;

  # Content-Length header or connection close is required in HTTP 1.0
  # unless the chunked transfer encoding is used
  return $self
    if $self->{fix}++ || !$self->at_least_version('1.0') || $self->is_chunked;
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
  $self->emit(progress => 'body', $offset);

  # Chunk
  my $chunk = $self->content->get_body_chunk($offset);
  return $chunk if !defined $chunk || length $chunk;

  # Finish
  $self->{state} = 'finished';
  $self->emit('finish');

  return $chunk;
}

sub get_header_chunk {
  my ($self, $offset) = @_;

  # Progress
  $self->emit(progress => 'headers', $offset);

  # HTTP 0.9 has no headers
  return '' if $self->version eq '0.9';

  return $self->fix_headers->content->get_header_chunk($offset);
}

sub get_start_line_chunk {
  my ($self, $offset) = @_;
  $self->emit(progress => 'start_line', $offset);
  return substr $self->{start_line_buffer} //= $self->_build_start_line,
    $offset, $ENV{MOJO_CHUNK_SIZE} || 131072;
}

sub has_leftovers { shift->content->has_leftovers }
sub header_size   { shift->fix_headers->content->header_size }
sub headers       { shift->content->headers(@_) }
sub is_chunked    { shift->content->is_chunked }
sub is_dynamic    { shift->content->is_dynamic }

sub is_finished { (shift->{state} || '') eq 'finished' }

sub is_limit_exceeded { ((shift->error)[1] || 0) ~~ [413, 431] }

sub is_multipart { shift->content->is_multipart }

sub json {
  my ($self, $pointer) = @_;
  return if $self->is_multipart;
  my $data = $self->{json} ||= Mojo::JSON->new->decode($self->body);
  return $pointer ? Mojo::JSON::Pointer->new->get($data, $pointer) : $data;
}

# DEPRECATED in Rainbow!
sub json_class {
  warn "Mojo::Message->json_class is DEPRECATED!\n";
  return @_ > 1 ? shift : 'Mojo::JSON';
}

sub leftovers { shift->content->leftovers }

sub max_line_size { shift->headers->max_line_size(@_) }

sub param { shift->body_params->param(@_) }

sub parse            { shift->_parse(0, @_) }
sub parse_until_body { shift->_parse(1, @_) }

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

sub write       { shift->content->write(@_) }
sub write_chunk { shift->content->write_chunk(@_) }

sub _build {
  my ($self, $method) = @_;

  # Build part from chunks
  my $buffer = '';
  my $offset = 0;
  while (1) {
    my $chunk = $self->$method($offset);

    # No chunk yet, try again
    next unless defined $chunk;

    # End of part
    last unless length $chunk;

    # Part
    $offset += length $chunk;
    $buffer .= $chunk;
  }

  return $buffer;
}

sub _build_start_line {''}

sub _nest {
  my $array = shift;
  my $hash  = {};
  for my $object (@$array) {
    my $name = $object->name;

    # Multiple objects with same name
    if (exists $hash->{$name}) {
      $hash->{$name} = [$hash->{$name}] unless ref $hash->{$name} eq 'ARRAY';
      push @{$hash->{$name}}, $object;
    }

    # Object
    else { $hash->{$name} = $object }
  }

  return $hash;
}

sub _parse {
  my ($self, $until_body, $chunk) = @_;

  # Add chunk
  $chunk //= '';
  $self->{raw_size} += length $chunk;
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

    # Parse
    $self->_parse_start_line;
  }

  # Content
  if (($self->{state} || '') ~~ [qw(body content finished)]) {

    # Until body
    my $content = $self->content;
    my $buffer  = delete $self->{buffer};
    if ($until_body) { $self->content($content->parse_until_body($buffer)) }

    # CGI
    elsif ($self->{state} eq 'body') {
      $self->content($content->parse_body($buffer));
    }

    # HTTP 0.9
    elsif ($self->version eq '0.9') {
      $self->content($content->parse_body_once($buffer));
    }

    # Parse
    else { $self->content($content->parse($buffer)) }
  }

  # Check line size
  return $self->error('Maximum line size exceeded', 431)
    if $self->headers->is_limit_exceeded;

  # Finished
  $self->{state} = 'finished' if $self->content->is_finished;

  # Progress
  $self->emit('progress');

  # Finished
  $self->emit('finish') if $self->is_finished;

  return $self;
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
    my ($name)     = $disposition =~ /\ name="?([^";]+)"?/;
    my ($filename) = $disposition =~ /\ filename="?([^"]*)"?/;
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
      $value = decode($charset, $value) // $value
        if $charset && !$part->headers->content_transfer_encoding;
    }

    push @formdata, [$name, $filename, $value];
  }

  return \@formdata;
}

sub _parse_start_line { }

1;

=head1 NAME

Mojo::Message - HTTP 1.1 message base class

=head1 SYNOPSIS

  use Mojo::Base 'Mojo::Message';

=head1 DESCRIPTION

L<Mojo::Message> is an abstract base class for HTTP 1.1 messages as described
in RFC 2616 and RFC 2388.

=head1 EVENTS

L<Mojo::Message> can emit the following events.

=head2 C<finish>

  $message->on(finish => sub {
    my $message = shift;
    ...
  });

Emitted after message building or parsing is finished.

  my $before = time;
  $message->on(finish => sub {
    my $message = shift;
    $message->headers->header('X-Parser-Time' => time - $before);
  });

=head2 C<progress>

  $message->on(progress => sub {
    my $message = shift;
    ...
  });

Emitted when message building or parsing makes progress.

  # Building
  $message->on(progress => sub {
    my ($message, $state, $offset) = @_;
    say qq{Building "$state" at offset $offset};
  });

  # Parsing
  $message->on(progress => sub {
    my $message = shift;
    return unless my $len = $message->headers->content_length;
    my $size = $message->content->progress;
    say 'Progress: ', $size == $len ? 100 : int($size / ($len / 100)), '%';
  });

=head1 ATTRIBUTES

L<Mojo::Message> implements the following attributes.

=head2 C<content>

  my $message = $message->content;
  $message    = $message->content(Mojo::Content::Single->new);

Content container, defaults to a L<Mojo::Content::Single> object.

=head2 C<default_charset>

  my $charset = $message->default_charset;
  $message    = $message->default_charset('UTF-8');

Default charset used for form data parsing, defaults to C<UTF-8>.

=head2 C<max_message_size>

  my $size = $message->max_message_size;
  $message = $message->max_message_size(1024);

Maximum message size in bytes, defaults to the value of the
C<MOJO_MAX_MESSAGE_SIZE> environment variable or C<5242880>. Note that
increasing this value can also drastically increase memory usage, should you
for example attempt to parse an excessively large message body with the
C<body_params>, C<dom> or C<json> methods.

=head2 C<version>

  my $version = $message->version;
  $message    = $message->version('1.1');

HTTP version of message.

=head1 METHODS

L<Mojo::Message> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 C<at_least_version>

  my $success = $message->at_least_version('1.1');

Check if message is at least a specific version.

=head2 C<body>

  my $string = $message->body;
  $message   = $message->body('Hello!');
  my $cb     = $message->body(sub {...});

Access C<content> data or replace all subscribers of the C<read> event.

  $message->body(sub {
    my ($message, $chunk) = @_;
    say "Streaming: $chunk";
  });

=head2 C<body_params>

  my $p = $message->body_params;

C<POST> parameters extracted from C<x-application-urlencoded>,
C<application/x-www-form-urlencoded> or C<multipart/form-data> message body,
usually a L<Mojo::Parameters> object. Note that this method caches all data,
so it should not be called before the entire message body has been received.

  say $message->body_params->param('foo');

=head2 C<body_size>

  my $size = $message->body_size;

Alias for L<Mojo::Content/"body_size">.

=head2 C<build_body>

  my $string = $message->build_body;

Render whole body.

=head2 C<build_headers>

  my $string = $message->build_headers;

Render all headers.

=head2 C<build_start_line>

  my $string = $message->build_start_line;

Render start line.

=head2 C<cookie>

  my $cookie  = $message->cookie('foo');
  my @cookies = $message->cookie('foo');

Access message cookies, usually L<Mojo::Cookie::Request> or
L<Mojo::Cookie::Response> objects. Note that this method caches all data, so
it should not be called before all headers have been received.

  say $message->cookie('foo')->value;

=head2 C<cookies>

  my $cookies = $message->cookies;

Access message cookies, meant to be overloaded in a subclass.

=head2 C<dom>

  my $dom        = $message->dom;
  my $collection = $message->dom('a[href]');

Turns message body into a L<Mojo::DOM> object and takes an optional selector
to perform a C<find> on it right away, which returns a L<Mojo::Collection>
object. Note that this method caches all data, so it should not be called
before the entire message body has been received.

  # Perform "find" right away
  say $message->dom('h1, h2, h3')->pluck('text');

  # Use everything else Mojo::DOM has to offer
  say $message->dom->at('title')->text;
  say $message->dom->html->body->children->pluck('type')->uniq;

=head2 C<error>

  my $message          = $message->error;
  my ($message, $code) = $message->error;
  $message             = $message->error('Parser error');
  $message             = $message->error('Parser error', 500);

Parser errors and codes.

=head2 C<fix_headers>

  $message = $message->fix_headers;

Make sure message has all required headers for the current HTTP version.

=head2 C<get_body_chunk>

  my $string = $message->get_body_chunk($offset);

Get a chunk of body data starting from a specific position.

=head2 C<get_header_chunk>

  my $string = $message->get_header_chunk($offset);

Get a chunk of header data, starting from a specific position.

=head2 C<get_start_line_chunk>

  my $string = $message->get_start_line_chunk($offset);

Get a chunk of start line data starting from a specific position.

=head2 C<has_leftovers>

  my $success = $message->has_leftovers;

Alias for L<Mojo::Content/"has_leftovers">.

=head2 C<header_size>

  my $size = $message->header_size;

Size of headers in bytes.

=head2 C<headers>

  my $headers = $message->headers;

Alias for L<Mojo::Content/"headers">.

  say $message->headers->content_type;

=head2 C<is_chunked>

  my $success = $message->is_chunked;

Alias for L<Mojo::Content/"is_chunked">.

=head2 C<is_dynamic>

  my $success = $message->is_dynamic;

Alias for L<Mojo::Content/"is_dynamic">.

=head2 C<is_finished>

  my $success = $message->is_finished;

Check if parser is finished.

=head2 C<is_limit_exceeded>

  my $success = $message->is_limit_exceeded;

Check if message has exceeded C<max_line_size> or C<max_message_size>.

=head2 C<is_multipart>

  my $success = $message->is_multipart;

Alias for L<Mojo::Content/"is_multipart">.

=head2 C<json>

  my $hash  = $message->json;
  my $array = $message->json;
  my $value = $message->json('/foo/bar');

Decode JSON message body directly using L<Mojo::JSON> if possible, returns
C<undef> otherwise. An optional JSON Pointer can be used to extract a specific
value with L<Mojo::JSON::Pointer>. Note that this method caches all data, so
it should not be called before the entire message body has been received.

  say $message->json->{foo}{bar}[23];
  say $message->json('/foo/bar/23');

=head2 C<leftovers>

  my $bytes = $message->leftovers;

Alias for L<Mojo::Content/"leftovers">.

=head2 C<max_line_size>

  $message->max_line_size(1024);

Alias for L<Mojo::Headers/"max_line_size">.

=head2 C<param>

  my @names = $message->param;
  my $foo   = $message->param('foo');
  my @foo   = $message->param('foo');

Access C<POST> parameters. Note that this method caches all data, so it should
not be called before the entire message body has been received.

=head2 C<parse>

  $message = $message->parse('HTTP/1.1 200 OK...');

Parse message chunk.

=head2 C<parse_until_body>

  $message = $message->parse_until_body('HTTP/1.1 200 OK...');

Parse message chunk until the body is reached.

=head2 C<start_line_size>

  my $size = $message->start_line_size;

Size of the start line in bytes.

=head2 C<to_string>

  my $string = $message->to_string;

Render whole message.

=head2 C<upload>

  my $upload  = $message->upload('foo');
  my @uploads = $message->upload('foo');

Access C<multipart/form-data> file uploads, usually L<Mojo::Upload> objects.
Note that this method caches all data, so it should not be called before the
entire message body has been received.

  say $message->upload('foo')->asset->slurp;

=head2 C<uploads>

  my $uploads = $message->uploads;

All C<multipart/form-data> file uploads, usually L<Mojo::Upload> objects.

  say $message->uploads->[2]->filename;

=head2 C<write>

  $message->write('Hello!');
  $message->write('Hello!', sub {...});

Alias for L<Mojo::Content/"write">.

=head2 C<write_chunk>

  $message->write_chunk('Hello!');
  $message->write_chunk('Hello!', sub {...});

Alias for L<Mojo::Content/"write_headers">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
