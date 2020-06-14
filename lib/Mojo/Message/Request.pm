package Mojo::Message::Request;
use Mojo::Base 'Mojo::Message';

use Digest::SHA qw(sha1_base64);
use Mojo::Cookie::Request;
use Mojo::Util qw(b64_encode b64_decode sha1_sum);
use Mojo::URL;

my ($SEED, $COUNTER) = ($$ . time . rand, int rand 0xffffff);

has env    => sub { {} };
has method => 'GET';
has [qw(proxy reverse_proxy)];
has request_id => sub {
  my $b64 = substr(sha1_base64($SEED . ($COUNTER = ($COUNTER + 1) % 0xffffff)), 0, 8);
  $b64 =~ tr!+/!-_!;
  return $b64;
};
has url       => sub { Mojo::URL->new };
has via_proxy => 1;

sub clone {
  my $self = shift;

  # Dynamic requests cannot be cloned
  return undef unless my $content = $self->content->clone;
  my $clone
    = $self->new(content => $content, method => $self->method, url => $self->url->clone, version => $self->version);
  $clone->{proxy} = $self->{proxy}->clone if $self->{proxy};

  return $clone;
}

sub cookies {
  my $self = shift;

  # Parse cookies
  my $headers = $self->headers;
  return [map { @{Mojo::Cookie::Request->parse($_)} } $headers->cookie] unless @_;

  # Add cookies
  my @cookies = map { ref $_ eq 'HASH' ? Mojo::Cookie::Request->new($_) : $_ } $headers->cookie || (), @_;
  $headers->cookie(join '; ', @cookies);

  return $self;
}

sub every_param { shift->params->every_param(@_) }

sub extract_start_line {
  my ($self, $bufref) = @_;

  # Ignore any leading empty lines
  return undef unless $$bufref =~ s/^\s*(.*?)\x0d?\x0a//;

  # We have a (hopefully) full request-line
  return !$self->error({message => 'Bad request start-line'}) unless $1 =~ /^(\S+)\s+(\S+)\s+HTTP\/(\d\.\d)$/;
  my $url    = $self->method($1)->version($3)->url;
  my $target = $2;
  return !!$url->host_port($target)              if $1 eq 'CONNECT';
  return !!$url->parse($target)->fragment(undef) if $target =~ /^[^:\/?#]+:/;
  return !!$url->path_query($target);
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
  return $self unless (my $proxy = $self->proxy) && $self->via_proxy;
  return $self unless my $info = $proxy->userinfo;
  $headers->proxy_authorization('Basic ' . b64_encode($info, '')) unless $headers->proxy_authorization;
  return $self;
}

sub get_start_line_chunk {
  my ($self, $offset) = @_;
  $self->_start_line->emit(progress => 'start_line', $offset);
  return substr $self->{start_buffer}, $offset, 131072;
}

sub is_handshake { lc($_[0]->headers->upgrade // '') eq 'websocket' }

sub is_secure {
  my $url = shift->url;
  return ($url->protocol || $url->base->protocol) eq 'https';
}

sub is_xhr { (shift->headers->header('X-Requested-With') // '') =~ /XMLHttpRequest/i }

sub param { shift->params->param(@_) }

sub params { $_[0]->{params} ||= $_[0]->body_params->clone->append($_[0]->query_params) }

sub parse {
  my ($self, $env, $chunk) = (shift, ref $_[0] ? (shift, '') : (undef, shift));

  # Parse CGI environment
  $self->env($env)->_parse_env($env) if $env;

  # Parse normal message
  if (($self->{state} // '') ne 'cgi') { $self->SUPER::parse($chunk) }

  # Parse CGI content
  else { $self->content($self->content->parse_body($chunk))->SUPER::parse('') }

  # Check if we can fix things that require all headers
  return $self unless $self->is_finished;

  # Base URL
  my $base = $self->url->base;
  $base->scheme('http') unless $base->scheme;
  my $headers = $self->headers;
  if (!$base->host && (my $host = $headers->host)) { $base->host_port($host) }

  # Basic authentication
  if (my $basic = _basic($headers->authorization)) { $base->userinfo($basic) }

  # Basic proxy authentication
  my $basic = _basic($headers->proxy_authorization);
  $self->proxy(Mojo::URL->new->userinfo($basic)) if $basic;

  # "X-Forwarded-Proto"
  $base->scheme('https') if $self->reverse_proxy && ($headers->header('X-Forwarded-Proto') // '') eq 'https';

  return $self;
}

sub query_params { shift->url->query }

sub start_line_size { length shift->_start_line->{start_buffer} }

sub _basic { $_[0] && $_[0] =~ /Basic (.+)$/ ? b64_decode $1 : undef }

sub _parse_env {
  my ($self, $env) = @_;

  # Bypass normal message parser
  $self->{state} = 'cgi';

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
    $value =~ s/:(\d+)$// ? $base->host($value)->port($1) : $base->host($value) if $name eq 'HOST';
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
  $base->scheme($1) and $self->version($2) if ($env->{SERVER_PROTOCOL} // '') =~ m!^([^/]+)/([^/]+)$!;

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
    $value  =~ s!^/|/$!!g;
    $buffer =~ s!^/?\Q$value\E/?!!;
    $buffer =~ s!^/!!;
    $path->parse($buffer);
  }
}

sub _start_line {
  my $self = shift;

  return $self if defined $self->{start_buffer};

  # Path
  my $url  = $self->url;
  my $path = $url->path_query;
  $path = "/$path" unless $path =~ m!^/!;

  # CONNECT
  my $method = uc $self->method;
  if ($method eq 'CONNECT') {
    my $port = $url->port // ($url->protocol eq 'https' ? '443' : '80');
    $path = $url->ihost . ":$port";
  }

  # Proxy
  elsif ($self->proxy && $self->via_proxy && $url->protocol ne 'https') {
    $path = $url->clone->userinfo(undef) unless $self->is_handshake;
  }

  $self->{start_buffer} = "$method $path HTTP/@{[$self->version]}\x0d\x0a";

  return $self;
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

L<Mojo::Message::Request> is a container for HTTP requests, based on L<RFC 7230|http://tools.ietf.org/html/rfc7230>,
L<RFC 7231|http://tools.ietf.org/html/rfc7231>, L<RFC 7235|http://tools.ietf.org/html/rfc7235> and L<RFC
2817|http://tools.ietf.org/html/rfc2817>.

=head1 EVENTS

L<Mojo::Message::Request> inherits all events from L<Mojo::Message>.

=head1 ATTRIBUTES

L<Mojo::Message::Request> inherits all attributes from L<Mojo::Message> and implements the following new ones.

=head2 env

  my $env = $req->env;
  $req    = $req->env({PATH_INFO => '/'});

Direct access to the C<CGI> or C<PSGI> environment hash if available.

  # Check CGI version
  my $version = $req->env->{GATEWAY_INTERFACE};

  # Check PSGI version
  my $version = $req->env->{'psgi.version'};

=head2 method

  my $method = $req->method;
  $req       = $req->method('POST');

HTTP request method, defaults to C<GET>.

=head2 proxy

  my $url = $req->proxy;
  $req    = $req->proxy(Mojo::URL->new('http://127.0.0.1:3000'));

Proxy URL for request.

=head2 reverse_proxy

  my $bool = $req->reverse_proxy;
  $req     = $req->reverse_proxy($bool);

Request has been performed through a reverse proxy.

=head2 request_id

  my $id = $req->request_id;
  $req   = $req->request_id('aee7d5d8');

Request ID, defaults to a reasonably unique value.

=head2 url

  my $url = $req->url;
  $req    = $req->url(Mojo::URL->new);

HTTP request URL, defaults to a L<Mojo::URL> object.

  # Get request information
  my $info = $req->url->to_abs->userinfo;
  my $host = $req->url->to_abs->host;
  my $path = $req->url->to_abs->path;

=head2 via_proxy

  my $bool = $req->via_proxy;
  $req     = $req->via_proxy($bool);

Request can be performed through a proxy server.

=head1 METHODS

L<Mojo::Message::Request> inherits all methods from L<Mojo::Message> and implements the following new ones.

=head2 clone

  my $clone = $req->clone;

Return a new L<Mojo::Message::Request> object cloned from this request if possible, otherwise return C<undef>.

=head2 cookies

  my $cookies = $req->cookies;
  $req        = $req->cookies(Mojo::Cookie::Request->new);
  $req        = $req->cookies({name => 'foo', value => 'bar'});

Access request cookies, usually L<Mojo::Cookie::Request> objects.

  # Names of all cookies
  say $_->name for @{$req->cookies};

=head2 every_param

  my $values = $req->every_param('foo');

Similar to L</"param">, but returns all values sharing the same name as an array reference.

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

Get a chunk of request-line data starting from a specific position. Note that this method finalizes the request.

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

  my $value = $req->param('foo');

Access C<GET> and C<POST> parameters extracted from the query string and C<application/x-www-form-urlencoded> or
C<multipart/form-data> message body. If there are multiple values sharing the same name, and you want to access more
than just the last one, you can use L</"every_param">. Note that this method caches all data, so it should not be
called before the entire request body has been received. Parts of the request body need to be loaded into memory to
parse C<POST> parameters, so you have to make sure it is not excessively large. There's a 16MiB limit for requests by
default.

=head2 params

  my $params = $req->params;

All C<GET> and C<POST> parameters extracted from the query string and C<application/x-www-form-urlencoded> or
C<multipart/form-data> message body, usually a L<Mojo::Parameters> object. Note that this method caches all data, so it
should not be called before the entire request body has been received. Parts of the request body need to be loaded into
memory to parse C<POST> parameters, so you have to make sure it is not excessively large. There's a 16MiB limit for
requests by default.

  # Get parameter names and values
  my $hash = $req->params->to_hash;

=head2 parse

  $req = $req->parse('GET /foo/bar HTTP/1.1');
  $req = $req->parse({PATH_INFO => '/'});

Parse HTTP request chunks or environment hash.

=head2 query_params

  my $params = $req->query_params;

All C<GET> parameters, usually a L<Mojo::Parameters> object.

  # Turn GET parameters to hash and extract value
  say $req->query_params->to_hash->{foo};

=head2 start_line_size

  my $size = $req->start_line_size;

Size of the request-line in bytes. Note that this method finalizes the request.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
