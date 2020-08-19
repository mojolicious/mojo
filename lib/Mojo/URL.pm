package Mojo::URL;
use Mojo::Base -base;
use overload bool => sub {1}, '""' => sub { shift->to_string }, fallback => 1;

use Mojo::Parameters;
use Mojo::Path;
use Mojo::Util qw(decode encode punycode_decode punycode_encode url_escape url_unescape);

has base => sub { Mojo::URL->new };
has [qw(fragment host port scheme userinfo)];

sub clone {
  my $self  = shift;
  my $clone = $self->new;
  @$clone{keys %$self} = values %$self;
  $clone->{$_} && ($clone->{$_} = $clone->{$_}->clone) for qw(base path query);
  return $clone;
}

sub host_port {
  my ($self, $host_port) = @_;

  if (defined $host_port) {
    $self->port($1) if $host_port =~ s/:(\d+)$//;
    my $host = url_unescape $host_port;
    return $host =~ /[^\x00-\x7f]/ ? $self->ihost($host) : $self->host($host);
  }

  return undef unless defined(my $host = $self->ihost);
  return $host unless defined(my $port = $self->port);
  return "$host:$port";
}

sub ihost {
  my $self = shift;

  # Decode
  return $self->host(join '.', map { /^xn--(.+)$/ ? punycode_decode $1 : $_ } split(/\./, shift, -1)) if @_;

  # Check if host needs to be encoded
  return undef unless defined(my $host = $self->host);
  return $host unless $host =~ /[^\x00-\x7f]/;

  # Encode
  return join '.', map { /[^\x00-\x7f]/ ? ('xn--' . punycode_encode $_) : $_ } split(/\./, $host, -1);
}

sub is_abs { !!shift->scheme }

sub new { @_ > 1 ? shift->SUPER::new->parse(@_) : shift->SUPER::new }

sub parse {
  my ($self, $url) = @_;

  # Official regex from RFC 3986
  $url =~ m!^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?!;
  $self->scheme($2)                         if defined $2;
  $self->path($5)                           if defined $5;
  $self->query($7)                          if defined $7;
  $self->fragment(_decode(url_unescape $9)) if defined $9;
  if (defined(my $auth = $4)) {
    $self->userinfo(_decode(url_unescape $1)) if $auth =~ s/^([^\@]+)\@//;
    $self->host_port($auth);
  }

  return $self;
}

sub password { (shift->userinfo // '') =~ /:(.*)$/ ? $1 : undef }

sub path {
  my $self = shift;

  # Old path
  $self->{path} ||= Mojo::Path->new;
  return $self->{path} unless @_;

  # New path
  $self->{path} = ref $_[0] ? $_[0] : $self->{path}->merge($_[0]);

  return $self;
}

sub path_query {
  my ($self, $pq) = @_;

  if (defined $pq) {
    return $self unless $pq =~ /^([^?#]*)(?:\?([^#]*))?/;
    return defined $2 ? $self->path($1)->query($2) : $self->path($1);
  }

  my $query = $self->query->to_string;
  return $self->path->to_string . (length $query ? "?$query" : '');
}

sub protocol { lc(shift->scheme // '') }

sub query {
  my $self = shift;

  # Old parameters
  my $q = $self->{query} ||= Mojo::Parameters->new;
  return $q unless @_;

  # Replace with list
  if (@_ > 1) { $q->pairs([])->parse(@_) }

  # Merge with hash
  elsif (ref $_[0] eq 'HASH') { $q->merge(%{$_[0]}) }

  # Append array
  elsif (ref $_[0] eq 'ARRAY') { $q->append(@{$_[0]}) }

  # New parameters
  else { $self->{query} = ref $_[0] ? $_[0] : $q->parse($_[0]) }

  return $self;
}

sub to_abs {
  my $self = shift;

  my $abs = $self->clone;
  return $abs if $abs->is_abs;

  # Scheme
  my $base = shift || $abs->base;
  $abs->base($base)->scheme($base->scheme);

  # Authority
  return $abs if $abs->host;
  $abs->userinfo($base->userinfo)->host($base->host)->port($base->port);

  # Absolute path
  my $path = $abs->path;
  return $abs if $path->leading_slash;

  # Inherit path
  if (!@{$path->parts}) {
    $abs->path($base->path->clone->canonicalize);

    # Query
    $abs->query($base->query->clone) unless length $abs->query->to_string;
  }

  # Merge paths
  else { $abs->path($base->path->clone->merge($path)->canonicalize) }

  return $abs;
}

sub to_string        { shift->_string(0) }
sub to_unsafe_string { shift->_string(1) }

sub username { (shift->userinfo // '') =~ /^([^:]+)/ ? $1 : undef }

sub _decode { decode('UTF-8', $_[0]) // $_[0] }

sub _encode { url_escape encode('UTF-8', $_[0]), $_[1] }

sub _string {
  my ($self, $unsafe) = @_;

  # Scheme
  my $url = '';
  if (my $proto = $self->protocol) { $url .= "$proto:" }

  # Authority
  my $auth = $self->host_port;
  $auth = _encode($auth, '^A-Za-z0-9\-._~!$&\'()*+,;=:\[\]') if defined $auth;
  if ($unsafe && defined(my $info = $self->userinfo)) {
    $auth = _encode($info, '^A-Za-z0-9\-._~!$&\'()*+,;=:') . '@' . $auth;
  }
  $url .= "//$auth" if defined $auth;

  # Path and query
  my $path = $self->path_query;
  $url .= !$auth || !length $path || $path =~ m!^[/?]! ? $path : "/$path";

  # Fragment
  return $url unless defined(my $fragment = $self->fragment);
  return $url . '#' . _encode($fragment, '^A-Za-z0-9\-._~!$&\'()*+,;=:@/?');
}

1;

=encoding utf8

=head1 NAME

Mojo::URL - Uniform Resource Locator

=head1 SYNOPSIS

  use Mojo::URL;

  # Parse
  my $url = Mojo::URL->new('http://sri:foo@example.com:3000/foo?foo=bar#23');
  say $url->scheme;
  say $url->userinfo;
  say $url->host;
  say $url->port;
  say $url->path;
  say $url->query;
  say $url->fragment;

  # Build
  my $url = Mojo::URL->new;
  $url->scheme('http');
  $url->host('example.com');
  $url->port(3000);
  $url->path('/foo/bar');
  $url->query(foo => 'bar');
  $url->fragment(23);
  say "$url";

=head1 DESCRIPTION

L<Mojo::URL> implements a subset of L<RFC 3986|https://tools.ietf.org/html/rfc3986>, L<RFC
3987|https://tools.ietf.org/html/rfc3987> and the L<URL Living Standard|https://url.spec.whatwg.org> for Uniform
Resource Locators with support for IDNA and IRIs.

=head1 ATTRIBUTES

L<Mojo::URL> implements the following attributes.

=head2 base

  my $base = $url->base;
  $url     = $url->base(Mojo::URL->new);

Base of this URL, defaults to a L<Mojo::URL> object.

  "http://example.com/a/b?c"
  Mojo::URL->new("/a/b?c")->base(Mojo::URL->new("http://example.com"))->to_abs;

=head2 fragment

  my $fragment = $url->fragment;
  $url         = $url->fragment('♥mojolicious♥');

Fragment part of this URL.

  # "yada"
  Mojo::URL->new('http://example.com/foo?bar=baz#yada')->fragment;

=head2 host

  my $host = $url->host;
  $url     = $url->host('127.0.0.1');

Host part of this URL.

  # "example.com"
  Mojo::URL->new('http://sri:t3st@example.com:8080/foo')->host;

=head2 port

  my $port = $url->port;
  $url     = $url->port(8080);

Port part of this URL.

  # "8080"
  Mojo::URL->new('http://sri:t3st@example.com:8080/foo')->port;

=head2 scheme

  my $scheme = $url->scheme;
  $url       = $url->scheme('http');

Scheme part of this URL.

  # "http"
  Mojo::URL->new('http://example.com/foo')->scheme;

=head2 userinfo

  my $info = $url->userinfo;
  $url     = $url->userinfo('root:♥');

Userinfo part of this URL.

  # "sri:t3st"
  Mojo::URL->new('https://sri:t3st@example.com/foo')->userinfo;

=head1 METHODS

L<Mojo::URL> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 clone

  my $url2 = $url->clone;

Return a new L<Mojo::URL> object cloned from this URL.

=head2 host_port

  my $host_port = $url->host_port;
  $url          = $url->host_port('example.com:8080');

Normalized version of L</"host"> and L</"port">.

  # "xn--n3h.net:8080"
  Mojo::URL->new('http://☃.net:8080/test')->host_port;

  # "example.com"
  Mojo::URL->new('http://example.com/test')->host_port;

=head2 ihost

  my $ihost = $url->ihost;
  $url      = $url->ihost('xn--bcher-kva.ch');

Host part of this URL in punycode format.

  # "xn--n3h.net"
  Mojo::URL->new('http://☃.net')->ihost;

  # "example.com"
  Mojo::URL->new('http://example.com')->ihost;

=head2 is_abs

  my $bool = $url->is_abs;

Check if URL is absolute.

  # True
  Mojo::URL->new('http://example.com')->is_abs;
  Mojo::URL->new('http://example.com/test/index.html')->is_abs;

  # False
  Mojo::URL->new('test/index.html')->is_abs;
  Mojo::URL->new('/test/index.html')->is_abs;
  Mojo::URL->new('//example.com/test/index.html')->is_abs;

=head2 new

  my $url = Mojo::URL->new;
  my $url = Mojo::URL->new('http://127.0.0.1:3000/foo?f=b&baz=2#foo');

Construct a new L<Mojo::URL> object and L</"parse"> URL if necessary.

=head2 parse

  $url = $url->parse('http://127.0.0.1:3000/foo/bar?fo=o&baz=23#foo');

Parse relative or absolute URL.

  # "/test/123"
  $url->parse('/test/123?foo=bar')->path;

  # "example.com"
  $url->parse('http://example.com/test/123?foo=bar')->host;

  # "sri@example.com"
  $url->parse('mailto:sri@example.com')->path;

=head2 password

  my $password = $url->password;

Password part of L</"userinfo">.

  # "s3cret"
  Mojo::URL->new('http://isabel:s3cret@mojolicious.org')->password;

  # "s:3:c:r:e:t"
  Mojo::URL->new('http://isabel:s:3:c:r:e:t@mojolicious.org')->password;

=head2 path

  my $path = $url->path;
  $url     = $url->path('foo/bar');
  $url     = $url->path('/foo/bar');
  $url     = $url->path(Mojo::Path->new);

Path part of this URL, relative paths will be merged with L<Mojo::Path/"merge">, defaults to a L<Mojo::Path> object.

  # "test"
  Mojo::URL->new('http://example.com/test/Mojo')->path->parts->[0];

  # "/test/DOM/HTML"
  Mojo::URL->new('http://example.com/test/Mojo')->path->merge('DOM/HTML');

  # "http://example.com/DOM/HTML"
  Mojo::URL->new('http://example.com/test/Mojo')->path('/DOM/HTML');

  # "http://example.com/test/DOM/HTML"
  Mojo::URL->new('http://example.com/test/Mojo')->path('DOM/HTML');

  # "http://example.com/test/Mojo/DOM/HTML"
  Mojo::URL->new('http://example.com/test/Mojo/')->path('DOM/HTML');

=head2 path_query

  my $path_query = $url->path_query;
  $url           = $url->path_query('/foo/bar?a=1&b=2');

Normalized version of L</"path"> and L</"query">.

  # "/test?a=1&b=2"
  Mojo::URL->new('http://example.com/test?a=1&b=2')->path_query;

  # "/"
  Mojo::URL->new('http://example.com/')->path_query;

=head2 protocol

  my $proto = $url->protocol;

Normalized version of L</"scheme">.

  # "http"
  Mojo::URL->new('HtTp://example.com')->protocol;

=head2 query

  my $query = $url->query;
  $url      = $url->query({merge => 'to'});
  $url      = $url->query([append => 'with']);
  $url      = $url->query(replace => 'with');
  $url      = $url->query('a=1&b=2');
  $url      = $url->query(Mojo::Parameters->new);

Query part of this URL, key/value pairs in an array reference will be appended with L<Mojo::Parameters/"append">, and
key/value pairs in a hash reference merged with L<Mojo::Parameters/"merge">, defaults to a L<Mojo::Parameters> object.

  # "2"
  Mojo::URL->new('http://example.com?a=1&b=2')->query->param('b');

  # "a=2&b=2&c=3"
  Mojo::URL->new('http://example.com?a=1&b=2')->query->merge(a => 2, c => 3);

  # "http://example.com?a=2&c=3"
  Mojo::URL->new('http://example.com?a=1&b=2')->query(a => 2, c => 3);

  # "http://example.com?a=2&a=3"
  Mojo::URL->new('http://example.com?a=1&b=2')->query(a => [2, 3]);

  # "http://example.com?a=2&b=2&c=3"
  Mojo::URL->new('http://example.com?a=1&b=2')->query({a => 2, c => 3});

  # "http://example.com?b=2"
  Mojo::URL->new('http://example.com?a=1&b=2')->query({a => undef});

  # "http://example.com?a=1&b=2&a=2&c=3"
  Mojo::URL->new('http://example.com?a=1&b=2')->query([a => 2, c => 3]);

=head2 to_abs

  my $abs = $url->to_abs;
  my $abs = $url->to_abs(Mojo::URL->new('http://example.com/foo'));

Return a new L<Mojo::URL> object cloned from this relative URL and turn it into an absolute one using L</"base"> or
provided base URL.

  # "http://example.com/foo/baz.xml?test=123"
  Mojo::URL->new('baz.xml?test=123')
    ->to_abs(Mojo::URL->new('http://example.com/foo/bar.html'));

  # "http://example.com/baz.xml?test=123"
  Mojo::URL->new('/baz.xml?test=123')
    ->to_abs(Mojo::URL->new('http://example.com/foo/bar.html'));

  # "http://example.com/foo/baz.xml?test=123"
  Mojo::URL->new('//example.com/foo/baz.xml?test=123')
    ->to_abs(Mojo::URL->new('http://example.com/foo/bar.html'));

=head2 to_string

  my $str = $url->to_string;

Turn URL into a string. Note that L</"userinfo"> will not be included for security reasons.

  # "http://mojolicious.org"
  Mojo::URL->new->scheme('http')->host('mojolicious.org')->to_string;

  # "http://mojolicious.org"
  Mojo::URL->new('http://daniel:s3cret@mojolicious.org')->to_string;

=head2 to_unsafe_string

  my $str = $url->to_unsafe_string;

Same as L</"to_string">, but includes L</"userinfo">.

  # "http://daniel:s3cret@mojolicious.org"
  Mojo::URL->new('http://daniel:s3cret@mojolicious.org')->to_unsafe_string;

=head2 username

  my $username = $url->username;

Username part of L</"userinfo">.

  # "isabel"
  Mojo::URL->new('http://isabel:s3cret@mojolicious.org')->username;

=head1 OPERATORS

L<Mojo::URL> overloads the following operators.

=head2 bool

  my $bool = !!$url;

Always true.

=head2 stringify

  my $str = "$url";

Alias for L</"to_string">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
