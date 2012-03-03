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
use Mojo::Util qw/decode url_unescape/;
use Scalar::Util 'weaken';

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 131072;

has content => sub { Mojo::Content::Single->new };
has default_charset  => 'UTF-8';
has dom_class        => 'Mojo::DOM';
has json_class       => 'Mojo::JSON';
has max_message_size => sub { $ENV{MOJO_MAX_MESSAGE_SIZE} || 5242880 };
has version          => '1.1';

# "I'll keep it short and sweet. Family. Religion. Friendship.
#  These are the three demons you must slay if you wish to succeed in
#  business."
sub at_least_version {
  my ($self, $version) = @_;

  # Major and minor
  my ($search_major,  $search_minor)  = split /\./, $version;
  my ($current_major, $current_minor) = split /\./, $self->version;

  # Version is equal or newer
  return 1 if $search_major < $current_major;
  return 1
    if $search_major == $current_major && $search_minor <= $current_minor;

  # Version is older
  return;
}

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
    return $content->unsubscribe('read')
      ->on(read => sub { $self->$new(pop) });
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
  my $params = Mojo::Parameters->new;
  $params->charset($self->content->charset || $self->default_charset);

  # "x-application-urlencoded" and "application/x-www-form-urlencoded"
  my $type = $self->headers->content_type || '';
  if ($type =~ m#(?:x-application|application/x-www-form)-urlencoded#i) {
    $params->parse($self->content->asset->slurp);
  }

  # "multipart/formdata"
  elsif ($type =~ m#multipart/form-data#i) {
    my $formdata = $self->_parse_formdata;

    # Formdata
    for my $data (@$formdata) {
      my $name     = $data->[0];
      my $filename = $data->[1];
      my $value    = $data->[2];

      # File
      next if defined $filename;

      # Form value
      $params->append($name, $value);
    }
  }

  return $self->{body_params} = $params;
}

sub body_size { shift->content->body_size }

# "My new movie is me, standing in front of a brick wall for 90 minutes.
#  It cost 80 million dollars to make.
#  How do you sleep at night?
#  On top of a pile of money, with many beautiful women."
sub build_body {
  my $self = shift;
  my $body = $self->content->build_body(@_);
  $self->{state} = 'finished';
  $self->emit('finish');
  return $body;
}

sub build_headers {
  my $self = shift;

  # HTTP 0.9 has no headers
  return '' if $self->version eq '0.9';

  $self->fix_headers;
  return $self->content->build_headers;
}

sub build_start_line {
  my $self = shift;

  my $startline = '';
  my $offset    = 0;
  while (1) {
    my $chunk = $self->get_start_line_chunk($offset);

    # No start line yet, try again
    next unless defined $chunk;

    # End of start line
    last unless length $chunk;

    # Start line
    $offset += length $chunk;
    $startline .= $chunk;
  }

  return $startline;
}

sub cookie {
  my ($self, $name) = @_;
  return unless $name;

  # Map
  unless ($self->{cookies}) {
    my $cookies = {};
    for my $cookie (@{$self->cookies}) {
      my $cookie_name = $cookie->name;

      # Multiple cookies with same name
      if (exists $cookies->{$cookie_name}) {
        $cookies->{$cookie_name} = [$cookies->{$cookie_name}]
          unless ref $cookies->{$cookie_name} eq 'ARRAY';
        push @{$cookies->{$cookie_name}}, $cookie;
      }

      # Cookie
      else { $cookies->{$cookie_name} = $cookie }
    }

    $self->{cookies} = $cookies;
  }

  # Multiple
  my $cookies = $self->{cookies}->{$name};
  my @cookies;
  @cookies = ref $cookies eq 'ARRAY' ? @$cookies : ($cookies) if $cookies;

  return wantarray ? @cookies : $cookies[0];
}

sub dom {
  my $self = shift;
  return if $self->is_multipart;
  my $dom = $self->dom_class->new;
  $dom->charset($self->content->charset);
  $dom->parse($self->body);
  return @_ ? $dom->find(@_) : $dom;
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
  if ($self->at_least_version('1.0') && !$self->is_chunked) {
    my $headers = $self->headers;
    unless ($headers->content_length) {
      $self->is_dynamic
        ? $headers->connection('close')
        : $headers->content_length($self->body_size);
    }
  }

  return $self;
}

sub get_body_chunk {
  my $self = shift;

  # Progress
  $self->emit(progress => 'body', @_);

  # Chunk
  my $chunk = $self->content->get_body_chunk(@_);
  return $chunk if !defined $chunk || length $chunk;

  # Finish
  $self->{state} = 'finished';
  $self->emit('finish');

  return $chunk;
}

sub get_header_chunk {
  my $self = shift;

  # Progress
  $self->emit(progress => 'headers', @_);

  # HTTP 0.9 has no headers
  return '' if $self->version eq '0.9';

  return $self->content->get_header_chunk(@_);
}

sub get_start_line_chunk {
  my ($self, $offset) = @_;
  $self->emit(progress => 'start_line', @_);
  return substr $self->{start_line_buffer} //= $self->_build_start_line,
    $offset, CHUNK_SIZE;
}

sub has_leftovers { shift->content->has_leftovers }

sub header_size { shift->fix_headers->content->header_size }

sub headers { shift->content->headers(@_) }

sub is_chunked { shift->content->is_chunked }

sub is_dynamic { shift->content->is_dynamic }

sub is_finished { (shift->{state} || '') eq 'finished' }

sub is_limit_exceeded {
  return unless my $code = (shift->error)[1];
  return $code ~~ [413, 431];
}

sub is_multipart { shift->content->is_multipart }

sub json {
  my ($self, $pointer) = @_;
  return if $self->is_multipart;
  my $data = $self->json_class->new->decode($self->body);
  return $pointer ? Mojo::JSON::Pointer->get($data, $pointer) : $data;
}

sub leftovers { shift->content->leftovers }

sub max_line_size { shift->headers->max_line_size(@_) }

sub param {
  my $self = shift;
  return ($self->{body_params} ||= $self->body_params)->param(@_);
}

sub parse            { shift->_parse(0, @_) }
sub parse_until_body { shift->_parse(1, @_) }

sub start_line_size { length shift->build_start_line }

sub to_string {
  my $self = shift;
  $self->build_start_line . $self->build_headers . $self->build_body;
}

sub upload {
  my ($self, $name) = @_;
  return unless $name;

  # Map
  unless ($self->{uploads}) {
    my $uploads = {};
    for my $upload (@{$self->uploads}) {
      my $uname = $upload->name;

      # Multiple uploads with same name
      if (exists $uploads->{$uname}) {
        $uploads->{$uname} = [$uploads->{$uname}]
          unless ref $uploads->{$uname} eq 'ARRAY';
        push @{$uploads->{$uname}}, $upload;
      }

      # Upload
      else { $uploads->{$uname} = $upload }
    }

    $self->{uploads} = $uploads;
  }

  # Multiple
  my $uploads = $self->{uploads}->{$name};
  my @uploads;
  @uploads = ref $uploads eq 'ARRAY' ? @$uploads : ($uploads) if $uploads;

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
    my $name     = $data->[0];
    my $filename = $data->[1];
    my $part     = $data->[2];

    # Just a form value
    next unless defined $filename;

    # Uploaded file
    my $upload = Mojo::Upload->new;
    $upload->name($name);
    $upload->asset($part->asset);
    $upload->filename($filename);
    $upload->headers($part->headers);
    push @uploads, $upload;
  }

  return \@uploads;
}

sub write       { shift->content->write(@_) }
sub write_chunk { shift->content->write_chunk(@_) }

sub _build_start_line {
  croak 'Method "_build_start_line" not implemented by subclass';
}

sub _parse {
  my ($self, $until_body, $chunk) = @_;

  # Add chunk
  $self->{buffer}   //= '';
  $self->{raw_size} //= 0;
  if (defined $chunk) {
    $self->{raw_size} += length $chunk;
    $self->{buffer} .= $chunk;
  }

  # Check message size
  return $self->error('Maximum message size exceeded.', 413)
    if $self->{raw_size} > $self->max_message_size;

  # Start line
  unless ($self->{state}) {

    # Check line size
    my $len = index $self->{buffer}, "\x0a";
    $len = length $self->{buffer} if $len < 0;
    return $self->error('Maximum line size exceeded.', 431)
      if $len > $self->max_line_size;

    # Parse
    $self->_parse_start_line;
  }

  # Content
  if (($self->{state} || '') ~~ [qw/body content finished/]) {

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
  return $self->error('Maximum line size exceeded.', 431)
    if $self->headers->is_limit_exceeded;

  # Finished
  $self->{state} = 'finished' if $self->content->is_finished;

  # Progress
  $self->emit('progress');

  # Finished
  $self->emit('finish') if $self->is_finished;

  return $self;
}

sub _parse_start_line {
  croak 'Method "_parse_start_line" not implemented by subclass';
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

1;
__END__

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

=head2 C<dom_class>

  my $class = $message->dom_class;
  $message  = $message->dom_class('Mojo::DOM');

Class to be used for DOM manipulation with the C<dom> method, defaults to
L<Mojo::DOM>.

=head2 C<json_class>

  my $class = $message->json_class;
  $message  = $message->json_class('Mojo::JSON');

Class to be used for JSON deserialization with the C<json> method, defaults
to L<Mojo::JSON>.

=head2 C<max_message_size>

  my $size = $message->max_message_size;
  $message = $message->max_message_size(1024);

Maximum message size in bytes, defaults to the value of the
C<MOJO_MAX_MESSAGE_SIZE> environment variable or C<5242880>. Increasing this
value can also drastically increase memory usage, should you for example
attempt to parse an excessively large message body with C<body_params>,
C<dom> or C<json>.

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

  my $params = $message->body_params;

C<POST> parameters extracted from C<x-application-urlencoded>,
C<application/x-www-form-urlencoded> or C<multipart/form-data> message body,
usually a L<Mojo::Parameters> object.

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
L<Mojo::Cookie::Response> objects.

  say $message->cookie('foo')->value;

=head2 C<dom>

  my $dom        = $message->dom;
  my $collection = $message->dom('a[href]');

Turns message body into a L<Mojo::DOM> object and takes an optional selector
to perform a C<find> on it right away, which returns a collection.

  # Perform "find" right away
  $message->dom('h1, h2, h3')->each(sub { say $_->text });

  # Use everything else Mojo::DOM has to offer
  say $message->dom->at('title')->text;
  $message->dom->html->body->children->each(sub { say $_->type });

=head2 C<error>

  my $message          = $message->error;
  my ($message, $code) = $message->error;
  $message             = $message->error('Parser error.');
  $message             = $message->error('Parser error.', 500);

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

Alias for L<Mojo::Content/"is_dynamic">. Note that this method is
EXPERIMENTAL and might change without warning!

=head2 C<is_finished>

  my $success = $message->is_finished;

Check if parser is finished.

=head2 C<is_limit_exceeded>

  my $success = $message->is_limit_exceeded;

Check if message has exceeded C<max_line_size> or C<max_message_size>. Note
that this method is EXPERIMENTAL and might change without warning!

=head2 C<is_multipart>

  my $success = $message->is_multipart;

Alias for L<Mojo::Content/"is_multipart">.

=head2 C<json>

  my $object = $message->json;
  my $array  = $message->json;
  my $value  = $message->json('/foo/bar');

Decode JSON message body directly using L<Mojo::JSON> if possible, returns
C<undef> otherwise. An optional JSON Pointer can be used to extract a
specific value with L<Mojo::JSON::Pointer>.

  say $message->json->{foo}->{bar}->[23];
  say $message->json('/foo/bar/23');

=head2 C<leftovers>

  my $bytes = $message->leftovers;

Alias for L<Mojo::Content/"leftovers">.

=head2 C<max_line_size>

  $message->max_line_size(1024);

Alias for L<Mojo::Headers/"max_line_size">. Note that this method is
EXPERIMENTAL and might change without warning!

=head2 C<param>

  my $param  = $message->param('foo');
  my @params = $message->param('foo');

Access C<GET> and C<POST> parameters.

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
