# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Message;

use strict;
use warnings;

use base 'Mojo::Stateful';
use overload '""' => sub { shift->to_string }, fallback => 1;
use bytes;

use Carp 'croak';
use Mojo::Asset::Memory;
use Mojo::Buffer;
use Mojo::ByteStream 'b';
use Mojo::Content::Single;
use Mojo::Parameters;
use Mojo::Upload;

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 8192;

__PACKAGE__->attr(buffer  => sub { Mojo::Buffer->new });
__PACKAGE__->attr(content => sub { Mojo::Content::Single->new });
__PACKAGE__->attr(default_charset                   => 'UTF-8');
__PACKAGE__->attr([qw/major_version minor_version/] => 1);

__PACKAGE__->attr([qw/_body_params _cookies _uploads/]);

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
    return $self->_body_params if $self->_body_params;

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
            my $part     = $data->[2];

            # File
            next if $filename;

            # Charset
            my $charset;
            if (my $type = $part->headers->content_type) {
                $type =~ /charset=\"?(\S+)\"?/;
                $charset = $1 if $1;
            }

            # Value
            my $value = $part->asset->slurp;

            # Try to decode
            if ($charset) {
                my $backup = $value;
                $value = b($value)->decode($charset)->to_string;
                $value = $backup unless defined $value;
            }

            $params->append($name, $value);
        }
    }

    # Cache
    return $self->_body_params($params)->_body_params;
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
sub build_body { shift->content->build_body(@_) }

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
    unless ($self->_cookies) {
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
        $self->_cookies($cookies);
    }

    # Multiple?
    my @cookies =
      ref $self->_cookies->{$name} eq 'ARRAY'
      ? @{$self->_cookies->{$name}}
      : ($self->_cookies->{$name});

    # Context?
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

sub get_body_chunk { shift->content->get_body_chunk(@_) }

sub get_header_chunk {
    my $self = shift;

    # Progress
    $self->progress_cb->($self, 'headers', @_) if $self->progress_cb;

    # HTTP 0.9 has no headers
    return '' if $self->version eq '0.9';

    # Fix headers
    $self->fix_headers;

    $self->content->get_header_chunk(@_);
}

sub get_start_line_chunk {
    my ($self, $offset) = @_;

    # Progress
    $self->progress_cb->($self, 'start_line', $offset) if $self->progress_cb;

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

sub progress_cb { shift->content->progress_cb(@_) }

sub start_line_size { length shift->build_start_line }

sub to_string { shift->build(@_) }

sub upload {
    my ($self, $name) = @_;

    # Shortcut
    return unless $name;

    # Map
    unless ($self->_uploads) {
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
        $self->_uploads($uploads);
    }

    my @uploads =
      ref $self->_uploads->{$name} eq 'ARRAY'
      ? @{$self->_uploads->{$name}}
      : ($self->_uploads->{$name});
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
    $self->progress_cb->($self) if $self->progress_cb;

    # Content
    if ($self->is_state(qw/content done done_with_leftovers/)) {
        my $content = $self->content;

        # HTTP 0.9 has no headers
        $content->state('body') if $self->version eq '0.9';

        # Parse
        $content->filter_buffer($self->buffer);

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

    return $self;
}

sub _parse_formdata {
    my $self = shift;

    my @formdata;

    # Check content
    my $content = $self->content;
    return \@formdata unless $content->is_multipart;

    # Walk the tree
    my @parts;
    push @parts, $content;
    while (my $part = shift @parts) {

        # Multipart?
        if ($part->is_multipart) {
            unshift @parts, @{$part->parts};
            next;
        }

        # "Content-Disposition"
        my $disposition = $part->headers->content_disposition;
        next unless $disposition;
        my ($name)     = $disposition =~ /\ name="?([^\";]+)"?/;
        my ($filename) = $disposition =~ /\ filename="?([^\"]*)"?/;

        push @formdata, [$name, $filename, $part];
    }

    return \@formdata;
}

1;
__END__

=head1 NAME

Mojo::Message - Message Base Class

=head1 SYNOPSIS

    use base 'Mojo::Message';

=head1 DESCRIPTION

L<Mojo::Message> is a base class for HTTP messages.

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

=head2 C<buffer>

    my $buffer = $message->buffer;
    $message   = $message->buffer(Mojo::Buffer->new);

=head2 C<content>

    my $content = $message->content;
    $message    = $message->content(Mojo::Content::Single->new);

=head2 C<default_charset>

    my $charset = $message->default_charset;
    $message    = $message->default_charset('UTF-8');

=head2 C<headers>

    my $headers = $message->headers;
    $message    = $message->headers(Mojo::Headers->new);

=head2 C<major_version>

    my $major_version = $message->major_version;
    $message          = $message->major_version(1);

=head2 C<minor_version>

    my $minor_version = $message->minor_version;
    $message          = $message->minor_version(1);

=head2 C<progress_cb>

    my $cb   = $message->progress_cb;
    $message = $message->progress_cb(sub {
        my $self = shift;
        print '+';
    });

=head1 METHODS

L<Mojo::Message> inherits all methods from L<Mojo::Stateful> and implements
the following new ones.

=head2 C<at_least_version>

    my $success = $message->at_least_version('1.1');

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

=head2 C<body_params>

    my $params = $message->body_params;

=head2 C<body_size>

    my $size = $message->body_size;

=head2 C<to_string>

=head2 C<build>

    my $string = $message->build;

=head2 C<build_body>

    my $string = $message->build_body;

=head2 C<build_headers>

    my $string = $message->build_headers;

=head2 C<build_start_line>

    my $string = $message->build_start_line;

=head2 C<cookie>

    my $cookie  = $message->cookie('foo');
    my @cookies = $message->cookie('foo');

=head2 C<fix_headers>

    $message = $message->fix_headers;

=head2 C<get_body_chunk>

    my $string = $message->get_body_chunk($offset);

=head2 C<get_header_chunk>

    my $string = $message->get_header_chunk($offset);

=head2 C<get_start_line_chunk>

    my $string = $message->get_start_line_chunk($offset);

=head2 C<has_leftovers>

    my $leftovers = $message->has_leftovers;

=head2 C<header_size>

    my $size = $message->header_size;

=head2 C<is_chunked>

    my $chunked = $message->is_chunked;

=head2 C<is_multipart>

    my $multipart = $message->is_multipart;

=head2 C<leftovers>

    my $bytes = $message->leftovers;

=head2 C<param>

    my $param  = $message->param('foo');
    my @params = $message->param('foo');

=head2 C<parse>

    $message = $message->parse('HTTP/1.1 200 OK...');

=head2 C<parse_until_body>

    $message = $message->parse_until_body('HTTP/1.1 200 OK...');

=head2 C<start_line_size>

    my $size = $message->start_line_size;

=head2 C<upload>

    my $upload  = $message->upload('foo');
    my @uploads = $message->upload('foo');

=head2 C<uploads>

    my $uploads = $message->uploads;

=head2 C<version>

    my $version = $message->version;
    $message    = $message->version('1.1');

=cut
