package Mojo::JSON::Pointer;
use Mojo::Base -base;

has 'data';

sub contains { shift->_pointer(1, @_) }
sub get      { shift->_pointer(0, @_) }

sub new { @_ > 1 ? shift->SUPER::new(data => shift) : shift->SUPER::new }

sub _pointer {
  my ($self, $contains, $data, $pointer) = @_;
  ($data, $pointer) = ($self->data, $data) unless defined $pointer;

  return $data unless $pointer =~ s!^/!!;
  for my $p ($pointer eq '' ? ($pointer) : (split '/', $pointer)) {
    $p =~ s/~0/~/g;
    $p =~ s!~1!/!g;

    # Hash
    if (ref $data eq 'HASH' && exists $data->{$p}) { $data = $data->{$p} }

    # Array
    elsif (ref $data eq 'ARRAY' && $p =~ /^\d+$/ && @$data > $p) {
      $data = $data->[$p];
    }

    # Nothing
    else { return undef }
  }

  return $contains ? 1 : $data;
}

1;

=encoding utf8

=head1 NAME

Mojo::JSON::Pointer - JSON Pointers

=head1 SYNOPSIS

  use Mojo::JSON::Pointer;

  my $pointer = Mojo::JSON::Pointer->new({foo => [23, 'bar']});
  say $pointer->get('/foo/1');
  say 'Contains "/foo".' if $pointer->contains('/foo');

=head1 DESCRIPTION

L<Mojo::JSON::Pointer> is a relaxed implementation of
L<RFC 6901|http://tools.ietf.org/html/rfc6901>.

=head1 ATTRIBUTES

L<Mojo::JSON::Pointer> implements the following attributes.

=head2 data

  my $data = $pointer->data;
  $pointer = $pointer->data({foo => 'bar'});

Data to be processed.

=head1 METHODS

L<Mojo::JSON::Pointer> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 contains

  my $bool = $pointer->contains('/foo/1');
  my $bool = $pointer->contains($data, '/foo/1');

Check if Perl data structure contains a value that can be identified with the
given JSON Pointer, defaults to using L</data>.

  # True
  $pointer->contains({'♥' => 'mojolicious'}, '/♥');
  $pointer->contains({foo => 'bar', baz => [4, 5, 6]}, '/foo');
  $pointer->contains({foo => 'bar', baz => [4, 5, 6]}, '/baz/2');

  # False
  $pointer->contains({'♥' => 'mojolicious'}, '/☃');
  $pointer->contains({foo => 'bar', baz => [4, 5, 6]}, '/bar');
  $pointer->contains({foo => 'bar', baz => [4, 5, 6]}, '/baz/9');

=head2 get

  my $value = $pointer->get('/foo/bar');
  my $value = $pointer->get($data, '/foo/bar');

Extract value identified by the given JSON Pointer, defaults to using
L</data>.

  # "mojolicious"
  $pointer->get({'♥' => 'mojolicious'}, '/♥');

  # "bar"
  $pointer->get({foo => 'bar', baz => [4, 5, 6]}, '/foo');

  # "4"
  $pointer->get({foo => 'bar', baz => [4, 5, 6]}, '/baz/0');

  # "6"
  $pointer->get({foo => 'bar', baz => [4, 5, 6]}, '/baz/2');

=head2 new

  my $pointer = Mojo::JSON::Pointer->new;
  my $pointer = Mojo::JSON::Pointer->new({foo => 'bar'});

Build new L<Mojo::JSON::Pointer> object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
