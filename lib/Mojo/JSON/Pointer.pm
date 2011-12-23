package Mojo::JSON::Pointer;
use Mojo::Base -base;

use Mojo::Util 'url_unescape';
use Scalar::Util 'looks_like_number';

sub contains { shift->_pointer(1, @_) }
sub get      { shift->_pointer(0, @_) }

# "Google, even though you've enslaved half the world,
#  you're still a damn fine search engine."
sub _pointer {
  my ($self, $contains, $data, $pointer) = @_;

  # Parse pointer and walk data structure
  return unless $pointer =~ s|^/||;
  for my $p (split '/', $pointer) {
    $p = url_unescape $p;
    utf8::decode $p;

    # Hash
    if (ref $data eq 'HASH' && exists $data->{$p}) { $data = $data->{$p} }

    # Array
    elsif (ref $data eq 'ARRAY' && looks_like_number($p) && @$data > $p) {
      $data = $data->[$p];
    }

    # Nothing
    else {return}
  }

  return $contains ? 1 : $data;
}

1;
__END__

=head1 NAME

Mojo::JSON::Pointer - JSON Pointers

=head1 SYNOPSIS

  use Mojo::JSON::Pointer;

  my $p = Mojo::JSON::Pointer->new;
  say $p->get({foo => [23, 'bar']}, '/foo/1');
  say 'Contains "/foo".' if $p->contains({foo => [23, 'bar']}, '/foo');

=head1 DESCRIPTION

L<Mojo::JSON::Pointer> implements JSON Pointers as described in
L<http://tools.ietf.org/html/draft-pbryan-zyp-json-pointer-02>. Note that
this module is EXPERIMENTAL and might change without warning!

=head1 METHODS

=head2 C<contains>

  my $success = $p->contains($data, '/foo/1');

Check if data structure contains a value that can be identified with the
given JSON Pointer.

=head2 C<get>

  my $value = $p->get($data, '/foo/bar');

Extract value identified by the given JSON Pointer.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
