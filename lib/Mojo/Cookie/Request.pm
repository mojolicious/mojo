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
  for my $token (map {@$_} $self->_tokenize($string)) {
    my ($name, $value) = @$token;
    next if $name =~ /^\$/;
    push @cookies,
      Mojo::Cookie::Request->new(name => $name, value => $value // '');
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

Mojo::Cookie::Request - HTTP request cookie container

=head1 SYNOPSIS

  use Mojo::Cookie::Request;

  my $cookie = Mojo::Cookie::Request->new;
  $cookie->name('foo');
  $cookie->value('bar');
  say "$cookie";

=head1 DESCRIPTION

L<Mojo::Cookie::Request> is a container for HTTP request cookies.

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
