package Mojo::Cookie::Response;
use Mojo::Base 'Mojo::Cookie';

use Mojo::Date;
use Mojo::Util 'quote';

has [qw(domain httponly max_age path secure)];

sub expires {
  my $self = shift;

  # Upgrade
  my $e = $self->{expires};
  return $self->{expires} = defined $e && !ref $e ? Mojo::Date->new($e) : $e
    unless @_;
  $self->{expires} = shift;

  return $self;
}

sub parse {
  my ($self, $str) = @_;

  my @cookies;
  for my $token ($self->_tokenize($str // '')) {
    for my $i (0 .. $#$token) {
      my ($name, $value) = @{$token->[$i]};

      # This will only run once
      push @cookies, $self->new(name => $name, value => $value // '') and next
        unless $i;

      # Attributes (Netscape and RFC 6265)
      my @match
        = $name =~ /^(expires|domain|path|secure|Max-Age|HttpOnly)$/msi;
      next unless @match;
      my $attr = lc $match[0];
      $attr =~ tr/-/_/;
      $cookies[-1]->$attr($attr =~ /(?:secure|HttpOnly)/i ? 1 : $value);
    }
  }

  return \@cookies;
}

sub to_string {
  my $self = shift;

  # Name and value (Netscape)
  return '' unless my $name = $self->name;
  my $value = $self->value // '';
  $value = $value =~ /[,;"]/ ? quote($value) : $value;
  my $cookie = "$name=$value";

  # "expires" (Netscape)
  if (defined(my $e = $self->expires)) { $cookie .= "; expires=$e" }

  # "domain" (Netscape)
  if (my $domain = $self->domain) { $cookie .= "; domain=$domain" }

  # "path" (Netscape)
  if (my $path = $self->path) { $cookie .= "; path=$path" }

  # "secure" (Netscape)
  if (my $secure = $self->secure) { $cookie .= "; secure" }

  # "Max-Age" (RFC 6265)
  if (defined(my $m = $self->max_age)) { $cookie .= "; Max-Age=$m" }

  # "HttpOnly" (RFC 6265)
  if (my $httponly = $self->httponly) { $cookie .= "; HttpOnly" }

  return $cookie;
}

1;

=head1 NAME

Mojo::Cookie::Response - HTTP response cookie

=head1 SYNOPSIS

  use Mojo::Cookie::Response;

  my $cookie = Mojo::Cookie::Response->new;
  $cookie->name('foo');
  $cookie->value('bar');
  say "$cookie";

=head1 DESCRIPTION

L<Mojo::Cookie::Response> is a container for HTTP response cookies as
described in RFC 6265.

=head1 ATTRIBUTES

L<Mojo::Cookie::Response> inherits all attributes from L<Mojo::Cookie> and
implements the following new ones.

=head2 domain

  my $domain = $cookie->domain;
  $cookie    = $cookie->domain('localhost');

Cookie domain.

=head2 httponly

  my $httponly = $cookie->httponly;
  $cookie      = $cookie->httponly(1);

HttpOnly flag, which can prevent client-side scripts from accessing this
cookie.

=head2 max_age

  my $max_age = $cookie->max_age;
  $cookie     = $cookie->max_age(60);

Max age for cookie.

=head2 path

  my $path = $cookie->path;
  $cookie  = $cookie->path('/test');

Cookie path.

=head2 secure

  my $secure = $cookie->secure;
  $cookie    = $cookie->secure(1);

Secure flag, which instructs browsers to only send this cookie over HTTPS
connections.

=head1 METHODS

L<Mojo::Cookie::Response> inherits all methods from L<Mojo::Cookie> and
implements the following new ones.

=head2 expires

  my $expires = $cookie->expires;
  $cookie     = $cookie->expires(time + 60);
  $cookie     = $cookie->expires(Mojo::Date->new(time + 60));

Expiration for cookie.

=head2 parse

  my $cookies = Mojo::Cookie::Response->parse('f=b; path=/');

Parse cookies.

=head2 to_string

  my $str = $cookie->to_string;

Render cookie.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
