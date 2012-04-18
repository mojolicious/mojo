package Mojo::URL;
use Mojo::Base -base;
use overload
  'bool'   => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

use Mojo::Parameters;
use Mojo::Path;
use Mojo::Util qw/punycode_decode punycode_encode url_escape url_unescape/;

has [qw/fragment host port scheme userinfo/];
has base => sub { Mojo::URL->new };

# Characters (RFC 3986)
our $UNRESERVED = 'A-Za-z0-9\-\.\_\~';
our $SUBDELIM   = '!\$\&\'\(\)\*\+\,\;\=';
my $PCHAR = "$UNRESERVED$SUBDELIM\%\:\@";

# "Homer, it's easy to criticize.
#  Fun, too."
sub new { shift->SUPER::new->parse(@_) }

sub authority {
  my ($self, $authority) = @_;

  # New authority
  if (defined $authority) {
    my $host = $authority;

    # Userinfo
    if ($authority =~ /^([^\@]+)\@(.+)$/) {
      $self->userinfo(url_unescape $1);
      $host = $2;
    }

    # Port
    my $port = undef;
    if ($host =~ /^(.+)\:(\d+)$/) {
      $host = $1;
      $self->port($2);
    }

    # Host
    $host = url_unescape $host;
    return $host =~ /[^\x00-\x7f]/ ? $self->ihost($host) : $self->host($host);
  }

  # Format
  my $userinfo = $self->userinfo;
  $authority .= url_escape($userinfo, "$UNRESERVED$SUBDELIM\:") . '@'
    if $userinfo;
  $authority .= lc($self->ihost || '');
  my $port = $self->port;
  $authority .= ":$port" if $port;

  return $authority;
}

sub clone {
  my $self = shift;

  my $clone = Mojo::URL->new;
  $clone->scheme($self->scheme);
  $clone->authority($self->authority);
  $clone->path($self->path->clone);
  $clone->query($self->query->clone);
  $clone->fragment($self->fragment);
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
  return unless my $host = $self->host;
  return $host unless $host =~ /[^\x00-\x7f]/;

  # Encode
  return join '.',
    map { /[^\x00-\x7f]/ ? ('xn--' . punycode_encode $_) : $_ } split /\./,
    $host;
}

sub is_abs { shift->scheme }

sub parse {
  my ($self, $url) = @_;
  return $self unless $url;

  # Official regex
  $url =~ m|(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?|;
  $self->scheme($1);
  $self->authority($2);
  $self->path->parse($3);
  $self->query($4);
  $self->fragment($5);

  return $self;
}

sub path {
  my ($self, $path) = @_;

  # Old path
  return $self->{path} ||= Mojo::Path->new unless $path;

  # New path
  if (!ref $path) {

    # Absolute path
    if ($path =~ m#^/#) { $path = Mojo::Path->new($path) }

    # Relative path
    else {
      my $new = Mojo::Path->new($path);
      $path = $self->{path} || Mojo::Path->new;
      pop @{$path->parts} unless $path->trailing_slash;
      push @{$path->parts}, @{$new->parts};
      $path->leading_slash(1)->trailing_slash($new->trailing_slash);
    }
  }
  $self->{path} = $path;

  return $self;
}

sub query {
  my $self = shift;

  # Old parameters
  return $self->{query} ||= Mojo::Parameters->new unless @_;

  # Replace with list
  if (@_ > 1) { $self->{query} = Mojo::Parameters->new(@_) }

  # Merge with array
  elsif (ref $_[0] eq 'ARRAY') {
    my $q = $self->{query} ||= Mojo::Parameters->new;
    while (my $name = shift @{$_[0]}) {
      my $value = shift @{$_[0]};
      defined $value ? $q->param($name => $value) : $q->remove($name);
    }
  }

  # Append hash
  elsif (ref $_[0] eq 'HASH') {
    ($self->{query} ||= Mojo::Parameters->new)->append(%{$_[0]});
  }

  # Replace with string
  else { $self->{query} = Mojo::Parameters->new($_[0]) }

  return $self;
}

sub to_abs {
  my $self = shift;
  my $base = shift || $self->base->clone;

  # Scheme
  my $abs = $self->clone;
  return $abs if $abs->is_abs;
  $abs->scheme($base->scheme);

  # Authority
  return $abs if $abs->authority;
  $abs->authority($base->authority);

  # Absolute path
  my $path = $abs->path;
  return $abs if $path->leading_slash;

  # Inherit path
  my $base_path = $base->path;
  if (!@{$path->parts}) {
    $path =
      $abs->path($base_path->clone)->path->trailing_slash(0)->canonicalize;

    # Query
    return $abs if length $abs->query->to_string;
    $abs->query($base->query->clone);
  }

  # Merge paths
  else {
    my $new = $base_path->clone->leading_slash(1);

    # Characters after the right-most '/' need to go
    pop @{$new->parts} if @{$path->parts} && !$new->trailing_slash;
    push @{$new->parts}, @{$path->parts};
    $new->trailing_slash($path->trailing_slash) if @{$new->parts};
    $abs->path($new->canonicalize);
  }

  return $abs;
}

sub to_rel {
  my $self = shift;
  my $base = shift || $self->base->clone;

  # Scheme and authority
  my $rel = $self->clone->base($base)->scheme(undef);
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

# "Dad, what's a Muppet?
#  Well, it's not quite a mop, not quite a puppet, but man... *laughs*
#  So, to answer you question, I don't know."
sub to_string {
  my $self = shift;

  # Scheme
  my $url = '';
  if (my $scheme = $self->scheme) { $url .= lc "$scheme://" }

  # Authority
  my $authority = $self->authority;
  $url .= $url ? $authority : $authority ? "//$authority" : '';

  # Path
  $url .= $self->path;

  # Query
  my $query = join '', $self->query;
  $url .= "?$query" if length $query;

  # Fragment
  if (my $fragment = $self->fragment) {
    $url .= '#' . url_escape $fragment, "$PCHAR\/\?";
  }

  return $url;
}

1;
__END__

=encoding utf8

=head1 NAME

Mojo::URL - Uniform Resource Locator

=head1 SYNOPSIS

  use Mojo::URL;

  # Parse
  my $url = Mojo::URL->new(
    'http://sri:foobar@kraih.com:3000/foo/bar?foo=bar#23'
  );
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
  $url->host('kraih.com');
  $url->port(3000);
  $url->path('/foo/bar');
  $url->path('baz');
  $url->query->param(foo => 'bar');
  $url->fragment(23);
  say $url;

=head1 DESCRIPTION

L<Mojo::URL> implements a subset of RFC 3986 and RFC 3987 for Uniform
Resource Locators with support for IDNA and IRIs.

=head1 ATTRIBUTES

L<Mojo::URL> implements the following attributes.

=head2 C<authority>

  my $authority = $url->authority;
  $url          = $url->authority('root:pass%3Bw0rd@localhost:8080');

Authority part of this URL.

=head2 C<base>

  my $base = $url->base;
  $url     = $url->base(Mojo::URL->new);

Base of this URL.

=head2 C<fragment>

  my $fragment = $url->fragment;
  $url         = $url->fragment('foo');

Fragment part of this URL.

=head2 C<host>

  my $host = $url->host;
  $url     = $url->host('127.0.0.1');

Host part of this URL.

=head2 C<port>

  my $port = $url->port;
  $url     = $url->port(8080);

Port part of this URL.

=head2 C<scheme>

  my $scheme = $url->scheme;
  $url       = $url->scheme('http');

Scheme part of this URL.

=head2 C<userinfo>

  my $userinfo = $url->userinfo;
  $url         = $url->userinfo('root:pass%3Bw0rd');

Userinfo part of this URL.

=head1 METHODS

L<Mojo::URL> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $url = Mojo::URL->new;
  my $url = Mojo::URL->new('http://127.0.0.1:3000/foo?f=b&baz=2#foo');

Construct a new L<Mojo::URL> object.

=head2 C<clone>

  my $url2 = $url->clone;

Clone this URL.

=head2 C<ihost>

  my $ihost = $url->ihost;
  $url      = $url->ihost('xn--bcher-kva.ch');

Host part of this URL in punycode format.

  # "xn--da5b0n.net"
  Mojo::URL->new('http://☃.net')->ihost;

=head2 C<is_abs>

  my $success = $url->is_abs;

Check if URL is absolute.

=head2 C<parse>

  $url = $url->parse('http://127.0.0.1:3000/foo/bar?fo=o&baz=23#foo');

Parse URL.

=head2 C<path>

  my $path = $url->path;
  $url     = $url->path('/foo/bar');
  $url     = $url->path('foo/bar');
  $url     = $url->path(Mojo::Path->new);

Path part of this URL, relative paths will be appended to the existing path,
defaults to a L<Mojo::Path> object.

  # "http://mojolicio.us/Mojo/DOM"
  Mojo::URL->new('http://mojolicio.us/perldoc')->path('/Mojo/DOM');

  # "http://mojolicio.us/perldoc/Mojo/DOM"
  Mojo::URL->new('http://mojolicio.us/perldoc')->path('Mojo/DOM');

=head2 C<query>

  my $query = $url->query;
  $url      = $url->query(replace => 'with');
  $url      = $url->query([merge => 'with']);
  $url      = $url->query({append => 'to'});
  $url      = $url->query(Mojo::Parameters->new);

Query part of this URL, defaults to a L<Mojo::Parameters> object.

  # "2"
  Mojo::URL->new('http://mojolicio.us?a=1&b=2')->query->param('b');

  # "http://mojolicio.us?a=2&c=3"
  Mojo::URL->new('http://mojolicio.us?a=1&b=2')->query(a => 2, c => 3);

  # "http://mojolicio.us?a=2&b=2&c=3"
  Mojo::URL->new('http://mojolicio.us?a=1&b=2')->query([a => 2, c => 3]);

  # "http://mojolicio.us?b=2"
  Mojo::URL->new('http://mojolicio.us?a=1&b=2')->query([a => undef]);

  # "http://mojolicio.us?a=1&b=2&a=2&c=3"
  Mojo::URL->new('http://mojolicio.us?a=1&b=2')->query({a => 2, c => 3});

=head2 C<to_abs>

  my $abs = $url->to_abs;
  my $abs = $url->to_abs(Mojo::URL->new('http://kraih.com/foo'));

Clone relative URL and turn it into an absolute one.

=head2 C<to_rel>

  my $rel = $url->to_rel;
  my $rel = $url->to_rel(Mojo::URL->new('http://kraih.com/foo'));

Clone absolute URL and turn it into a relative one.

=head2 C<to_string>

  my $string = $url->to_string;

Turn URL into a string.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
