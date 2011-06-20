package Mojo::Asset::Memory;
use Mojo::Base 'Mojo::Asset';

use Carp 'croak';
use IO::File;

# "There's your giraffe, little girl.
#  I'm a boy.
#  That's the spirit. Never give up."
sub new {
  my $self = shift->SUPER::new(@_);
  $self->{content} = '';
  $self;
}

sub add_chunk {
  my ($self, $chunk) = @_;
  utf8::encode $chunk if utf8::is_utf8 $chunk;
  $self->{content} .= $chunk if defined $chunk;
  $self;
}

sub contains {
  my $self = shift;

  my $start = $self->start_range;
  my $pos = index $self->{content}, shift, $start;
  $pos -= $start if $start && $pos >= 0;
  my $end = $self->end_range;

  return -1 if $end && $pos >= $end;
  $pos;
}

sub get_chunk {
  my ($self, $start) = @_;

  $start += $self->start_range;
  my $size = $ENV{MOJO_CHUNK_SIZE} || 131072;
  if (my $end = $self->end_range) {
    $size = $end + 1 - $start if ($start + $size) > $end;
  }

  substr shift->{content}, $start, $size;
}

sub move_to {
  my ($self, $path) = @_;
  my $file = IO::File->new;
  $file->open("> $path") or croak qq/Can't open file "$path": $!/;
  $file->syswrite($self->{content});
  $self;
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

Construct a new L<Mojo::Asset::Memory> object.

=head2 C<add_chunk>

  $asset = $asset->add_chunk('foo bar baz');

Add chunk of data to asset.

=head2 C<contains>

  my $position = $asset->contains('bar');

Check if asset contains a specific string.

=head2 C<get_chunk>

  my $chunk = $asset->get_chunk($offset);

Get chunk of data starting from a specific position.

=head2 C<move_to>

  $asset = $asset->move_to('/foo/bar/baz.txt');

Move asset data into a specific file.

=head2 C<size>

  my $size = $asset->size;

Size of asset data in bytes.

=head2 C<slurp>

  my $string = $file->slurp;

Read all asset data at once.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
