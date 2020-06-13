package Mojo::JSON::Pointer;
use Mojo::Base -base;

has 'data';

sub contains { shift->_pointer(0, @_) }
sub get      { shift->_pointer(1, @_) }

sub new { @_ > 1 ? shift->SUPER::new(data => shift) : shift->SUPER::new }

sub _pointer {
  my ($self, $get, $pointer) = @_;

  my $data = $self->data;
  return length $pointer ? undef : $get ? $data : 1 unless $pointer =~ s!^/!!;
  for my $p (length $pointer ? (split '/', $pointer, -1) : ($pointer)) {
    $p =~ s!~1!/!g;
    $p =~ s/~0/~/g;

    # Hash
    if (ref $data eq 'HASH' && exists $data->{$p}) { $data = $data->{$p} }

    # Array
    elsif (ref $data eq 'ARRAY' && $p =~ /^\d+$/ && @$data > $p) { $data = $data->[$p] }

    # Nothing
    else { return undef }
  }

  return $get ? $data : 1;
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

L<Mojo::JSON::Pointer> is an implementation of L<RFC 6901|http://tools.ietf.org/html/rfc6901>.

=head1 ATTRIBUTES

L<Mojo::JSON::Pointer> implements the following attributes.

=head2 data

  my $data = $pointer->data;
  $pointer = $pointer->data({foo => 'bar'});

Data structure to be processed.

=head1 METHODS

L<Mojo::JSON::Pointer> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 contains

  my $bool = $pointer->contains('/foo/1');

Check if L</"data"> contains a value that can be identified with the given JSON Pointer.

  # True
  Mojo::JSON::Pointer->new('just a string')->contains('');
  Mojo::JSON::Pointer->new({'♥' => 'mojolicious'})->contains('/♥');
  Mojo::JSON::Pointer->new({foo => 'bar', baz => [4, 5]})->contains('/foo');
  Mojo::JSON::Pointer->new({foo => 'bar', baz => [4, 5]})->contains('/baz/1');

  # False
  Mojo::JSON::Pointer->new({'♥' => 'mojolicious'})->contains('/☃');
  Mojo::JSON::Pointer->new({foo => 'bar', baz => [4, 5]})->contains('/bar');
  Mojo::JSON::Pointer->new({foo => 'bar', baz => [4, 5]})->contains('/baz/9');

=head2 get

  my $value = $pointer->get('/foo/bar');

Extract value from L</"data"> identified by the given JSON Pointer.

  # "just a string"
  Mojo::JSON::Pointer->new('just a string')->get('');

  # "mojolicious"
  Mojo::JSON::Pointer->new({'♥' => 'mojolicious'})->get('/♥');

  # "bar"
  Mojo::JSON::Pointer->new({foo => 'bar', baz => [4, 5, 6]})->get('/foo');

  # "4"
  Mojo::JSON::Pointer->new({foo => 'bar', baz => [4, 5, 6]})->get('/baz/0');

  # "6"
  Mojo::JSON::Pointer->new({foo => 'bar', baz => [4, 5, 6]})->get('/baz/2');

=head2 new

  my $pointer = Mojo::JSON::Pointer->new;
  my $pointer = Mojo::JSON::Pointer->new({foo => 'bar'});

Build new L<Mojo::JSON::Pointer> object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
