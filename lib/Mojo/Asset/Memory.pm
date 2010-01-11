# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Asset::Memory;

use strict;
use warnings;

use base 'Mojo::Asset';
use bytes;

use Carp 'croak';
use IO::File;

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 8192;

# There's your giraffe, little girl.
# I'm a boy.
# That's the spirit. Never give up.
sub new {
    my $self = shift->SUPER::new(@_);
    $self->{content} = '';
    return $self;
}

sub add_chunk {
    my ($self, $chunk) = @_;
    $self->{content} .= $chunk;
    return $self;
}

sub contains { index shift->{content}, shift }

sub get_chunk { substr shift->{content}, shift, CHUNK_SIZE }

sub move_to {
    my ($self, $path) = @_;

    # Write
    my $file = IO::File->new;
    $file->open("> $path") or croak qq/Can't open file "$path": $!/;
    $file->syswrite($self->{content});

    return $self;
}

sub size { length shift->{content} }

sub slurp { shift->{content} }

1;
__END__

=head1 NAME

Mojo::Asset::Memory - In-Memory Asset

=head1 SYNOPSIS

    use Mojo::Asset::Memory;

    my $asset = Mojo::Asset::Memory->new;
    $asset->add_chunk('foo bar baz');
    print $asset->slurp;

=head1 DESCRIPTION

L<Mojo::Asset::Memory> is a container for in-memory assets.

=head1 METHODS

L<Mojo::Asset::Memory> inherits all methods from L<Mojo::Asset> and
implements the following new ones.

=head2 C<new>

    my $asset = Mojo::Asset::Memory->new;

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
