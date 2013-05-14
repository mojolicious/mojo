package Mojo::URL;
use Mojo::Base -base;
use overload
  'bool'   => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

use Mojo::Parameters;
use Mojo::Path;
use Mojo::Util qw(punycode_decode punycode_encode url_escape url_unescape);

has base => sub { Mojo::URL->new };
has [qw(fragment host port scheme userinfo)];

sub new { shift->SUPER::new->parse(@_) }

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
  return undef unless defined(my $authority = $self->ihost);
  if (my $userinfo = $self->userinfo) {
    $userinfo = url_escape $userinfo, '^A-Za-z0-9\-._~!$&\'()*+,;=:';
    $authority = $userinfo . '@' . $authority;
  }
  if (my $port = $self->port) { $authority .= ":$port" }

  return $authority;
}

sub clone {
  my $self = shift;

  my $clone = $self->new;
  $clone->$_($self->$_) for qw(scheme userinfo host port fragment);
  $clone->path($self->path->clone);
  $clone->query($self->query->clone);
  $clone->base($self->base->clone) if $self->{base};

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

sub parse {
  my ($self, $url) = @_;
  return $self unless $url;

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

sub to_rel {
  my $self = shift;

  my $rel = $self->clone;
  return $rel unless $rel->is_abs;

  # Scheme and authority
  my $base = shift || $rel->base;
  $rel->base($base)->scheme(undef);
  $rel->userinfo(undef)->host(undef)->port(undef) if $base->authority;

  # Path
  my @parts      = @{$rel->path->parts};
  my $base_path  = $base->path;
  my @base_parts = @{$base_path->parts};
  pop @base_parts unless $base_path->trailing_slash;
  while (@parts && @base_parts && $parts[0] eq $base_parts[0]) {
    shift @parts;
    shift @base_parts;
  }
  my $path = $rel->path(Mojo::Path->new)->path;
  $path->leading_slash(1) if $rel->authority;
  $path->parts([('..') x @base_parts, @parts]);
  $path->trailing_slash(1) if $self->path->trailing_slash;

  return $rel;
}

sub to_string {
  my $self = shift;

  # Scheme
  my $url = '';
  if (my $proto = $self->protocol) { $url .= "$proto:" }

  # Authority
  my $authority = $self->authority;
  $url .= "//$authority" if defined $authority;

  # Path
  my $path = $self->path->to_string;
  $url .= !$authority || $path eq '' || $path =~ m!^/! ? $path : "/$path";

  # Query
  if (length(my $query = $self->query->to_string)) { $url .= "?$query" }

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
  $url->path('baz');
  $url->query->param(foo => 'bar');
  $url->fragment(23);
  say "$url";

=head1 DESCRIPTION

L<Mojo::URL> implements a subset of RFC 3986 and RFC 3987 for Uniform
Resource Locators with support for IDNA and IRIs.

=head1 ATTRIBUTES

L<Mojo::URL> implements the following attributes.

=head2 base

  my $base = $url->base;
  $url     = $url->base(Mojo::URL->new);

Base of this URL.

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

  my $userinfo = $url->userinfo;
  $url         = $url->userinfo('root:pass%3Bw0rd');

Userinfo part of this URL.

=head1 METHODS

L<Mojo::URL> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 new

  my $url = Mojo::URL->new;
  my $url = Mojo::URL->new('http://127.0.0.1:3000/foo?f=b&baz=2#foo');

Construct a new L<Mojo::URL> object and C<parse> URL if necessary.

=head2 authority

  my $authority = $url->authority;
  $url          = $url->authority('root:pass%3Bw0rd@localhost:8080');

Authority part of this URL.

=head2 clone

  my $url2 = $url->clone;

Clone this URL.

=head2 ihost

  my $ihost = $url->ihost;
  $url      = $url->ihost('xn--bcher-kva.ch');

Host part of this URL in punycode format.

  # "xn--da5b0n.net"
  Mojo::URL->new('http://☃.net')->ihost;

=head2 is_abs

  my $success = $url->is_abs;

Check if URL is absolute.

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

=head2 protocol

  my $proto = $url->protocol;

Normalized version of C<scheme>.

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

Clone relative URL and turn it into an absolute one.

=head2 to_rel

  my $rel = $url->to_rel;
  my $rel = $url->to_rel(Mojo::URL->new('http://example.com/foo'));

Clone absolute URL and turn it into a relative one.

=head2 to_string

  my $str = $url->to_string;
  my $str = "$url";

Turn URL into a string.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
