package Mojo::URL;
use Mojo::Base -base;
use overload bool => sub {1}, '""' => sub { shift->to_string }, fallback => 1;

use Mojo::Parameters;
use Mojo::Path;
use Mojo::Util qw(punycode_decode punycode_encode url_escape url_unescape);

has base => sub { Mojo::URL->new };
has [qw(fragment host port scheme userinfo)];

sub authority {
  my $self = shift;

  # New authority
  if (@_) {
    return $self unless defined(my $authority = shift);

    # Userinfo
    $authority =~ s/^([^\@]+)\@// and $self->userinfo(url_unescape $1);

    # Port
    $authority =~ s/:(\d+)$// and $self->port($1);

    # Host
    my $host = url_unescape $authority;
    return $host =~ /[^\x00-\x7f]/ ? $self->ihost($host) : $self->host($host);
  }

  # Build authority
  return undef unless defined(my $authority = $self->host_port);
  return $authority unless my $info = $self->userinfo;
  return url_escape($info, '^A-Za-z0-9\-._~!$&\'()*+,;=:') . '@' . $authority;
}

sub host_port {
  my $self = shift;
  return undef unless defined(my $host = $self->ihost);
  return $host unless my $port = $self->port;
  return "$host:$port";
}

sub clone {
  my $self  = shift;
  my $clone = $self->new;
  @$clone{keys %$self} = values %$self;
  $clone->{$_} && ($clone->{$_} = $clone->{$_}->clone) for qw(base path query);
  return $clone;
}

sub ihost {
  my $self = shift;

  # Decode
  return $self->host(join '.',
    map { /^xn--(.+)$/ ? punycode_decode($_) : $_ } split /\./, shift)
    if @_;

  # Check if host needs to be encoded
  return undef unless defined(my $host = $self->host);
  return lc $host unless $host =~ /[^\x00-\x7f]/;

  # Encode
  return lc join '.',
    map { /[^\x00-\x7f]/ ? ('xn--' . punycode_encode $_) : $_ } split /\./,
    $host;
}

sub is_abs { !!shift->scheme }

sub new { @_ > 1 ? shift->SUPER::new->parse(@_) : shift->SUPER::new }

sub parse {
  my ($self, $url) = @_;

  # Official regex from RFC 3986
  $url =~ m!^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?!;
  return $self->scheme($2)->authority($4)->path($5)->query($7)->fragment($9);
}

sub path {
  my $self = shift;

  # Old path
  $self->{path} ||= Mojo::Path->new;
  return $self->{path} unless @_;

  # New path
  my $path = shift;
  $self->{path} = ref $path ? $path : $self->{path}->merge($path);

  return $self;
}

sub path_query {
  my $self  = shift;
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
  if (@_ > 1) { $q->params([])->parse(@_) }

  # Merge with array
  elsif (ref $_[0] eq 'ARRAY') {
    while (my $name = shift @{$_[0]}) {
      my $value = shift @{$_[0]};
      defined $value ? $q->param($name => $value) : $q->remove($name);
    }
  }

  # Append hash
  elsif (ref $_[0] eq 'HASH') { $q->append(%{$_[0]}) }

  # Replace with string
  else { $q->parse($_[0]) }

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
  return $abs if $abs->authority;
  $abs->authority($base->authority);

  # Absolute path
  my $path = $abs->path;
  return $abs if $path->leading_slash;

  # Inherit path
  my $base_path = $base->path;
  if (!@{$path->parts}) {
    $path
      = $abs->path($base_path->clone)->path->trailing_slash(0)->canonicalize;

    # Query
    return $abs if length $abs->query->to_string;
    $abs->query($base->query->clone);
  }

  # Merge paths
  else { $abs->path($base_path->clone->merge($path)->canonicalize) }

  return $abs;
}

sub to_string {
  my $self = shift;

  # Scheme
  my $url = '';
  if (my $proto = $self->protocol) { $url .= "$proto:" }

  # Authority
  my $authority = $self->authority;
  $url .= "//$authority" if defined $authority;

  # Path and query
  my $path = $self->path_query;
  $url .= !$authority || $path eq '' || $path =~ m!^[/?]! ? $path : "/$path";

  # Fragment
  return $url unless defined(my $fragment = $self->fragment);
  return $url . '#' . url_escape $fragment, '^A-Za-z0-9\-._~!$&\'()*+,;=%:@/?';
}

1;

=encoding utf8

=head1 NAME

Mojo::URL - Uniform Resource Locator

=head1 SYNOPSIS

  use Mojo::URL;

  # Parse
  my $url
    = Mojo::URL->new('http://sri:foobar@example.com:3000/foo/bar?foo=bar#23');
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
  $url->userinfo('sri:foobar');
  $url->host('example.com');
  $url->port(3000);
  $url->path('/foo/bar');
  $url->query->param(foo => 'bar');
  $url->fragment(23);
  say "$url";

=head1 DESCRIPTION

L<Mojo::URL> implements a subset of
L<RFC 3986|http://tools.ietf.org/html/rfc3986> and
L<RFC 3987|http://tools.ietf.org/html/rfc3987> for Uniform Resource Locators
with support for IDNA and IRIs.

=head1 ATTRIBUTES

L<Mojo::URL> implements the following attributes.

=head2 base

  my $base = $url->base;
  $url     = $url->base(Mojo::URL->new);

Base of this URL, defaults to a L<Mojo::URL> object.

=head2 fragment

  my $fragment = $url->fragment;
  $url         = $url->fragment('foo');

Fragment part of this URL.

=head2 host

  my $host = $url->host;
  $url     = $url->host('127.0.0.1');

Host part of this URL.

=head2 port

  my $port = $url->port;
  $url     = $url->port(8080);

Port part of this URL.

=head2 scheme

  my $scheme = $url->scheme;
  $url       = $url->scheme('http');

Scheme part of this URL.

=head2 userinfo

  my $info = $url->userinfo;
  $url     = $url->userinfo('root:pass%3Bw0rd');

Userinfo part of this URL.

=head1 METHODS

L<Mojo::URL> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 authority

  my $authority = $url->authority;
  $url          = $url->authority('root:pass%3Bw0rd@localhost:8080');

Authority part of this URL.

=head2 clone

  my $url2 = $url->clone;

Clone this URL.

=head2 host_port

  my $host_port = $url->host_port;

Normalized version of L</"host"> and L</"port">.

  # "xn--n3h.net:8080"
  Mojo::URL->new('http://☃.net:8080/test')->host_port;

=head2 ihost

  my $ihost = $url->ihost;
  $url      = $url->ihost('xn--bcher-kva.ch');

Host part of this URL in punycode format.

  # "xn--n3h.net"
  Mojo::URL->new('http://☃.net')->ihost;

=head2 is_abs

  my $bool = $url->is_abs;

Check if URL is absolute.

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

=head2 path

  my $path = $url->path;
  $url     = $url->path('/foo/bar');
  $url     = $url->path('foo/bar');
  $url     = $url->path(Mojo::Path->new);

Path part of this URL, relative paths will be merged with the existing path,
defaults to a L<Mojo::Path> object.

  # "http://example.com/DOM/HTML"
  Mojo::URL->new('http://example.com/perldoc/Mojo')->path('/DOM/HTML');

  # "http://example.com/perldoc/DOM/HTML"
  Mojo::URL->new('http://example.com/perldoc/Mojo')->path('DOM/HTML');

  # "http://example.com/perldoc/Mojo/DOM/HTML"
  Mojo::URL->new('http://example.com/perldoc/Mojo/')->path('DOM/HTML');

=head2 path_query

  my $path_query = $url->path_query;

Normalized version of L</"path"> and L</"query">.

=head2 protocol

  my $proto = $url->protocol;

Normalized version of L</"scheme">.

  # "http"
  Mojo::URL->new('HtTp://example.com')->protocol;

=head2 query

  my $query = $url->query;
  $url      = $url->query(replace => 'with');
  $url      = $url->query([merge => 'with']);
  $url      = $url->query({append => 'to'});
  $url      = $url->query(Mojo::Parameters->new);

Query part of this URL, pairs in an array will be merged and pairs in a hash
appended, defaults to a L<Mojo::Parameters> object.

  # "2"
  Mojo::URL->new('http://example.com?a=1&b=2')->query->param('b');

  # "http://example.com?a=2&c=3"
  Mojo::URL->new('http://example.com?a=1&b=2')->query(a => 2, c => 3);

  # "http://example.com?a=2&a=3"
  Mojo::URL->new('http://example.com?a=1&b=2')->query(a => [2, 3]);

  # "http://example.com?a=2&b=2&c=3"
  Mojo::URL->new('http://example.com?a=1&b=2')->query([a => 2, c => 3]);

  # "http://example.com?b=2"
  Mojo::URL->new('http://example.com?a=1&b=2')->query([a => undef]);

  # "http://example.com?a=1&b=2&a=2&c=3"
  Mojo::URL->new('http://example.com?a=1&b=2')->query({a => 2, c => 3});

=head2 to_abs

  my $abs = $url->to_abs;
  my $abs = $url->to_abs(Mojo::URL->new('http://example.com/foo'));

Clone relative URL and turn it into an absolute one using L</"base"> or
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

Turn URL into a string.

=head1 OPERATORS

L<Mojo::URL> overloads the following operators.

=head2 bool

  my $bool = !!$url;

Always true.

=head2 stringify

  my $str = "$url";

Alias for L</to_string>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
