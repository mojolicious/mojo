package Mojo::Message::Request;
use Mojo::Base 'Mojo::Message';

use Mojo::Cookie::Request;
use Mojo::Parameters;
use Mojo::Util qw/b64_encode b64_decode get_line/;
use Mojo::URL;

has env => sub { {} };
has method => 'GET';
has url => sub { Mojo::URL->new };

my $START_LINE_RE = qr|
  ^\s*
  ([a-zA-Z]+)                                                   # Method
  \s+
  ([0-9a-zA-Z\-\.\_\~\:/\?\#\[\]\@\!\$\&\'\(\)\*\+\,\;\=\%]+)   # Path
  (?:\s+HTTP/(\d+\.\d+))?                                       # Version
  $
|x;
my $HOST_RE = qr/^([^\:]*)\:?(.*)$/;

sub clone {
  my $self = shift;

  # Dynamic requests cannot be cloned
  return unless my $content = $self->content->clone;
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

  # Basic authentication
  if ((my $u = $url->userinfo) && !$headers->authorization) {
    $headers->authorization('Basic ' . b64_encode($u, ''));
  }

  # Basic proxy authentication
  if (my $proxy = $self->proxy) {
    if ((my $u = $proxy->userinfo) && !$headers->proxy_authorization) {
      $headers->proxy_authorization('Basic ' . b64_encode($u, ''));
    }
  }

  return $self;
}

sub is_secure {
  my $url = shift->url;
  return ($url->scheme || $url->base->scheme || '') eq 'https';
}

sub is_xhr {
  (shift->headers->header('X-Requested-With') || '') =~ /XMLHttpRequest/i;
}

sub param {
  my $self = shift;
  return ($self->{params} ||= $self->params)->param(@_);
}

sub params {
  my $self   = shift;
  my $params = Mojo::Parameters->new;
  return $params->merge($self->body_params, $self->query_params);
}

sub parse {
  my $self = shift;

  # CGI like environment
  my $env;
  if   (@_ > 1) { $env = {@_} }
  else          { $env = $_[0] if ref $_[0] eq 'HASH' }

  # Parse CGI like environment
  my $chunk;
  if ($env) { $self->_parse_env($env) }

  # Parse chunk
  else { $chunk = shift }

  # Pass through
  $self->SUPER::parse($chunk);

  # Fix things we only know after parsing headers
  if (!$self->{state} || $self->{state} ne 'headers') {

    # Base URL
    my $base = $self->url->base;
    $base->scheme('http') unless $base->scheme;
    my $headers = $self->headers;
    if (!$base->authority && (my $host = $headers->host)) {
      $base->authority($host);
    }

    # Basic authentication
    if (my $auth = $headers->authorization) {
      if (my $userinfo = $self->_parse_basic_auth($auth)) {
        $base->userinfo($userinfo);
      }
    }

    # Basic proxy authentication
    if (my $auth = $headers->proxy_authorization) {
      if (my $userinfo = $self->_parse_basic_auth($auth)) {
        $self->proxy(Mojo::URL->new->userinfo($userinfo));
      }
    }

    # "X-Forwarded-HTTPS"
    $base->scheme('https')
      if $ENV{MOJO_REVERSE_PROXY} && $headers->header('X-Forwarded-HTTPS');
  }

  return $self;
}

sub proxy {
  my ($self, $url) = @_;

  # Get
  return $self->{proxy} unless $url;

  # Mojo::URL object
  if (ref $url) { $self->{proxy} = $url }

  # String
  elsif ($url) { $self->{proxy} = Mojo::URL->new($url) }

  return $self;
}

sub query_params { shift->url->query }

sub _build_start_line {
  my $self = shift;

  # Path
  my $url   = $self->url;
  my $path  = $url->path->to_string;
  my $query = $url->query->to_string;
  $path .= "?$query" if $query;
  $path = "/$path" unless $path =~ m#^/#;

  # CONNECT
  my $method = uc $self->method;
  if ($method eq 'CONNECT') {
    my $host = $url->host;
    my $port = $url->port || ($url->scheme eq 'https' ? '443' : '80');
    $path = "$host:$port";
  }

  # Proxy
  elsif ($self->proxy) {
    my $clone = $url = $url->clone;
    $clone->userinfo(undef);
    $path = $clone
      unless lc($self->headers->upgrade || '') eq 'websocket'
        || ($url->scheme || '') eq 'https';
  }

  # HTTP 0.9
  my $version = $self->version;
  return "$method $path\x0d\x0a" if $version eq '0.9';

  # HTTP 1.0 and above
  return "$method $path HTTP/$version\x0d\x0a";
}

sub _parse_basic_auth {
  my ($self, $header) = @_;
  return unless $header =~ /Basic (.+)$/;
  return b64_decode $1;
}

sub _parse_env {
  my ($self, $env) = @_;
  $env ||= \%ENV;

  # Make environment accessible
  $self->env($env);

  # Extract headers
  my $headers = $self->headers;
  my $url     = $self->url;
  my $base    = $url->base;
  for my $name (keys %$env) {
    next unless $name =~ /^HTTP_/i;
    my $value = $env->{$name};
    $name =~ s/^HTTP_//i;
    $name =~ s/_/-/g;
    $headers->header($name, $value);

    # Host/Port
    if ($name eq 'HOST') {
      my $host = $value;
      my $port;
      ($host, $port) = ($1, $2) if $host =~ $HOST_RE;
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
  if (($env->{SERVER_PROTOCOL} || '') =~ m#^([^/]+)/([^/]+)$#) {
    $base->scheme($1);
    $self->version($2);
  }

  # HTTPS
  $base->scheme('https') if $env->{HTTPS};

  # Path
  my $path = $url->path;
  if   (my $value = $env->{PATH_INFO}) { $path->parse($value) }
  else                                 { $path->parse('') }

  # Base path
  if (my $value = $env->{SCRIPT_NAME}) {

    # Make sure there is a trailing slash (important for merging)
    $base->path->parse($value =~ m#/$# ? $value : "$value/");

    # Remove SCRIPT_NAME prefix if necessary
    my $buffer = $path->to_string;
    $value  =~ s|^/||;
    $value  =~ s|/$||;
    $buffer =~ s|^/?$value/?||;
    $buffer =~ s|^/||;
    $path->parse($buffer);
  }

  # There won't be a start line or headers
  $self->{state} = 'body';
}

# "Bart, with $10,000, we'd be millionaires!
#  We could buy all kinds of useful things like...love!"
sub _parse_start_line {
  my $self = shift;

  # Ignore any leading empty lines
  my $line = get_line \$self->{buffer};
  $line = get_line \$self->{buffer}
    while ((defined $line) && ($line =~ m/^\s*$/));
  return unless defined $line;

  # We have a (hopefully) full request line
  return $self->error('Bad request start line.', 400)
    unless $line =~ $START_LINE_RE;
  $self->method($1);
  my $url = $self->url;
  $1 eq 'CONNECT' ? $url->authority($2) : $url->parse($2);

  # HTTP 0.9 is identified by the missing version
  $self->{state} = 'content';
  return $self->version($3) if defined $3;
  $self->version('0.9');
  $self->{state}  = 'finished';
  $self->{buffer} = '';
}

1;
__END__

=head1 NAME

Mojo::Message::Request - HTTP 1.1 request container

=head1 SYNOPSIS

  use Mojo::Message::Request;

  # Parse
  my $req = Mojo::Message::Request->new;
  $req->parse("GET /foo HTTP/1.0\x0a\x0d");
  $req->parse("Content-Length: 12\x0a\x0d\x0a\x0d");
  $req->parse("Content-Type: text/plain\x0a\x0d\x0a\x0d");
  $req->parse('Hello World!');
  say $req->body;

  # Build
  my $req = Mojo::Message::Request->new;
  $req->url->parse('http://127.0.0.1/foo/bar');
  $req->method('GET');
  say $req->to_string;

=head1 DESCRIPTION

L<Mojo::Message::Request> is a container for HTTP 1.1 requests as described
in RFC 2616.

=head1 EVENTS

L<Mojo::Message::Request> inherits all events from L<Mojo::Message>.

=head1 ATTRIBUTES

L<Mojo::Message::Request> inherits all attributes from L<Mojo::Message> and
implements the following new ones.

=head2 C<env>

  my $env = $req->env;
  $req    = $req->env({});

Direct access to the C<CGI> or C<PSGI> environment hash if available.

  # Check CGI version
  my $version = $req->env->{GATEWAY_INTERFACE};

  # Check PSGI version
  my $version = $req->env->{'psgi.version'};

=head2 C<method>

  my $method = $req->method;
  $req       = $req->method('GET');

HTTP request method.

=head2 C<url>

  my $url = $req->url;
  $req    = $req->url(Mojo::URL->new);

HTTP request URL, defaults to a L<Mojo::URL> object.

  my $foo = $req->url->query->to_hash->{foo};

=head1 METHODS

L<Mojo::Message::Request> inherits all methods from L<Mojo::Message> and
implements the following new ones.

=head2 C<clone>

  my $clone = $req->clone;

Clone request if possible, otherwise return C<undef>.

=head2 C<cookies>

  my $cookies = $req->cookies;
  $req        = $req->cookies(Mojo::Cookie::Request->new);
  $req        = $req->cookies({name => 'foo', value => 'bar'});

Access request cookies, usually L<Mojo::Cookie::Request> objects.

  say $req->cookies->[1]->value;

=head2 C<fix_headers>

  $req = $req->fix_headers;

Make sure message has all required headers for the current HTTP version.

=head2 C<is_secure>

  my $success = $req->is_secure;

Check if connection is secure.

=head2 C<is_xhr>

  my $success = $req->is_xhr;

Check C<X-Requested-With> header for C<XMLHttpRequest> value.

=head2 C<param>

  my @names = $req->param;
  my $foo   = $req->param('foo');
  my @foo   = $req->param('foo');

Access C<GET> and C<POST> parameters.

=head2 C<params>

  my $params = $req->params;

All C<GET> and C<POST> parameters, usually a L<Mojo::Parameters> object.

  say $req->params->param('foo');

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

=head2 C<query_params>

  my $params = $req->query_params;

All C<GET> parameters, usually a L<Mojo::Parameters> object.

  say $req->query_params->to_hash->{'foo'};

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
