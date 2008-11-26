# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Message;

use strict;
use warnings;

use base 'Mojo::Stateful';
use overload '""' => sub { shift->to_string }, fallback => 1;
use bytes;

use Carp 'croak';
use Mojo::Buffer;
use Mojo::ByteStream;
use Mojo::Content;
use Mojo::File::Memory;
use Mojo::Parameters;
use Mojo::Upload;
use Mojo::URL;

__PACKAGE__->attr(
    buffer => (
        chained => 1,
        default => sub { Mojo::Buffer->new }
    )
);
__PACKAGE__->attr(
    [qw/build_start_line_cb parser_progress_cb/] => (chained => 1));
__PACKAGE__->attr(
    content => (
        chained => 1,
        default => sub { Mojo::Content->new }
    )
);
__PACKAGE__->attr(
    [qw/major_version minor_version/] => (
        chained => 1,
        default => 1
    )
);

# I'll keep it short and sweet. Family. Religion. Friendship.
# These are the three demons you must slay if you wish to succeed in
# business.
sub at_least_version {
    my ($self, $version) = @_;
    my ($major, $minor) = split /\./, $version;

    # Version is equal or newer
    return 1 if $major > $self->major_version;
    if ($major == $self->major_version) {
        return 1 if $minor <= $self->minor_version;
    }

    # Version is older
    return 0;
}

sub body {
    my ($self, $content) = @_;

    # Plain old content
    unless ($self->is_multipart) {

        # Get/Set content
        if ($content) {
            $self->content->file(Mojo::File::Memory->new);
            $self->content->file->add_chunk($content);
        }
        return $self->content->file->slurp;
    }

    $self->content($content);
    return $self->content;
}

sub body_length { shift->content->body_length }

sub body_params {
    my $self = shift;

    # Cached
    return $self->{_body_params} if $self->{_body_params};

    my $params = Mojo::Parameters->new;

    # "x-application-urlencoded" and "application/x-www-form-urlencoded"
    my $content_type = $self->headers->content_type || '';
    if ($content_type
        =~ /(?:x-application|application\/x-www-form)-urlencoded/i)
    {

        # Parse
        my $raw = $self->content->file->slurp;
        $params->parse($raw);

        return $params;
    }

    # "multipart/formdata"
    elsif ($content_type =~ /multipart\/form-data/i) {
        my $formdata = $self->_parse_formdata;

        # Formdata
        for my $data (@$formdata) {
            my $name     = $data->[0];
            my $filename = $data->[1];
            my $part     = $data->[2];

            $params->append($name, $part->file->slurp) unless $filename;
        }
    }

    # Cache
    return $self->{_body_params} = $params;
}

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

sub build_body_cb { shift->content->build_body_cb(@_) }

sub build_headers {
    my $self = shift;

    # HTTP 0.9 has no headers
    return '' if $self->version eq '0.9';

    # Fix headers
    $self->fix_headers;

    return $self->content->build_headers;
}

sub build_headers_cb { shift->content->build_headers_cb(@_) }

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

sub builder_progress_cb { shift->content->builder_progress_cb(@_) }

sub cookie {
    my ($self, $name) = @_;

    # Shortcut
    return undef unless $name;

    # Map
    unless ($self->{_cookies}) {
        my $cookies = {};
        for my $cookie (@{$self->cookies}) {
            my $cname = $cookie->name;

            # Multiple cookies with same name
            if (exists $cookies->{$name}) {
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

    return $self->{_cookies}->{$name};
}

sub fix_headers {
    my $self = shift;

    # Content-Length header is required in HTTP 1.0 messages
    if ($self->at_least_version('1.0') && !$self->is_chunked) {
        $self->headers->content_length($self->body_length)
          unless $self->headers->content_length;
    }

    return $self;
}

sub get_body_chunk { shift->content->get_body_chunk(@_) }

sub get_header_chunk {
    my $self = shift;

    # Progress
    $self->builder_progress_cb->($self) if $self->builder_progress_cb;

    # HTTP 0.9 has no headers
    return '' if $self->version eq '0.9';

    # Fix headers
    $self->fix_headers;

    $self->content->get_header_chunk(@_);
}

sub get_start_line_chunk {
    my ($self, $offset) = @_;

    # Progress
    $self->builder_progress_cb->($self) if $self->builder_progress_cb;

    # Start line generator
    return $self->build_start_line_cb->($self, $offset)
      if $self->build_start_line_cb;

    my $copy = $self->_build_start_line;
    return substr($copy, $offset, 4096);
}

sub header_length { shift->content->header_length }

sub headers { shift->content->headers(@_) }

sub is_chunked { shift->content->is_chunked }

sub is_multipart { shift->content->is_multipart }

sub param {
    my $self = shift;
    $self->{body_params} ||= $self->body_params;
    return $self->{body_params}->param(@_);
}

# Please don't eat me! I have a wife and kids. Eat them!
sub parse {
    my $self = shift;

    # Buffer
    $self->buffer->add_chunk(join '', @_) if @_;

    # Progress
    $self->parser_progress_cb->($self) if $self->parser_progress_cb;

    # Content
    if ($self->is_state(qw/content done/)) {
        my $content = $self->content;
        $content->state('body') if $self->version eq '0.9';
        $content->filter_buffer($self->buffer);
        $self->content($content->parse);
    }

    # Done
    $self->done if $self->content->is_done;

    return $self;
}

sub start_line_length { return length shift->build_start_line }

sub to_string { shift->build(@_) }

sub upload {
    my ($self, $name) = @_;

    # Shortcut
    return undef unless $name;

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

    return $self->{_uploads}->{$name};
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
        $upload->file($part->file);
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

=head2 C<body_length>

    my $body_length = $message->body_length;

=head2 C<buffer>

    my $buffer = $message->buffer;
    $message   = $message->buffer(Mojo::Buffer->new);

=head2 C<build_body_cb>

    my $cb = $message->build_body_cb;

    $counter = 1;
    $message = $message->build_body_cb(sub {
        my $self  = shift;
        my $chunk = '';
        $chunk    = "hello world!" if $counter == 1;
        $chunk    = "hello world2!\n\n" if $counter == 2;
        $counter++;
        return $chunk;
    });

=head2 C<build_headers_cb>

    my $cb = $message->build_headers_cb;

    $message = $message->build_headers_cb(sub {
        my $h = Mojo::Headers->new;
        $h->content_type('text/plain');
        return $h->to_string;
    });

=head2 C<build_start_line_cb>

    my $cb = $message->build_start_line_cb;

    $message = $content->build_start_line_cb(sub {
        return "HTTP/1.1 200 OK\r\n\r\n";
    });

=head2 C<builder_progress_cb>

    my $cb   = $message->builder_progress_cb;
    $message = $message->builder_progress_cb(sub {
        my $self = shift;
        print '+';
    });

=head2 C<content>

    my $content = $message->content;
    $message    = $message->content(Mojo::Content->new);

=head2 C<header_length>

    my $header_length = $message->header_length;

=head2 C<headers>

    my $headers = $message->headers;
    $message    = $message->headers(Mojo::Headers->new);

=head2 C<major_version>

    my $major_version = $message->major_version;
    $message          = $message->major_version(1);

The major version of the HTTP specification being followed. Defaults to 1.

=head2 C<minor_version>

    my $minor_version = $message->minor_version;
    $message          = $message->minor_version(1);

The minor version of the HTTP specification being followed. Defaults to 1.

=head2 C<parser_progress_cb>

    my $cb   = $message->parser_progress_cb;
    $message = $message->parser_progress_cb(sub {
        my $self = shift;
        print '+';
    });

=head2 C<raw_body_length>

    my $raw_body_length = $message->raw_body_length;

=head2 C<start_line_length>

    my $start_line_length = $message->start_line_length;

=head2 C<version>

    my $version = $message->version;
    $message    = $message->version('1.1');

=head1 METHODS

L<Mojo::Message> inherits all methods from L<Mojo::Stateful> and implements
the following new ones.

=head2 C<body>

    my $string = $message->body;
    $message = $message->body('Hello!');

=head2 C<body_params>

    my $params = $message->body_params;

Returns a L<Mojo::Parameters> object, containing POST parameters.

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

    my $cookie = $message->cookie('foo');

=head2 C<fix_headers>

    $message = $message->fix_headers;

For HTTP 1.0 and newer, add the required C<< Content-Length >> header if the
message is not chunked and the header has not already been set.

=head2 C<get_body_chunk>

    my $string = $message->get_body_chunk($offset);

=head2 C<get_header_chunk>

    my $string = $message->get_header_chunk($offset);

=head2 C<get_start_line_chunk>

    my $string = $message->get_start_line_chunk($offset);

=head2 C<is_chunked>

    my $is_chunked = $message->is_chunked;

=head2 C<is_multipart>

    my $is_multipart = $message->is_multipart;

=head2 C<at_least_version>

    my $success = $message->at_least_version('1.1');

Returns true if the message version is greater than or equal to the version
passed in.

=head2 C<param>

    my $param = $message->param('foo');

=head2 C<parse>

    $message = $message->parse('HTTP/1.1 200 OK...');

=head2 C<upload>

    my $upload = $message->upload('foo');

Returns a L<Mojo::Upload> object or a arrayref of L<Mojo::Upload> objects.

=head2 C<uploads>

    my $uploads = $message->uploads;

Returns a arrayref of L<Mojo::Upload> objects.

=cut
