package Mojo::Cookie::Request;
use Mojo::Base 'Mojo::Cookie';

use Mojo::Util 'quote';

# "Lisa, would you like a donut?
#  No thanks. Do you have any fruit?
#  This has purple in it. Purple is a fruit."
sub parse {
  my ($self, $string) = @_;

  # Walk tree
  my @cookies;
  for my $knot ($self->_tokenize($string)) {
    for my $token (@{$knot}) {
      my ($name, $value) = @{$token};

      # Garbage (RFC 2965)
      next if $name =~ /^\$/;

      # Name and value
      push @cookies, Mojo::Cookie::Request->new;
      $cookies[-1]->name($name);
      $cookies[-1]->value($value //= '');
    }
  }

  return \@cookies;
}

sub to_string {
  my $self = shift;
  return '' unless my $cookie = $self->name;
  $cookie .= '=';
  my $value = $self->value;
  $cookie .= $value =~ /[,;"]/ ? quote($value) : $value if defined $value;
  return $cookie;
}

1;
__END__

=head1 NAME

Mojo::Cookie::Request - HTTP 1.1 request cookie container

=head1 SYNOPSIS

  use Mojo::Cookie::Request;

  my $cookie = Mojo::Cookie::Request->new;
  $cookie->name('foo');
  $cookie->value('bar');
  say $cookie;

=head1 DESCRIPTION

L<Mojo::Cookie::Request> is a container for HTTP 1.1 request cookies.

=head1 ATTRIBUTES

L<Mojo::Cookie::Request> inherits all attributes from L<Mojo::Cookie>.

=head1 METHODS

L<Mojo::Cookie::Request> inherits all methods from L<Mojo::Cookie> and
implements the following new ones.

=head2 C<parse>

  my $cookies = $cookie->parse('f=b; g=a');

Parse cookies.

=head2 C<to_string>

  my $string = $cookie->to_string;

Render cookie.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
