package Mojo::Cookie::Request;
use Mojo::Base 'Mojo::Cookie';

use Mojo::Util 'quote';

sub parse {
  my ($self, $str) = @_;

  my @cookies;
  for my $token (map {@$_} $self->_tokenize($str // '')) {
    my ($name, $value) = @$token;
    next if $name =~ /^\$/;
    push @cookies, $self->new(name => $name, value => $value // '');
  }

  return \@cookies;
}

sub to_string {
  my $self = shift;
  return '' unless my $name = $self->name;
  my $value = $self->value // '';
  $value = $value =~ /[,;"]/ ? quote($value) : $value;
  return "$name=$value";
}

1;

=head1 NAME

Mojo::Cookie::Request - HTTP request cookie

=head1 SYNOPSIS

  use Mojo::Cookie::Request;

  my $cookie = Mojo::Cookie::Request->new;
  $cookie->name('foo');
  $cookie->value('bar');
  say "$cookie";

=head1 DESCRIPTION

L<Mojo::Cookie::Request> is a container for HTTP request cookies as described
in RFC 6265.

=head1 ATTRIBUTES

L<Mojo::Cookie::Request> inherits all attributes from L<Mojo::Cookie>.

=head1 METHODS

L<Mojo::Cookie::Request> inherits all methods from L<Mojo::Cookie> and
implements the following new ones.

=head2 parse

  my $cookies = Mojo::Cookie::Request->parse('f=b; g=a');

Parse cookies.

=head2 to_string

  my $str = $cookie->to_string;

Render cookie.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
