# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Message;

use strict;
use warnings;

use base 'Mojo::Stateful';
use overload '""' => sub { shift->to_string }, fallback => 1;

use Carp 'croak';
use Mojo::Asset::Memory;
use Mojo::ByteStream 'b';
use Mojo::Content::Single;
use Mojo::Parameters;
use Mojo::Upload;

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 8192;

__PACKAGE__->attr(buffer  => sub { Mojo::ByteStream->new });
__PACKAGE__->attr(content => sub { Mojo::Content::Single->new });
__PACKAGE__->attr(default_charset => 'UTF-8');
__PACKAGE__->attr([qw/finish_cb progress_cb/]);
__PACKAGE__->attr([qw/major_version minor_version/] => 1);

# I'll keep it short and sweet. Family. Religion. Friendship.
# These are the three demons you must slay if you wish to succeed in
# business.
sub at_least_version {
    my ($self, $version) = @_;
    my ($major, $minor) = split /\./, $version;

    # Version is equal or newer
    return 1 if $major < $self->major_version;
    if ($major == $self->major_version) {
        return 1 if $minor <= $self->minor_version;
    }

    # Version is older
    return;
}

sub body {
    my $self = shift;

    # Downgrade multipart content
    $self->content(Mojo::Content::Single->new)
      if $self->content->isa('Mojo::Content::MultiPart');

    # Get
    unless (@_) {
        return $self->body_cb
          ? $self->body_cb
          : return $self->content->asset->slurp;
    }

    # New content
    my $content = shift;

    # Cleanup
    $self->body_cb(undef);
    $self->content->asset(Mojo::Asset::Memory->new);

    # Shortcut
    return $self unless defined $content;

    # Callback
    if (ref $content eq 'CODE') { $self->body_cb($content) }

    # Set text content
    elsif (length $content) { $self->content->asset->add_chunk($content) }

    return $self;
}

sub body_cb { shift->content->body_cb(@_) }

sub body_params {
    my $self = shift;

    # Cached
    return $self->{_body_params} if $self->{_body_params};

    my $params = Mojo::Parameters->new;
    my $type = $self->headers->content_type || '';

    # Charset
    $params->charset($self->default_charset);
    $type =~ /charset=\"?(\S+)\"?/;
    $params->charset($1) if $1;

    # "x-application-urlencoded" and "application/x-www-form-urlencoded"
    if ($type =~ /(?:x-application|application\/x-www-form)-urlencoded/i) {

        # Parse
        $params->parse($self->content->asset->slurp);
    }

    # "multipart/formdata"
    elsif ($type =~ /multipart\/form-data/i) {
        my $formdata = $self->_parse_formdata;

        # Formdata
        for my $data (@$formdata) {
            my $name     = $data->[0];
            my $filename = $data->[1];
            my $value    = $data->[2];

            # File
            next if $filename;

            $params->append($name, $value);
        }
    }

    # Cache
    return $self->{_body_params} = $params;
}

sub body_size { shift->content->body_size }

sub build {
    my $self    = shift;
    my $message = '';

    # Start line
    $message .= $self->build_start_line;

    # Headers
    $message .= $self->build_headers;

    # Body
    $message .= $self->build_body;

    return $message;
}

# My new movie is me, standing in front of a brick wall for 90 minutes.
# It cost 80 million dollars to make.
# How do you sleep at night?
# On top of a pile of money, with many beautiful women.
sub build_body {
    my $self = shift;

    # Body
    my $body = $self->content->build_body(@_);

    # Finished
    if (my $cb = $self->finish_cb) { $self->$cb }

    return $body;
}

sub build_headers {
    my $self = shift;

    # HTTP 0.9 has no headers
    return '' if $self->version eq '0.9';

    # Fix headers
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

    # Shortcut
    return unless $name;

    # Map
    unless ($self->{_cookies}) {
        my $cookies = {};
        for my $cookie (@{$self->cookies}) {
            my $cname = $cookie->name;

            # Multiple cookies with same name
            if (exists $cookies->{$cname}) {
                $cookies->{$cname} = [$cookies->{$cname}]
                  unless ref $cookies->{$cname} eq 'ARRAY';
                push @{$cookies->{$cname}}, $cookie;
            }

            # Cookie
            else { $cookies->{$cname} = $cookie }
        }

        # Cache
        $self->{_cookies} = $cookies;
    }

    # Multiple
    my $cookies = $self->{_cookies}->{$name};
    my @cookies;
    @cookies = ref $cookies eq 'ARRAY' ? @$cookies : ($cookies) if $cookies;

    # Context
    return wantarray ? @cookies : $cookies[0];
}

sub fix_headers {
    my $self = shift;

    # Content-Length header is required in HTTP 1.0 (and above) messages if
    # there's a body, sadly many clients are expecting broken server behavior
    # if the Content-Length header is missing, so we are defaulting to
    # "Content-Length: 0" which has proven to just work in the real world
    if ($self->at_least_version('1.0') && !$self->is_chunked) {
        $self->headers->content_length($self->body_size)
          unless $self->headers->content_length;
    }

    return $self;
}

sub get_body_chunk {
    my $self = shift;

    # Progress
    if (my $cb = $self->progress_cb) { $self->$cb('body', @_) }

    # Chunk
    if (defined(my $chunk = $self->content->get_body_chunk(@_))) {
        return $chunk;
    }

    # Finished
    if (my $cb = $self->finish_cb) { $self->$cb }

    return;
}

sub get_header_chunk {
    my $self = shift;

    # Progress
    if (my $cb = $self->progress_cb) { $self->$cb('headers', @_) }

    # HTTP 0.9 has no headers
    return '' if $self->version eq '0.9';

    # Fix headers
    $self->fix_headers;

    $self->content->get_header_chunk(@_);
}

sub get_start_line_chunk {
    my ($self, $offset) = @_;

    # Progress
    if (my $cb = $self->progress_cb) { $self->$cb('start_line', @_) }

    my $copy = $self->_build_start_line;
    return substr($copy, $offset, CHUNK_SIZE);
}

sub has_leftovers { shift->content->has_leftovers }

sub header_size {
    my $self = shift;

    # Fix headers
    $self->fix_headers;

    return $self->content->header_size;
}

sub headers { shift->content->headers(@_) }

sub is_chunked { shift->content->is_chunked }

sub is_multipart { shift->content->is_multipart }

sub leftovers { shift->content->leftovers }

sub param {
    my $self = shift;
    $self->{body_params} ||= $self->body_params;
    return $self->{body_params}->param(@_);
}

sub parse {
    my ($self, $chunk) = @_;

    # Buffer
    $self->buffer->add_chunk($chunk) if defined $chunk;

    return $self->_parse(0);
}

sub parse_until_body {
    my ($self, $chunk) = @_;

    # Buffer
    $self->buffer->add_chunk($chunk);

    return $self->_parse(1);
}

sub start_line_size { length shift->build_start_line }

sub to_string { shift->build(@_) }

sub upload {
    my ($self, $name) = @_;

    # Shortcut
    return unless $name;

    # Map
    unless ($self->{_uploads}) {
        my $uploads = {};
        for my $upload (@{$self->uploads}) {
            my $uname = $upload->name;

            # Multiple uploads with same name
            if (exists $uploads->{$name}) {
                $uploads->{$uname} = [$uploads->{$uname}]
                  unless ref $uploads->{$uname} eq 'ARRAY';
                push @{$uploads->{$uname}}, $upload;
            }

            # Upload
            else { $uploads->{$uname} = $upload }
        }

        # Cache
        $self->{_uploads} = $uploads;
    }

    # Multiple
    my $uploads = $self->{_uploads}->{$name};
    my @uploads;
    @uploads = ref $uploads eq 'ARRAY' ? @$uploads : ($uploads) if $uploads;

    return wantarray ? @uploads : $uploads[0];
}

sub uploads {
    my $self = shift;

    my @uploads;
    return \@uploads unless $self->is_multipart;

    my $formdata = $self->_parse_formdata;

    # Formdata
    for my $data (@$formdata) {
        my $name     = $data->[0];
        my $filename = $data->[1];
        my $part     = $data->[2];

        next unless $filename;

        my $upload = Mojo::Upload->new;
        $upload->name($name);
        $upload->asset($part->asset);
        $upload->filename($filename);
        $upload->headers($part->headers);

        push @uploads, $upload;
    }

    return \@uploads;
}

sub version {
    my ($self, $version) = @_;

    # Return normalized version
    unless ($version) {
        my $major = $self->major_version;
        $major = 1 unless defined $major;
        my $minor = $self->minor_version;
        $minor = 1 unless defined $minor;
        return "$major.$minor";
    }

    # New version
    my ($major, $minor) = split /\./, $version;
    $self->major_version($major);
    $self->minor_version($minor);

    return $self;
}

sub _build_start_line {
    croak 'Method "_build_start_line" not implemented by subclass';
}

sub _parse {
    my $self = shift;
    my $until_body = @_ ? shift : 0;

    # Progress
    if (my $cb = $self->progress_cb) { $self->$cb }

    # Start line and headers
    my $buffer = $self->buffer;
    if ($self->is_state(qw/start headers/)) {

        # Check line size
        $self->error(413, 'Maximum line size exceeded.')
          if $buffer->size > ($ENV{MOJO_MAX_LINE_SIZE} || 10240);
    }

    # Check message size
    $self->error(413, 'Maximum message size exceeded.')
      if $buffer->raw_size > ($ENV{MOJO_MAX_MESSAGE_SIZE} || 524288);

    # Content
    if ($self->is_state(qw/content done done_with_leftovers/)) {
        my $content = $self->content;

        # HTTP 0.9 has no headers
        $content->state('body') if $self->version eq '0.9';

        # Parse
        $content->filter_buffer($buffer);

        # Until body
        if ($until_body) { $self->content($content->parse_until_body) }

        # Whole message
        else { $self->content($content->parse) }

        # HTTP 0.9 has no defined length
        $content->state('done') if $self->version eq '0.9';
    }

    # Done
    $self->done if $self->content->is_done;

    # Done with leftovers, maybe pipelined
    $self->state('done_with_leftovers')
      if $self->content->is_state('done_with_leftovers');

    # Finished
    if ((my $cb = $self->finish_cb) && $self->is_finished) { $self->$cb }

    return $self;
}

sub _parse_formdata {
    my $self = shift;

    my @formdata;

    # Check content
    my $content = $self->content;
    return \@formdata unless $content->is_multipart;

    # Default charset
    my $default = $self->default_charset;
    if (my $type = $self->headers->content_type) {
        $type =~ /charset=\"?(\S+)\"?/;
        $default = $1 if $1;
    }

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
        my $charset = $default;
        if (my $type = $part->headers->content_type) {
            $type =~ /charset=\"?(\S+)\"?/;
            $charset = $1 if $1;
        }

        # "Content-Disposition"
        my $disposition = $part->headers->content_disposition;
        next unless $disposition;
        my ($name)     = $disposition =~ /\ name="?([^\";]+)"?/;
        my ($filename) = $disposition =~ /\ filename="?([^\"]*)"?/;
        my $value      = $part;

        # Unescape
        $name     = b($name)->url_unescape->to_string;
        $filename = b($filename)->url_unescape->to_string;

        # Decode
        if ($charset) {
            my $backup = $name;
            $name     = b($name)->decode($charset)->to_string;
            $name     = $backup unless defined $name;
            $backup   = $filename;
            $filename = b($filename)->decode($charset)->to_string;
            $filename = $backup unless defined $filename;
        }

        # Form value
        unless ($filename) {

            # Slurp
            $value = $part->asset->slurp;

            # Decode
            if ($charset && !$part->headers->content_transfer_encoding) {
                my $backup = $value;
                $value = b($value)->decode($charset)->to_string;
                $value = $backup unless defined $value;
            }
        }

        push @formdata, [$name, $filename, $value];
    }

    return \@formdata;
}

1;
__END__

=head1 NAME

Mojo::Message - HTTP 1.1 Message Base Class

=head1 SYNOPSIS

    use base 'Mojo::Message';

=head1 DESCRIPTION

L<Mojo::Message> is an abstract base class for HTTP 1.1 messages as described
in RFC 2616 and RFC 2388.

=head1 ATTRIBUTES

L<Mojo::Message> inherits all attributes from L<Mojo::Stateful> and
implements the following new ones.

=head2 C<body_cb>

    my $cb = $message->body_cb;

    $counter = 1;
    $message = $message->body_cb(sub {
        my $self  = shift;
        my $chunk = '';
        $chunk    = "hello world!" if $counter == 1;
        $chunk    = "hello world2!\n\n" if $counter == 2;
        $counter++;
        return $chunk;
    });

Content generator callback.

=head2 C<buffer>

    my $buffer = $message->buffer;
    $message   = $message->buffer(Mojo::ByteStream->new);

Input buffer for parsing.

=head2 C<content>

    my $content = $message->content;
    $message    = $message->content(Mojo::Content::Single->new);

Content container, defaults to a L<Mojo::Content::Single> object.

=head2 C<default_charset>

    my $charset = $message->default_charset;
    $message    = $message->default_charset('UTF-8');

Default charset used for form data parsing.

=head2 C<finish_cb>

    my $cb   = $message->finish_cb;
    $message = $message->finish_cb(sub {
        my $self = shift;
    });

Callback called after message building or parsing is finished.

=head2 C<headers>

    my $headers = $message->headers;
    $message    = $message->headers(Mojo::Headers->new);

Header container, defaults to a L<Mojo::Headers> object.

=head2 C<major_version>

    my $major_version = $message->major_version;
    $message          = $message->major_version(1);

Major version, defaults to C<1>.

=head2 C<minor_version>

    my $minor_version = $message->minor_version;
    $message          = $message->minor_version(1);

Minor version, defaults to C<1>.

=head2 C<progress_cb>

    my $cb   = $message->progress_cb;
    $message = $message->progress_cb(sub {
        my $self = shift;
        print '+';
    });

Progress callback.

=head1 METHODS

L<Mojo::Message> inherits all methods from L<Mojo::Stateful> and implements
the following new ones.

=head2 C<at_least_version>

    my $success = $message->at_least_version('1.1');

Check if message is at least a specific version.

=head2 C<body>

    my $string = $message->body;
    $message   = $message->body('Hello!');

    $counter = 1;
    $message = $message->body(sub {
        my $self  = shift;
        my $chunk = '';
        $chunk    = "hello world!" if $counter == 1;
        $chunk    = "hello world2!\n\n" if $counter == 2;
        $counter++;
        return $chunk;
    });

Helper for simplified content access.

=head2 C<body_params>

    my $params = $message->body_params;

C<POST> parameters.

=head2 C<body_size>

    my $size = $message->body_size;

Size of the body in bytes.

=head2 C<to_string>

=head2 C<build>

    my $string = $message->build;

Render whole message.

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

Access message cookies.

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

    my $leftovers = $message->has_leftovers;

CHeck if message parser has leftover data in the buffer.

=head2 C<header_size>

    my $size = $message->header_size;

Size of headers.

=head2 C<is_chunked>

    my $chunked = $message->is_chunked;

Check if message content is chunked.

=head2 C<is_multipart>

    my $multipart = $message->is_multipart;

Check if message content is multipart.

=head2 C<leftovers>

    my $bytes = $message->leftovers;

Remove leftover data from the parser buffer.

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

Size of the start line.

=head2 C<upload>

    my $upload  = $message->upload('foo');
    my @uploads = $message->upload('foo');

Access file uploads.

=head2 C<uploads>

    my $uploads = $message->uploads;

All file uploads.

=head2 C<version>

    my $version = $message->version;
    $message    = $message->version('1.1');

HTTP version of message.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
