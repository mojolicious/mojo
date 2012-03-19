package Mojo::Cookie::Response;
use Mojo::Base 'Mojo::Cookie';

use Mojo::Date;
use Mojo::Util 'quote';

has [qw/domain httponly max_age path secure/];

my $ATTR_RE = qr/(Domain|expires|HttpOnly|Max-Age|Path|Secure)/msi;

sub expires {
  my ($self, $expires) = @_;

  # New expires value
  if (defined $expires) {
    $self->{expires} = $expires;
    return $self;
  }

  # Upgrade
  $self->{expires} = Mojo::Date->new($self->{expires})
    if defined $self->{expires} && !ref $self->{expires};

  return $self->{expires};
}

# "Remember the time he ate my goldfish?
#  And you lied and said I never had goldfish.
#  Then why did I have the bowl Bart? Why did I have the bowl?"
sub parse {
  my ($self, $string) = @_;

  # Walk tree
  my @cookies;
  for my $knot ($self->_tokenize($string)) {
    for my $i (0 .. $#{$knot}) {
      my ($name, $value) = @{$knot->[$i]};

      # This will only run once
      if (!$i) {
        push @cookies, Mojo::Cookie::Response->new;
        $cookies[-1]->name($name);
        $cookies[-1]->value($value //= '');
      }

      # Attributes
      elsif (my @match = $name =~ $ATTR_RE) {
        my $attr = lc $match[0];
        $attr =~ tr/-/_/;
        $cookies[-1]->$attr($attr =~ /(?:Secure|HttpOnly)/i ? 1 : $value);
      }
    }
  }

  return \@cookies;
}

sub to_string {
  my $self = shift;

  # Name and value
  return '' unless my $cookie = $self->name;
  $cookie .= '=';
  my $value = $self->value;
  $cookie .= $value =~ /[,;"]/ ? quote($value) : $value if defined $value;

  # Domain
  if (my $domain = $self->domain) { $cookie .= "; Domain=$domain" }

  # Path
  if (my $path = $self->path) { $cookie .= "; Path=$path" }

  # Max-Age
  if (defined(my $m = $self->max_age)) { $cookie .= "; Max-Age=$m" }

  # Expires
  if (defined(my $e = $self->expires)) { $cookie .= "; expires=$e" }

  # Secure
  if (my $secure = $self->secure) { $cookie .= "; Secure" }

  # HttpOnly
  if (my $httponly = $self->httponly) { $cookie .= "; HttpOnly" }

  return $cookie;
}

1;
__END__

=head1 NAME

Mojo::Cookie::Response - HTTP 1.1 response cookie container

=head1 SYNOPSIS

  use Mojo::Cookie::Response;

  my $cookie = Mojo::Cookie::Response->new;
  $cookie->name('foo');
  $cookie->value('bar');
  say $cookie;

=head1 DESCRIPTION

L<Mojo::Cookie::Response> is a container for HTTP 1.1 response cookies.

=head1 ATTRIBUTES

L<Mojo::Cookie::Response> inherits all attributes from L<Mojo::Cookie> and
implements the followign new ones.

=head2 C<domain>

  my $domain = $cookie->domain;
  $cookie    = $cookie->domain('localhost');

Cookie domain.

=head2 C<httponly>

  my $httponly = $cookie->httponly;
  $cookie      = $cookie->httponly(1);

HttpOnly flag, which can prevent client side scripts from accessing this
cookie.

=head2 C<max_age>

  my $max_age = $cookie->max_age;
  $cookie     = $cookie->max_age(60);

Max age for cookie in seconds.

=head2 C<path>

  my $path = $cookie->path;
  $cookie  = $cookie->path('/test');

Cookie path.

=head2 C<secure>

  my $secure = $cookie->secure;
  $cookie    = $cookie->secure(1);

Secure flag, which instructs browsers to only send this cookie over HTTPS
connections.

=head1 METHODS

L<Mojo::Cookie::Response> inherits all methods from L<Mojo::Cookie> and
implements the following new ones.

=head2 C<expires>

  my $expires = $cookie->expires;
  $cookie     = $cookie->expires(time + 60);
  $cookie     = $cookie->expires(Mojo::Date->new(time + 60));

Expiration for cookie in seconds.

=head2 C<parse>

  my $cookies = $cookie->parse('f=b; Path=/');

Parse cookies.

=head2 C<to_string>

  my $string = $cookie->to_string;

Render cookie.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
