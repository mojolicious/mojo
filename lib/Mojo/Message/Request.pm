# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Message::Request;

use strict;
use warnings;

use base 'Mojo::Message';

use Mojo::Cookie::Request;
use Mojo::Parameters;

__PACKAGE__->attr(method => 'GET');
__PACKAGE__->attr(url => sub { Mojo::URL->new });

__PACKAGE__->attr('_params');

sub cookies {
    my $self = shift;

    # Add cookies
    if (@_) {
        my $cookies = shift;
        $cookies = Mojo::Cookie::Request->new($cookies)
          if ref $cookies eq 'HASH';
        $cookies = $cookies->to_string_with_prefix;
        for my $cookie (@_) {
            $cookie = Mojo::Cookie::Request->new($cookie)
              if ref $cookie eq 'HASH';
            $cookies .= "; $cookie";
        }
        $self->headers->add('Cookie', $cookies);
        return $self;
    }

    # Cookie
    if (my $cookie = $self->headers->cookie) {
        return Mojo::Cookie::Request->parse($cookie);
    }

    # No cookies
    return [];
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

    return $self;
}

sub param {
    my $self = shift;
    $self->_params($self->params) unless $self->_params;
    return $self->_params->param(@_);
}

sub params {
    my $self   = shift;
    my $params = Mojo::Parameters->new;
    $params->merge($self->body_params, $self->query_params);
    return $params;
}

sub parse {
    my $self = shift;

    # CGI like environment?
    my $env;
    if   (exists $_[1]) { $env = {@_} }
    else                { $env = $_[0] if ref $_[0] eq 'HASH' }

    # Parse CGI like environment or add chunk
    my $chunk = shift;
    $env ? $self->_parse_env($env) : $self->buffer->add_chunk($chunk);

    # Start line
    $self->_parse_start_line if $self->is_state('start');

    # Pass through
    $self->SUPER::parse();

    # Fix things we only know after parsing headers
    unless ($self->is_state(qw/start headers/)) {

        # Base URL
        $self->url->base->scheme('http') unless $self->url->base->scheme;
        if (!$self->url->base->authority && $self->headers->host) {
            my $host = $self->headers->host;
            $self->url->base->authority($host);
        }
    }

    return $self;
}

sub proxy {
    my ($self, $url) = @_;

    # Mojo::URL object
    if (ref $url) {
        $self->{proxy} = $url;
        return $self;
    }

    # String
    elsif ($url) {
        $self->{proxy} = Mojo::URL->new($url);
        return $self;
    }

    return $self->{proxy};
}

sub query_params { shift->url->query }

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

    # Headers
    for my $name (keys %{$env}) {
        my $value = $env->{$name};

        # Header
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
    }

    # Content-Type is a special case on some servers
    if (my $value = $env->{CONTENT_TYPE}) {
        $self->headers->content_type($value);
    }

    # Content-Length is a special case on some servers
    if (my $value = $env->{CONTENT_LENGTH}) {
        $self->headers->content_length($value);
    }

    # Path is a special case on some servers
    if (my $value = $env->{REQUEST_URI}) { $self->url->parse($value) }

    # Query
    if (my $value = $env->{QUERY_STRING}) { $self->url->query->parse($value) }

    # Method
    if (my $value = $env->{REQUEST_METHOD}) { $self->method($value) }

    # Scheme/Version
    if (my $value = $env->{SERVER_PROTOCOL}) {
        $value =~ /^([^\/]*)\/*(.*)$/;
        $self->url->scheme($1)       if $1;
        $self->url->base->scheme($1) if $1;
        $self->version($2)           if $2;
    }

    # Base path
    if (my $value = $env->{SCRIPT_NAME}) {

        # Make sure there is a trailing slash (important for merging)
        $value .= '/' unless $value =~ /\/$/;

        $self->url->base->path->parse($value);
    }

    # Path
    if (my $value = $env->{PATH_INFO}) { $self->url->path->parse($value) }

    # Fix paths
    my $base = $self->url->base->path->to_string;
    my $path = $self->url->path->to_string;

    # IIS is so fucked up, nobody should ever have to use it...
    my $software = $env->{SERVER_SOFTWARE} || '';
    if ($software =~ /IIS\/\d+/ && $base =~ /^$path\/?$/) {

        # This is a horrible hack, just like IIS itself
        if (my $t = $env->{PATH_TRANSLATED}) {
            my @p = split /\//,    $path;
            my @t = split /\\\\?/, $t;

            # Try to generate correct PATH_INFO and SCRIPT_NAME
            my @n;
            while ($p[$#p] eq $t[$#t]) {
                pop @t;
                unshift @n, pop @p;
            }
            unshift @n, '', '';

            $base = join '/', @p;
            $path = join '/', @n;

            $self->url->base->path->parse($base);
            $self->url->path->parse($path);
        }
    }

    # Fix paths for normal screwed up CGI environments
    if ($path && $base) {

        # Path ends with a slash?
        my $slash;
        $slash = 1 if $path =~ /\/$/;

        # Make sure path has a slash, because base has one
        $path .= '/' unless $slash;

        # Remove SCRIPT_NAME prefix if it's there
        $path =~ s/^$base//;

        # Remove unwanted trailing slash
        $path =~ s/\/$// unless $slash;

        # Make sure we have a leading slash
        $path = "/$path" if $path && $path !~ /^\//;

        $self->url->path->parse($path);
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

    my $line = $self->buffer->get_line;

    # Ignore any leading empty lines
    while ((defined $line) && ($line =~ m/^\s*$/)) {
        $line = $self->buffer->get_line;
    }

    # We have a (hopefully) full request line
    if (defined $line) {
        if ($line =~ /
            ^\s*                                                          # Start
            ([a-zA-Z]+)                                                   # Method
            \s+                                                           # Whitespace
            ([0-9a-zA-Z\-\.\_\~\:\/\?\#\[\]\@\!\$\&\'\(\)\*\+\,\;\=\%]+)  # Path
            (?:\s+HTTP\/(\d+)\.(\d+))?                                    # Version (optional)
            $                                                             # End
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

                # HTTP 0.9 has no headers or body and does not support
                # pipelining
                $self->buffer->empty;
            }
        }
        else { $self->error('Parser error: Invalid request line.') }
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

=head2 C<query_params>

    my $params = $req->query_params;

=head2 C<url>

    my $url = $req->url;
    $req    = $req->url(Mojo::URL->new);

=head1 METHODS

L<Mojo::Message::Request> inherits all methods from L<Mojo::Message> and
implements the following new ones.

=head2 C<cookies>

    my $cookies = $req->cookies;
    $req        = $req->cookies(Mojo::Cookie::Request->new);
    $req        = $req->cookies({name => 'foo', value => 'bar'});

=head2 C<fix_headers>

    $req = $req->fix_headers;

=head2 C<param>

    my $param = $req->param('foo');

=head2 C<parse>

    $req = $req->parse('GET /foo/bar HTTP/1.1');
    $req = $req->parse(REQUEST_METHOD => 'GET');
    $req = $req->parse({REQUEST_METHOD => 'GET'});

=head2 C<proxy>

    my $proxy = $req->proxy;
    $req      = $req->proxy('http://foo:bar@127.0.0.1:3000');
    $req      = $req->proxy( Mojo::URL->new('http://127.0.0.1:3000')  );

=cut
