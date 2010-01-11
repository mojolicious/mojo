# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Message::Response;

use strict;
use warnings;

use base 'Mojo::Message';

use Mojo::Cookie::Response;
use Mojo::Date;

__PACKAGE__->attr([qw/code message/]);

# Umarked codes are from RFC 2616 (mostly taken from LWP)
my %MESSAGES = (
    100 => 'Continue',
    101 => 'Switching Protocols',
    102 => 'Processing',                      # RFC 2518 (WebDAV)
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    203 => 'Non-Authoritative Information',
    204 => 'No Content',
    205 => 'Reset Content',
    206 => 'Partial Content',
    207 => 'Multi-Status',                    # RFC 2518 (WebDAV)
    300 => 'Multiple Choices',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    305 => 'Use Proxy',
    307 => 'Temporary Redirect',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    402 => 'Payment Required',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    406 => 'Not Acceptable',
    407 => 'Proxy Authentication Required',
    408 => 'Request Timeout',
    409 => 'Conflict',
    410 => 'Gone',
    411 => 'Length Required',
    412 => 'Precondition Failed',
    413 => 'Request Entity Too Large',
    414 => 'Request-URI Too Large',
    415 => 'Unsupported Media Type',
    416 => 'Request Range Not Satisfiable',
    417 => 'Expectation Failed',
    418 => "I'm a teapot",                    # :)
    422 => 'Unprocessable Entity',            # RFC 2518 (WebDAV)
    423 => 'Locked',                          # RFC 2518 (WebDAV)
    424 => 'Failed Dependency',               # RFC 2518 (WebDAV)
    425 => 'Unordered Colection',             # RFC 3648 (WebDav)
    426 => 'Upgrade Required',                # RFC 2817
    449 => 'Retry With',                      # unofficial Microsoft
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    505 => 'HTTP Version Not Supported',
    506 => 'Variant Also Negotiates',         # RFC 2295
    507 => 'Insufficient Storage',            # RFC 2518 (WebDAV)
    509 => 'Bandwidth Limit Exceeded',        # unofficial
    510 => 'Not Extended'                     # RFC 2774
);

sub cookies {
    my $self = shift;

    # Add cookies
    if (@_) {
        for my $cookie (@_) {
            $cookie = Mojo::Cookie::Response->new($cookie)
              if ref $cookie eq 'HASH';
            $self->headers->add('Set-Cookie', "$cookie");
        }
        return $self;
    }

    # Set-Cookie2
    my $cookies = [];
    if (my $cookie2 = $self->headers->set_cookie2) {
        push @$cookies, @{Mojo::Cookie::Response->parse($cookie2)};
    }

    # Set-Cookie
    if (my $cookie = $self->headers->set_cookie) {
        push @$cookies, @{Mojo::Cookie::Response->parse($cookie)};
    }

    # No cookies
    return $cookies;
}

sub default_message { $MESSAGES{$_[1] || $_[0]->code || 200} }

sub fix_headers {
    my $self = shift;

    $self->SUPER::fix_headers(@_);

    # Date header is required in responses
    $self->headers->date(Mojo::Date->new->to_string)
      unless $self->headers->date;

    return $self;
}

sub is_status_class {
    my ($self, $class) = @_;
    return 1 if ($self->code >= $class && $self->code < ($class + 100));
    return;
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

sub _parse {
    my $self = shift;
    my $until_body = @_ ? shift : 0;

    # Start line
    $self->_parse_start_line if $self->is_state('start');

    # Pass through
    return $self->SUPER::_parse($until_body);
}

sub _build_start_line {
    my $self    = shift;
    my $version = $self->version;

    # HTTP 0.9 has no start line
    return '' if $version eq '0.9';

    # HTTP 1.0 and above
    my $code    = $self->code    || 200;
    my $message = $self->message || $self->default_message;
    return "HTTP/$version $code $message\x0d\x0a";
}

# Weaseling out of things is important to learn.
# It's what separates us from the animals... except the weasel.
sub _parse_start_line {
    my $self = shift;

    # HTTP 0.9 responses have no start line
    return $self->state('content') if $self->version eq '0.9';

    # Try to detect HTTP 0.9
    my $buffer = $self->buffer;
    if ($buffer =~ /^\s*(\S+\s*)/) {
        my $string = $1;

        # HTTP 0.9 will most likely not start with "HTTP/"
        my $match = "\/PTTH";
        substr $match, 0, 5 - length $string, '' if length $string < 5;
        $match = reverse $match;

        # Detected!
        if ($string !~ /^\s*$match/) {
            $self->major_version(0);
            $self->minor_version(9);
            $self->state('content');
            $self->content->relaxed(1);
            return 1;
        }
    }

    # We have a full HTTP 1.0+ response line
    my $line = $buffer->get_line;
    if (defined $line) {
        if ($line =~ /
            ^\s*              # Start
            HTTP\/(\d)\.(\d)  # Version
            \s+               # Whitespace
            (\d\d\d)          # Code
            \s+               # Whitespace
            ([\w\s]+)         # Message
            $                 # End
        /x
          )
        {
            $self->major_version($1);
            $self->minor_version($2);
            $self->code($3);
            $self->message($4);
            $self->state('content');
        }
        else { $self->error('Parser error: Invalid response line.') }
    }
}

1;
__END__

=head1 NAME

Mojo::Message::Response - Response

=head1 SYNOPSIS

    use Mojo::Message::Response;

    my $res = Mojo::Message::Response->new;
    $res->code(200);
    $res->headers->content_type('text/plain');
    $res->body('Hello World!');

    print "$res";

    $res->parse('HTTP/1.1 200 OK');

=head1 DESCRIPTION

L<Mojo::Message::Response> is a container for HTTP responses.

=head1 ATTRIBUTES

L<Mojo::Message::Response> inherits all attributes from L<Mojo::Message>
and implements the following new ones.

=head2 C<code>

    my $code = $res->code;
    $res     = $res->code(200);

=head2 C<message>

    my $message = $res->message;
    $res        = $res->message('OK');

=head1 METHODS

L<Mojo::Message::Response> inherits all methods from L<Mojo::Message> and
implements the following new ones.

=head2 C<cookies>

    my $cookies = $res->cookies;
    $res        = $res->cookies(Mojo::Cookie::Response->new);
    $req        = $req->cookies({name => 'foo', value => 'bar'});

=head2 C<default_message>

    my $message = $res->default_message;

=head2 C<fix_headers>

    $res = $res->fix_headers;

=head2 C<is_status_class>

    my $is_2xx = $res->is_status_class(200);

=head2 C<parse>

    $res = $res->parse('HTTP/1.1 200 OK');

=head2 C<parse_until_body>

    $res = $res->parse_until_body('HTTP/1.1 200 OK');

=cut
