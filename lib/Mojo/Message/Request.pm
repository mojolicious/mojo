# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Message::Request;

use strict;
use warnings;

use base 'Mojo::Message';

use Mojo::Cookie::Request;
use Mojo::Parameters;

__PACKAGE__->attr(method => (chained => 1, default => 'GET'));
__PACKAGE__->attr(url => (chained => 1, default => sub { Mojo::URL->new }));

sub cookies {
    my $self = shift;

    # Replace cookies
    if (@_) {
        my $cookies = shift;
        $cookies = $cookies->to_string_with_prefix;
        for my $cookie (@_) { $cookies .= "; $cookie" }
        $self->headers->header('Cookie', $cookies);
        return $self;
    }

    # Cookie
    if (my $cookie = $self->headers->cookie) {
        return Mojo::Cookie::Request->parse($cookie);
    }

    # No cookies
    return undef;
}

sub fix_headers {
    my $self = shift;

    $self->SUPER::fix_headers(@_);

    # Host header is required in HTTP 1.1 requests
    if ($self->at_least_version('1.1')) {
        my $host = $self->url->host;
        my $port = $self->url->port;
        $host .= ":$port" if $port;
        $self->headers->host($host) unless $self->headers->host;
    }

    # Proxy-Authorization header
    if ((my $proxy = $self->proxy) && !$self->headers->proxy_authorization) {

        # Basic proxy authorization
        if (my $userinfo = $proxy->userinfo) {
            my $auth = Mojo::ByteStream->new("$userinfo")->b64_encode;
            $self->headers->proxy_authorization("Basic $auth");
        }
    }

    return $self;
}

sub param {
    my $self = shift;
    $self->{params} ||= $self->params;
    return $self->{params}->param(@_);
}

sub params {
    my $self   = shift;
    my $params = Mojo::Parameters->new;
    $params->merge($self->body_params, $self->query_params);
    return $params;
}

sub parse {
    my $self = shift;

    # CGI like environment
    $self->_parse_env(shift) if ref $_[0] eq 'HASH';

    # Buffer
    $self->buffer->add_chunk(join '', @_) if @_;

    # Start line
    $self->_parse_start_line if $self->is_state('start');

    # Pass through
    return $self->SUPER::parse();
}

sub proxy {
    my ($self, $url) = @_;

    # If we have a Mojo::URL object to set
    if (ref $url) {
        $self->{proxy} = $url;
        return $self;
    }
    # If have a URL to set from a string
    elsif ($url) {
        $self->{proxy} = Mojo::URL->new($url);
        return $self;
    }
    # Default to trying %ENV
    elsif ( (not $self->{proxy}) and $ENV{HTTP_PROXY}) {
        $self->{proxy} = Mojo::URL->new( $ENV{HTTP_PROXY} );
    }

    return $self->{proxy};
}

sub query_params { return shift->url->query }

sub _build_start_line {
    my $self = shift;

    my $method  = $self->method;
    my $version = $self->version;

    # Request url
    my $url   = $self->url->path;
    my $query = $self->url->query->to_string;

    $url .= "?$query" if $query;
    $url = "/$url" unless $url =~ /^\//;
    $url = $self->url if $self->proxy;

    # HTTP 0.9
    return "$method $url\x0d\x0a" if $version eq '0.9';

    # HTTP 1.0 and above
    return "$method $url HTTP/$version\x0d\x0a";
}

sub _parse_env {
    my ($self, $env) = @_;
    $env ||= \%ENV;

    for my $name (keys %{$env}) {
        my $value = $env->{$name};

        # Headers
        if ($name =~ s/^HTTP_//i) {
            $name =~ s/_/-/g;
            $self->headers->header($name, $value);

            # Host/Port
            if ($name eq 'HOST') {
                my $host = $value;
                my $port = undef;

                if ($host =~ /^([^\:]*)\:?(.*)$/) {
                    $host = $1;
                    $port = $2;
                }

                $self->url->host($host);
                $self->url->port($port);
                $self->url->base->host($host);
                $self->url->base->port($port);
            }
        }

        # Content-Type is a special case on some servers
        elsif ($name eq 'CONTENT_TYPE') {
            $self->headers->content_type($value);
        }

        # Content-Length is a special case on some servers
        elsif ($name eq 'CONTENT_LENGTH') {
            $self->headers->content_length($value);
        }

        # Path
        elsif ($name eq 'PATH_INFO') {
            $self->url->path->parse($value);
        }

        # Query
        elsif ($name eq 'QUERY_STRING') {
            $self->url->query->parse($value);
        }

        # Method
        elsif ($name eq 'REQUEST_METHOD') { $self->method($value) }

        # Base path
        elsif ($name eq 'SCRIPT_NAME') {
            $self->url->base->path->parse($value);
        }

        # Scheme/Version
        elsif ($name eq 'SERVER_PROTOCOL') {
            $value =~ /^([^\/]*)\/*(.*)$/;
            $self->url->scheme($1)       if $1;
            $self->url->base->scheme($1) if $1;
            $self->version($2)           if $2;
        }
    }

    # There won't be a start line or header when you parse environment
    # variables
    $self->state('content');
    $self->content->state('body');
}

# Bart, with $10,000, we'd be millionaires!
# We could buy all kinds of useful things like...love!
sub _parse_start_line {
    my $self = shift;

    # We have a full request line
    my $line = $self->buffer->get_line;
    if (defined $line) {
        if ($line =~ /
            ^\s*                                           # Start
            ([a-zA-Z]+)                                    # Method
            \s+                                            # Whitespace
            ([0-9a-zA-Z\$\-_\.\!\?\#\=\*\(\)\,\%\/\&\~]+)  # Path
            (?:\s+HTTP\/(\d+)\.(\d+))?                     # Version (optional)
            $                                              # End
        /x
          )
        {
            $self->method($1);
            $self->url->parse($2);

            # HTTP 0.9 is identified by the missing version
            if (defined $3 && defined $4) {
                $self->major_version($3);
                $self->minor_version($4);
                $self->state('content');
            }
            else {
                $self->major_version(0);
                $self->minor_version(9);
                $self->done;
            }
        }
        else { $self->error('Parser error: Invalid request line') }
    }
}

1;
__END__

=head1 NAME

Mojo::Message::Request - Request

=head1 SYNOPSIS

    use Mojo::Message::Request;

    my $req = Mojo::Message::Request->new;
    $req->url->parse('http://127.0.0.1/foo/bar');
    $req->method('GET');

    print "$req";

    $req->parse('GET /foo/bar HTTP/1.1');

=head1 DESCRIPTION

L<Mojo::Message::Request> is a container for HTTP requests.

=head1 ATTRIBUTES

L<Mojo::Message::Request> inherits all attributes from L<Mojo::Message> and
implements the following new ones.

=head2 C<method>

    my $method = $req->method;
    $req       = $req->method('GET');

=head2 C<params>

    my $params = $req->params;

Returns a L<Mojo::Parameters> object, containing both GET and POST
parameters.

=head2 C<query_params>

    my $params = $req->query_params;

Returns a L<Mojo::Parameters> object, containing GET parameters.

=head2 C<url>

    my $url = $req->url;
    $req    = $req->url(Mojo::URL->new);

=head1 METHODS

L<Mojo::Message::Request> inherits all methods from L<Mojo::Message> and
implements the following new ones.

=head2 C<cookies>

    my $cookies = $req->cookies;
    $req        = $req->cookies(Mojo::Cookie::Request->new);

=head2 C<fix_headers>

    $req = $req->fix_headers;

=head2 C<param>

    my $param = $req->param('foo');

=head2 C<parse>

    $req = $req->parse('GET /foo/bar HTTP/1.1');
    $req = $req->parse({REQUEST_METHOD => 'GET'});

=head2 C<proxy>

    my $proxy = $req->proxy;
    $req      = $req->proxy('http://foo:bar@127.0.0.1:3000');
    $req      = $req->proxy( Mojo::URL->new('http://127.0.0.1:3000')  );

Returns a L< Mojo::URL > object representing an HTTP proxy for this request.
Returns the invocant when a new value is set as either a URL string or a
Mojo::URL object. If no proxy is provided explicitly this way, we will check
the value of C<< $ENV{HTTP_PROXY} >> as a fallback option.

=cut
