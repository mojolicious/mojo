package Mojo::Asset;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';

has 'end_range';
has start_range => 0;

# "Marge, it takes two to lie. One to lie and one to listen."
sub add_chunk { croak 'Method "add_chunk" not implemented by subclass' }
sub contains  { croak 'Method "contains" not implemented by subclass' }
sub get_chunk { croak 'Method "get_chunk" not implemented by subclass' }

sub is_file {undef}

sub move_to { croak 'Method "move_to" not implemented by subclass' }
sub size    { croak 'Method "size" not implemented by subclass' }
sub slurp   { croak 'Method "slurp" not implemented by subclass' }

1;
__END__

=head1 NAME

Mojo::Asset - HTTP 1.1 content storage base class

=head1 SYNOPSIS

  use Mojo::Base 'Mojo::Asset';

=head1 DESCRIPTION

L<Mojo::Asset> is an abstract base class for HTTP 1.1 content storage.

=head1 ATTRIBUTES

L<Mojo::Asset> implements the following attributes.

=head2 C<end_range>

  my $end = $asset->end_range;
  $asset  = $asset->end_range(8);

Pretend file ends earlier.

=head2 C<start_range>

  my $start = $asset->start_range;
  $asset    = $asset->start_range(0);

Pretend file starts later.

=head1 METHODS

L<Mojo::Asset> inherits all methods from L<Mojo::EventEmitter> and implements
the following new ones.

=head2 C<add_chunk>

  $asset = $asset->add_chunk('foo bar baz');

Add chunk of data to asset, meant to be overloaded in a subclass.

=head2 C<contains>

  my $position = $asset->contains('bar');

Check if asset contains a specific string, meant to be overloaded in a
subclass.

=head2 C<get_chunk>

  my $chunk = $asset->get_chunk($offset);

Get chunk of data starting from a specific position, meant to be overloaded
in a subclass.

=head2 C<is_file>

  my $false = $asset->is_file;

False.

=head2 C<move_to>

  $asset = $asset->move_to('/foo/bar/baz.txt');

Move asset data into a specific file, meant to be overloaded in a subclass.

=head2 C<size>

  my $size = $asset->size;

Size of asset data in bytes, meant to be overloaded in a subclass.

=head2 C<slurp>

  my $string = $asset->slurp;

Read all asset data at once. Meant to be overloaded in a subclass.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
