package Mojo::JSON::Pointer;
use Mojo::Base -base;

use Scalar::Util 'looks_like_number';

sub contains { shift->_pointer(1, @_) }
sub get      { shift->_pointer(0, @_) }

sub _pointer {
  my ($self, $contains, $data, $pointer) = @_;

  return $data unless $pointer =~ s!^/!!;
  for my $p ($pointer eq '' ? ($pointer) : (split '/', $pointer)) {
    $p =~ s/~0/~/g;
    $p =~ s!~1!/!g;

    # Hash
    if (ref $data eq 'HASH' && exists $data->{$p}) { $data = $data->{$p} }

    # Array
    elsif (ref $data eq 'ARRAY' && looks_like_number($p) && @$data > $p) {
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

  my $pointer = Mojo::JSON::Pointer->new;
  say $pointer->get({foo => [23, 'bar']}, '/foo/1');
  say 'Contains "/foo".' if $pointer->contains({foo => [23, 'bar']}, '/foo');

=head1 DESCRIPTION

L<Mojo::JSON::Pointer> is a relaxed implementation of RFC 6901.

=head1 METHODS

=head2 contains

  my $success = $pointer->contains($data, '/foo/1');

Check if data structure contains a value that can be identified with the given
JSON Pointer.

  # True
  $pointer->contains({'♥' => 'mojolicious'}, '/♥');
  $pointer->contains({foo => 'bar', baz => [4, 5, 6]}, '/foo');
  $pointer->contains({foo => 'bar', baz => [4, 5, 6]}, '/baz/2');

  # False
  $pointer->contains({'♥' => 'mojolicious'}, '/☃');
  $pointer->contains({foo => 'bar', baz => [4, 5, 6]}, '/bar');
  $pointer->contains({foo => 'bar', baz => [4, 5, 6]}, '/baz/9');

=head2 get

  my $value = $pointer->get($data, '/foo/bar');

Extract value identified by the given JSON Pointer.

  # "mojolicious"
  $pointer->get({'♥' => 'mojolicious'}, '/♥');

  # "bar"
  $pointer->get({foo => 'bar', baz => [4, 5, 6]}, '/foo');

  # "4"
  $pointer->get({foo => 'bar', baz => [4, 5, 6]}, '/baz/0');

  # "6"
  $pointer->get({foo => 'bar', baz => [4, 5, 6]}, '/baz/2');

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
