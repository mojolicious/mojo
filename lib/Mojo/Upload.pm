# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Upload;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';
use Mojo::Asset::File;
use Mojo::Headers;

__PACKAGE__->attr(asset => sub { Mojo::Asset::File->new });
__PACKAGE__->attr([qw/filename name/]);
__PACKAGE__->attr(headers => sub { Mojo::Headers->new });

# B-6
# You sunk my scrabbleship!
# This game makes no sense.
# Tell that to the good men who just lost their lives... SEMPER-FI!
sub move_to { shift->asset->move_to(@_) }

sub size { shift->asset->size }

sub slurp { shift->asset->slurp }

1;
__END__

=head1 NAME

Mojo::Upload - Upload

=head1 SYNOPSIS

    use Mojo::Upload;

    my $upload = Mojo::Upload->new;
    print $upload->filename;
    $upload->move_to('/foo/bar/baz.txt');

=head1 DESCRIPTION

L<Mojo::Upload> is a container for uploads.

=head1 ATTRIBUTES

L<Mojo::Upload> implements the following attributes.

=head2 C<asset>

    my $asset = $upload->asset;
    $upload   = $upload->asset(Mojo::Asset::File->new);

=head2 C<filename>

    my $filename = $upload->filename;
    $upload      = $upload->filename('foo.txt');

=head2 C<headers>

    my $headers = $upload->headers;
    $upload     = $upload->headers(Mojo::Headers->new);

=head2 C<name>

    my $name = $upload->name;
    $upload  = $upload->name('foo');

=head1 METHODS

L<Mojo::Upload> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<move_to>

    $upload->move_to('/foo/bar/baz.txt');

=head2 C<size>

    my $size = $upload->size;

=head2 C<slurp>

    my $string = $upload->slurp;

=cut
