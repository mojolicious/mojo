package Mojo::Message::Request;
use Mojo::Base 'Mojo::Message';

use Mojo::Cookie::Request;
use Mojo::Util qw(b64_encode b64_decode);
use Mojo::URL;

has env => sub { {} };
has method => 'GET';
has url => sub { Mojo::URL->new };
has 'reverse_proxy';

my $START_LINE_RE = qr/
  ^([a-zA-Z]+)                                              # Method
  \s+([0-9a-zA-Z!#\$\%&'()*+,\-.\/:;=?\@[\\\]^_`\{|\}~]+)   # URL
  \s+HTTP\/(\d\.\d)$                                        # Version
/x;

sub clone {
  my $self = shift;

  # Dynamic requests cannot be cloned
  return undef unless my $content = $self->content->clone;
  my $clone = $self->new(
    content => $content,
    method  => $self->method,
    url     => $self->url->clone,
    version => $self->version
  );
  $clone->{proxy} = $self->{proxy}->clone if $self->{proxy};

  return $clone;
}

sub cookies {
  my $self = shift;

  # Parse cookies
  my $headers = $self->headers;
  return [map { @{Mojo::Cookie::Request->parse($_)} } $headers->cookie]
    unless @_;

  # Add cookies
  my @cookies = $headers->cookie || ();
  for my $cookie (@_) {
    $cookie = Mojo::Cookie::Request->new($cookie) if ref $cookie eq 'HASH';
    push @cookies, $cookie;
  }
  $headers->cookie(join('; ', @cookies));

  return $self;
}

sub every_param { shift->params->every_param(@_) }

sub extract_start_line {
  my ($self, $bufref) = @_;

  # Ignore any leading empty lines
  return undef unless $$bufref =~ s/^\s*(.*?)\x0d?\x0a//;

  # We have a (hopefully) full request-line
  return !$self->error({message => 'Bad request start-line'})
    unless $1 =~ $START_LINE_RE;
  my $url = $self->method($1)->version($3)->url;
  return !!($1 eq 'CONNECT' ? $url->authority($2) : $url->parse($2));
}

sub fix_headers {
  my $self = shift;
  $self->{fix} ? return $self : $self->SUPER::fix_headers(@_);

  # Host
  my $url     = $self->url;
  my $headers = $self->headers;
  $headers->host($url->host_port) unless $headers->host;

  # Basic authentication
  if ((my $info = $url->userinfo) && !$headers->authorization) {
    $headers->authorization('Basic ' . b64_encode($info, ''));
  }

  # Basic proxy authentication
  return $self unless my $proxy = $self->proxy;
  return $self unless my $info  = $proxy->userinfo;
  $headers->proxy_authorization('Basic ' . b64_encode($info, ''))
    unless $headers->proxy_authorization;
  return $self;
}

sub get_start_line_chunk {
  my ($self, $offset) = @_;

  unless (defined $self->{start_buffer}) {

    # Path
    my $url  = $self->url;
    my $path = $url->path_query;
    $path = "/$path" unless $path =~ m!^/!;

    # CONNECT
    my $method = uc $self->method;
    if ($method eq 'CONNECT') {
      my $port = $url->port || ($url->protocol eq 'https' ? '443' : '80');
      $path = $url->ihost . ":$port";
    }

    # Proxy
    elsif ($self->proxy && $url->protocol ne 'https') {
      $path = $url->clone->userinfo(undef) unless $self->is_handshake;
    }

    $self->{start_buffer} = "$method $path HTTP/@{[$self->version]}\x0d\x0a";
  }

  $self->emit(progress => 'start_line', $offset);
  return substr $self->{start_buffer}, $offset, 131072;
}

sub is_handshake { lc($_[0]->headers->upgrade // '') eq 'websocket' }

sub is_secure {
  my $url = shift->url;
  return ($url->protocol || $url->base->protocol) eq 'https';
}

sub is_xhr {
  (shift->headers->header('X-Requested-With') // '') =~ /XMLHttpRequest/i;
}

sub param { shift->params->param(@_) }

sub params {
  my $self = shift;
  return $self->{params}
    ||= $self->body_params->clone->append($self->query_params);
}

sub parse {
  my $self = shift;

  # Parse CGI environment
  my $env = @_ > 1 ? {@_} : ref $_[0] eq 'HASH' ? $_[0] : undef;
  $self->env($env)->_parse_env($env) if $env;

  # Parse normal message
  my @args = $env ? () : @_;
  if (($self->{state} // '') ne 'cgi') { $self->SUPER::parse(@args) }

  # Parse CGI content
  else { $self->content($self->content->parse_body(@args))->SUPER::parse }

  # Check if we can fix things that require all headers
  return $self unless $self->is_finished;

  # Base URL
  my $base = $self->url->base;
  $base->scheme('http') unless $base->scheme;
  my $headers = $self->headers;
  if (!$base->host && (my $host = $headers->host)) { $base->authority($host) }

  # Basic authentication
  my $auth = _parse_basic_auth($headers->authorization);
  $base->userinfo($auth) if $auth;

  # Basic proxy authentication
  my $proxy_auth = _parse_basic_auth($headers->proxy_authorization);
  $self->proxy(Mojo::URL->new->userinfo($proxy_auth)) if $proxy_auth;

  # "X-Forwarded-Proto"
  $base->scheme('https')
    if $self->reverse_proxy
    && ($headers->header('X-Forwarded-Proto') // '') eq 'https';

  return $self;
}

sub proxy {
  my $self = shift;
  return $self->{proxy} unless @_;
  $self->{proxy} = !$_[0] || ref $_[0] ? shift : Mojo::URL->new(shift);
  return $self;
}

sub query_params { shift->url->query }

sub _parse_basic_auth {
  return undef unless my $header = shift;
  return $header =~ /Basic (.+)$/ ? b64_decode($1) : undef;
}

sub _parse_env {
  my ($self, $env) = @_;

  # Extract headers
  my $headers = $self->headers;
  my $url     = $self->url;
  my $base    = $url->base;
  for my $name (keys %$env) {
    my $value = $env->{$name};
    next unless $name =~ s/^HTTP_//i;
    $name =~ y/_/-/;
    $headers->header($name => $value);

    # Host/Port
    if ($name eq 'HOST') {
      my ($host, $port) = ($value, undef);
      ($host, $port) = ($1, $2) if $host =~ /^([^:]*):?(.*)$/;
      $base->host($host)->port($port);
    }
  }

  # Content-Type is a special case on some servers
  $headers->content_type($env->{CONTENT_TYPE}) if $env->{CONTENT_TYPE};

  # Content-Length is a special case on some servers
  $headers->content_length($env->{CONTENT_LENGTH}) if $env->{CONTENT_LENGTH};

  # Query
  $url->query->parse($env->{QUERY_STRING}) if $env->{QUERY_STRING};

  # Method
  $self->method($env->{REQUEST_METHOD}) if $env->{REQUEST_METHOD};

  # Scheme/Version
  $base->scheme($1) and $self->version($2)
    if ($env->{SERVER_PROTOCOL} // '') =~ m!^([^/]+)/([^/]+)$!;

  # HTTPS
  $base->scheme('https') if uc($env->{HTTPS} // '') eq 'ON';

  # Path
  my $path = $url->path->parse($env->{PATH_INFO} ? $env->{PATH_INFO} : '');

  # Base path
  if (my $value = $env->{SCRIPT_NAME}) {

    # Make sure there is a trailing slash (important for merging)
    $base->path->parse($value =~ m!/$! ? $value : "$value/");

    # Remove SCRIPT_NAME prefix if necessary
    my $buffer = $path->to_string;
    $value =~ s!^/|/$!!g;
    $buffer =~ s!^/?\Q$value\E/?!!;
    $buffer =~ s!^/!!;
    $path->parse($buffer);
  }

  # Bypass normal message parser
  $self->{state} = 'cgi';
}

1;

=encoding utf8

=head1 NAME

Mojo::Message::Request - HTTP request

=head1 SYNOPSIS

  use Mojo::Message::Request;

  # Parse
  my $req = Mojo::Message::Request->new;
  $req->parse("GET /foo HTTP/1.0\x0d\x0a");
  $req->parse("Content-Length: 12\x0d\x0a");
  $req->parse("Content-Type: text/plain\x0d\x0a\x0d\x0a");
  $req->parse('Hello World!');
  say $req->method;
  say $req->headers->content_type;
  say $req->body;

  # Build
  my $req = Mojo::Message::Request->new;
  $req->url->parse('http://127.0.0.1/foo/bar');
  $req->method('GET');
  say $req->to_string;

=head1 DESCRIPTION

L<Mojo::Message::Request> is a container for HTTP requests based on
L<RFC 7230|http://tools.ietf.org/html/rfc7230>,
L<RFC 7231|http://tools.ietf.org/html/rfc7231>,
L<RFC 7235|http://tools.ietf.org/html/rfc7235> and
L<RFC 2817|http://tools.ietf.org/html/rfc2817>.

=head1 EVENTS

L<Mojo::Message::Request> inherits all events from L<Mojo::Message>.

=head1 ATTRIBUTES

L<Mojo::Message::Request> inherits all attributes from L<Mojo::Message> and
implements the following new ones.

=head2 env

  my $env = $req->env;
  $req    = $req->env({});

Direct access to the C<CGI> or C<PSGI> environment hash if available.

  # Check CGI version
  my $version = $req->env->{GATEWAY_INTERFACE};

  # Check PSGI version
  my $version = $req->env->{'psgi.version'};

=head2 method

  my $method = $req->method;
  $req       = $req->method('POST');

HTTP request method, defaults to C<GET>.

=head2 url

  my $url = $req->url;
  $req    = $req->url(Mojo::URL->new);

HTTP request URL, defaults to a L<Mojo::URL> object.

  # Get request information
  say $req->url->to_abs->userinfo;
  say $req->url->to_abs->host;
  say $req->url->to_abs->path;

=head2 reverse_proxy

  my $bool = $req->reverse_proxy;
  $req     = $req->reverse_proxy($bool);

Request has been performed through a reverse proxy.

=head1 METHODS

L<Mojo::Message::Request> inherits all methods from L<Mojo::Message> and
implements the following new ones.

=head2 clone

  my $clone = $req->clone;

Clone request if possible, otherwise return C<undef>.

=head2 cookies

  my $cookies = $req->cookies;
  $req        = $req->cookies(Mojo::Cookie::Request->new);
  $req        = $req->cookies({name => 'foo', value => 'bar'});

Access request cookies, usually L<Mojo::Cookie::Request> objects.

=head2 every_param

  my $values = $req->every_param('foo');

Similar to L</"param">, but returns all values sharing the same name as an
array reference.

  # Get first value
  say $req->every_param('foo')->[0];

=head2 extract_start_line

  my $bool = $req->extract_start_line(\$str);

Extract request-line from string.

=head2 fix_headers

  $req = $req->fix_headers;

Make sure request has all required headers.

=head2 get_start_line_chunk

  my $bytes = $req->get_start_line_chunk($offset);

Get a chunk of request-line data starting from a specific position.

=head2 is_handshake

  my $bool = $req->is_handshake;

Check C<Upgrade> header for C<websocket> value.

=head2 is_secure

  my $bool = $req->is_secure;

Check if connection is secure.

=head2 is_xhr

  my $bool = $req->is_xhr;

Check C<X-Requested-With> header for C<XMLHttpRequest> value.

=head2 param

  my @names       = $req->param;
  my $value       = $req->param('foo');
  my ($foo, $bar) = $req->param(['foo', 'bar']);

Access C<GET> and C<POST> parameters extracted from the query string and
C<application/x-www-form-urlencoded> or C<multipart/form-data> message body.
If there are multiple values sharing the same name, and you want to access
more than just the last one, you can use L</"every_param">. Note that this
method caches all data, so it should not be called before the entire request
body has been received. Parts of the request body need to be loaded into
memory to parse C<POST> parameters, so you have to make sure it is not
excessively large, there's a 16MB limit by default.

=head2 params

  my $params = $req->params;

All C<GET> and C<POST> parameters extracted from the query string and
C<application/x-www-form-urlencoded> or C<multipart/form-data> message body,
usually a L<Mojo::Parameters> object. Note that this method caches all data,
so it should not be called before the entire request body has been received.
Parts of the request body need to be loaded into memory to parse C<POST>
parameters, so you have to make sure it is not excessively large, there's a
16MB limit by default.

  # Get parameter names and values
  my $hash = $req->params->to_hash;

=head2 parse

  $req = $req->parse('GET /foo/bar HTTP/1.1');
  $req = $req->parse(REQUEST_METHOD => 'GET');
  $req = $req->parse({REQUEST_METHOD => 'GET'});

Parse HTTP request chunks or environment hash.

=head2 proxy

  my $proxy = $req->proxy;
  $req      = $req->proxy('http://foo:bar@127.0.0.1:3000');
  $req      = $req->proxy(Mojo::URL->new('http://127.0.0.1:3000'));

Proxy URL for request.

  # Disable proxy
  $req->proxy(0);

=head2 query_params

  my $params = $req->query_params;

All C<GET> parameters, usually a L<Mojo::Parameters> object.

  # Turn GET parameters to hash and extract value
  say $req->query_params->to_hash->{foo};

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
