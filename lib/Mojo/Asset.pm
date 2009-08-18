# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Asset;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';

# Marge, it takes two to lie. One to lie and one to listen.
sub add_chunk { croak 'Method "add_chunk" not implemented by subclass' }
sub contains  { croak 'Method "contains" not implemented by subclass' }
sub get_chunk { croak 'Method "get_chunk" not implemented by subclass' }
sub move_to   { croak 'Method "move_to" not implemented by subclass' }
sub size      { croak 'Method "size" not implemented by subclass' }
sub slurp     { croak 'Method "slurp" not implemented by subclass' }

1;
__END__

=head1 NAME

Mojo::Asset - Asset Base Class

=head1 SYNOPSIS

    use base 'Mojo::Asset';

=head1 DESCRIPTION

L<Mojo::Asset> is a asset base class.

=head1 METHODS

L<Mojo::Asset> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<add_chunk>

    $asset = $asset->add_chunk('foo bar baz');

=head2 C<contains>

    my $position = $asset->contains('bar');

=head2 C<get_chunk>

    my $chunk = $asset->get_chunk($offset);

=head2 C<move_to>

    $asset = $asset->move_to('/foo/bar/baz.txt');

=head2 C<size>

    my $size = $asset->size;

=head2 C<slurp>

    my $string = $file->slurp;

=cut
