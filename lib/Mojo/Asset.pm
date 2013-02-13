package Mojo::Asset;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';

has 'end_range';
has start_range => 0;

sub add_chunk { croak 'Method "add_chunk" not implemented by subclass' }
sub contains  { croak 'Method "contains" not implemented by subclass' }
sub get_chunk { croak 'Method "get_chunk" not implemented by subclass' }

sub is_file {undef}

sub is_range { !!($_[0]->end_range || $_[0]->start_range) }

sub move_to { croak 'Method "move_to" not implemented by subclass' }
sub size    { croak 'Method "size" not implemented by subclass' }
sub slurp   { croak 'Method "slurp" not implemented by subclass' }

1;

=head1 NAME

Mojo::Asset - HTTP content storage base class

=head1 SYNOPSIS

  package Mojo::Asset::MyAsset;
  use Mojo::Base 'Mojo::Asset';

  sub add_chunk {...}
  sub contains  {...}
  sub get_chunk {...}
  sub move_to   {...}
  sub size      {...}
  sub slurp     {...}

=head1 DESCRIPTION

L<Mojo::Asset> is an abstract base class for HTTP content storage.

=head1 EVENTS

L<Mojo::Asset> inherits all events from L<Mojo::EventEmitter>.

=head1 ATTRIBUTES

L<Mojo::Asset> implements the following attributes.

=head2 end_range

  my $end = $asset->end_range;
  $asset  = $asset->end_range(8);

Pretend file ends earlier.

=head2 start_range

  my $start = $asset->start_range;
  $asset    = $asset->start_range(0);

Pretend file starts later.

=head1 METHODS

L<Mojo::Asset> inherits all methods from L<Mojo::EventEmitter> and implements
the following new ones.

=head2 add_chunk

  $asset = $asset->add_chunk('foo bar baz');

Add chunk of data to asset. Meant to be overloaded in a subclass.

=head2 contains

  my $position = $asset->contains('bar');

Check if asset contains a specific string. Meant to be overloaded in a
subclass.

=head2 get_chunk

  my $bytes = $asset->get_chunk($offset);
  my $bytes = $asset->get_chunk($offset, $max);

Get chunk of data starting from a specific position, defaults to a maximum
chunk size of C<131072> bytes. Meant to be overloaded in a subclass.

=head2 is_file

  my $false = $asset->is_file;

False.

=head2 is_range

  my $success = $asset->is_range;

Check if asset has a C<start_range> or C<end_range>.

=head2 move_to

  $asset = $asset->move_to('/home/sri/foo.txt');

Move asset data into a specific file. Meant to be overloaded in a subclass.

=head2 size

  my $size = $asset->size;

Size of asset data in bytes. Meant to be overloaded in a subclass.

=head2 slurp

  my $bytes = $asset->slurp;

Read all asset data at once. Meant to be overloaded in a subclass.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
