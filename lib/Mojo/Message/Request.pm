package Mojo::Message::Request;
use Mojo::Base 'Mojo::Message';

use Mojo::Cookie::Request;
use Mojo::Parameters;
use Mojo::Util qw/b64_encode b64_decode get_line/;
use Mojo::URL;

has env => sub { {} };
has method => 'GET';
has url => sub { Mojo::URL->new };

# Start line regex
my $START_LINE_RE = qr/
  ^\s*                                                         # Start
  ([a-zA-Z]+)                                                  # Method
  \s+                                                          # Whitespace
  (
  [0-9a-zA-Z\-\.\_\~\:\/\?\#\[\]\@\!\$\&\'\(\)\*\+\,\;\=\%]+   # Path
  )
  (?:\s+HTTP\/(\d+\.\d+))?                                     # Version
  $                                                            # End
/x;

# Host regex
my $HOST_RE = qr/^([^\:]*)\:?(.*)$/;

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
  my $url     = $self->url;
  my $headers = $self->headers;
  if ($self->at_least_version('1.1')) {
    my $host = $url->ihost;
    my $port = $url->port;
    $host .= ":$port" if $port;
    $headers->host($host) unless $headers->host;
  }

  # Basic authorization
  if ((my $u = $url->userinfo) && !$headers->authorization) {
    b64_encode $u, '';
    $headers->authorization("Basic $u");
  }

  # Basic proxy authorization
  if (my $proxy = $self->proxy) {
    if ((my $u = $proxy->userinfo) && !$headers->proxy_authorization) {
      b64_encode $u, '';
      $headers->proxy_authorization("Basic $u");
    }
  }

  return $self;
}

sub is_secure {
  my $self = shift;

  # Secure
  my $url = $self->url;
  my $scheme = $url->scheme || $url->base->scheme || '';
  return 1 if $scheme eq 'https';

  # Not secure
  return;
}

sub is_xhr {
  my $self = shift;
  return unless my $with = $self->headers->header('X-Requested-With');
  return 1 if $with =~ /XMLHttpRequest/i;
  return;
}

sub param {
  my $self = shift;
  $self->{_params} = $self->params unless $self->{_params};
  return $self->{_params}->param(@_);
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
  my $env;
  if   (exists $_[1]) { $env = {@_} }
  else                { $env = $_[0] if ref $_[0] eq 'HASH' }

  # Parse CGI like environment
  my $chunk;
  if ($env) { $self->_parse_env($env) }

  # Parse chunk
  else { $chunk = shift }

  # Pass through
  $self->SUPER::parse($chunk);

  # Fix things we only know after parsing headers
  if (!$self->{_state} || $self->{_state} ne 'headers') {

    # Base URL
    my $base = $self->url->base;
    $base->scheme('http') unless $base->scheme;
    my $headers = $self->headers;
    if (!$base->authority && (my $host = $headers->host)) {
      $base->authority($host);
    }

    # Basic authorization
    if (my $auth = $headers->authorization) {
      if (my $userinfo = $self->_parse_basic_auth($auth)) {
        $base->userinfo($userinfo);
      }
    }

    # Basic proxy authorization
    if (my $auth = $headers->proxy_authorization) {
      if (my $userinfo = $self->_parse_basic_auth($auth)) {
        $self->proxy(Mojo::URL->new->userinfo($userinfo));
      }
    }

    # Reverse proxy
    if ($ENV{MOJO_REVERSE_PROXY}) {

      # "X-Forwarded-Host"
      if (my $host = $headers->header('X-Forwarded-Host')) {
        if ($host =~ $HOST_RE) {
          $base->host($1);
          $base->port($2) if defined $2;
        }
      }

      # "X-Forwarded-HTTPS"
      if ($headers->header('X-Forwarded-HTTPS')) { $base->scheme('https') }
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

  # Path
  my $url   = $self->url;
  my $path  = $url->path->to_string;
  my $query = $url->query->to_string;
  $path .= "?$query" if $query;
  $path = "/$path" unless $path =~ /^\//;

  # Proxy
  if ($self->proxy) {
    my $clone = $url = $url->clone;
    $clone->userinfo(undef);
    $path = $clone;
  }

  # CONNECT
  my $method = uc $self->method;
  if ($method eq 'CONNECT') {
    my $host = $url->host;
    my $port = $url->port || ($url->scheme eq 'https' ? '443' : '80');
    $path = "$host:$port";
  }

  # Version
  my $version = $self->version;

  # HTTP 0.9
  return "$method $path\x0d\x0a" if $version eq '0.9';

  # HTTP 1.0 and above
  return "$method $path HTTP/$version\x0d\x0a";
}

sub _parse_basic_auth {
  my ($self, $header) = @_;
  return unless $header =~ /Basic (.+)$/;
  my $auth = $1;
  b64_decode $auth;
  return $auth;
}

sub _parse_env {
  my ($self, $env) = @_;
  $env ||= \%ENV;

  # Make environment accessible
  $self->env($env);

  my $headers = $self->headers;
  my $url     = $self->url;
  my $base    = $url->base;

  # Headers
  while (my ($name, $value) = each %$env) {

    # Header
    if ($name =~ s/^HTTP_//i) {
      $name =~ s/_/-/g;
      $headers->header($name, $value);

      # Host/Port
      if ($name eq 'HOST') {
        my $host = $value;
        my $port = undef;

        if ($host =~ $HOST_RE) {
          $host = $1;
          $port = $2;
        }

        $base->host($host);
        $base->port($port);
      }
    }
  }

  # Content-Type is a special case on some servers
  if (my $value = $env->{CONTENT_TYPE}) { $headers->content_type($value) }

  # Content-Length is a special case on some servers
  if (my $value = $env->{CONTENT_LENGTH}) {
    $headers->content_length($value);
  }

  # Path is a special case on some servers
  if (my $value = $env->{REQUEST_URI}) { $url->parse($value) }

  # Query
  if (my $value = $env->{QUERY_STRING}) { $url->query->parse($value) }

  # Method
  if (my $value = $env->{REQUEST_METHOD}) { $self->method($value) }

  # Scheme/Version
  if (my $value = $env->{SERVER_PROTOCOL}) {
    $value =~ /^([^\/]*)\/*(.*)$/;
    $base->scheme($1)  if $1;
    $self->version($2) if $2;
  }

  # HTTPS
  if ($env->{HTTPS}) { $base->scheme('https') }

  # Base path
  my $base_path = $base->path;
  if (my $value = $env->{SCRIPT_NAME}) {

    # Make sure there is a trailing slash (important for merging)
    $value .= '/' unless $value =~ /\/$/;

    $base_path->parse($value);
  }

  # Path
  my $path = $url->path;
  if   (my $value = $env->{PATH_INFO}) { $path->parse($value) }
  else                                 { $path->parse('') }

  # Path buffer
  my $base_buffer = $base_path->to_string;
  my $buffer      = $path->to_string;

  # Fix paths for broken CGI environments
  if (defined $buffer && defined $base_buffer && length $base_buffer) {

    # Remove SCRIPT_NAME prefix if it's there
    $base_buffer =~ s/^\///;
    $base_buffer =~ s/\/$//;
    $buffer      =~ s/^\/?$base_buffer\/?//;
    $buffer      =~ s/^\///;

    $path->parse($buffer);
  }

  # There won't be a start line or header when you parse environment
  # variables
  $self->{_state} = 'body';
}

# "Bart, with $10,000, we'd be millionaires!
#  We could buy all kinds of useful things like...love!"
sub _parse_start_line {
  my $self = shift;

  # Ignore any leading empty lines
  my $line = get_line $self->{_buffer};
  while ((defined $line) && ($line =~ m/^\s*$/)) {
    $line = get_line $self->{_buffer};
  }

  # We have a (hopefully) full request line
  if (defined $line) {
    if ($line =~ m/$START_LINE_RE/o) {
      $self->method($1);
      my $url = $self->url;
      $self->method eq 'CONNECT'
        ? $url->authority($2)
        : $url->parse($2);

      # HTTP 0.9 is identified by the missing version
      if (defined $3) {
        $self->version($3);
        $self->{_state} = 'content';
      }
      else {
        $self->version('0.9');
        $self->{_state} = 'done';

        # HTTP 0.9 has no headers or body and does not support
        # pipelining
        $self->{_buffer} = '';
      }
    }
    else { $self->error('Bad request start line.', 400) }
  }
}

1;
__END__

=head1 NAME

Mojo::Message::Request - HTTP 1.1 Request Container

=head1 SYNOPSIS

  use Mojo::Message::Request;

  my $req = Mojo::Message::Request->new;
  $req->url->parse('http://127.0.0.1/foo/bar');
  $req->method('GET');

  print "$req";

  $req->parse('GET /foo/bar HTTP/1.1');

=head1 DESCRIPTION

L<Mojo::Message::Request> is a container for HTTP 1.1 requests as described
in RFC 2616.

=head1 ATTRIBUTES

L<Mojo::Message::Request> inherits all attributes from L<Mojo::Message> and
implements the following new ones.

=head2 C<env>

  my $env = $req->env;
  $req    = $req->env({});

Direct access to the environment hash if available.

=head2 C<method>

  my $method = $req->method;
  $req       = $req->method('GET');

HTTP request method.

=head2 C<params>

  my $params = $req->params;

All C<GET> and C<POST> parameters, defaults to a L<Mojo::Parameters> object.

=head2 C<query_params>

  my $params = $req->query_params;

All C<GET> parameters, defaults to a L<Mojo::Parameters> object.

=head2 C<url>

  my $url = $req->url;
  $req    = $req->url(Mojo::URL->new);

HTTP request URL, defaults to a L<Mojo::URL> object.

=head1 METHODS

L<Mojo::Message::Request> inherits all methods from L<Mojo::Message> and
implements the following new ones.

=head2 C<cookies>

  my $cookies = $req->cookies;
  $req        = $req->cookies(Mojo::Cookie::Request->new);
  $req        = $req->cookies({name => 'foo', value => 'bar'});

Access request cookies.

=head2 C<fix_headers>

  $req = $req->fix_headers;

Make sure message has all required headers for the current HTTP version.

=head2 C<is_secure>

  my $secure = $req->is_secure;

Check if connection is secure.

=head2 C<is_xhr>

  my $xhr = $req->is_xhr;

Check C<X-Requested-With> header for C<XMLHttpRequest> value.

=head2 C<param>

  my $param = $req->param('foo');

Access C<GET> and C<POST> parameters, defaults to a L<Mojo::Parameters>
object.

=head2 C<parse>

  $req = $req->parse('GET /foo/bar HTTP/1.1');
  $req = $req->parse(REQUEST_METHOD => 'GET');
  $req = $req->parse({REQUEST_METHOD => 'GET'});

Parse HTTP request chunks or environment hash.

=head2 C<proxy>

  my $proxy = $req->proxy;
  $req      = $req->proxy('http://foo:bar@127.0.0.1:3000');
  $req      = $req->proxy(Mojo::URL->new('http://127.0.0.1:3000'));

Proxy URL for message.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
