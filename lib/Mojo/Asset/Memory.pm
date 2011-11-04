package Mojo::Asset::Memory;
use Mojo::Base 'Mojo::Asset';

use Carp 'croak';
use IO::File;
use Mojo::Asset::File;

has max_memory_size => sub { $ENV{MOJO_MAX_MEMORY_SIZE} || 262144 };

# "There's your giraffe, little girl.
#  I'm a boy.
#  That's the spirit. Never give up."
sub new {
  my $self = shift->SUPER::new(@_);
  $self->{content} = '';
  return $self;
}

sub add_chunk {
  my ($self, $chunk) = @_;
  $self->{content} .= $chunk if defined $chunk;
  return Mojo::Asset::File->new->add_chunk($self->slurp)
    if $self->size > $self->max_memory_size;
  return $self;
}

sub contains {
  my $self = shift;

  my $start = $self->start_range;
  my $pos = index $self->{content}, shift, $start;
  $pos -= $start if $start && $pos >= 0;
  my $end = $self->end_range;

  return -1 if $end && $pos >= $end;
  return $pos;
}

sub get_chunk {
  my ($self, $start) = @_;

  $start += $self->start_range;
  my $size = $ENV{MOJO_CHUNK_SIZE} || 131072;
  if (my $end = $self->end_range) {
    $size = $end + 1 - $start if ($start + $size) > $end;
  }

  return substr shift->{content}, $start, $size;
}

sub move_to {
  my ($self, $path) = @_;
  croak qq/Can't open file "$path": $!/
    unless my $file = IO::File->new("> $path");
  $file->syswrite($self->{content});
  return $self;
}

sub size { length shift->{content} }

sub slurp { shift->{content} }

1;
__END__

=head1 NAME

Mojo::Asset::Memory - In-memory storage for HTTP 1.1 content

=head1 SYNOPSIS

  use Mojo::Asset::Memory;

  my $mem = Mojo::Asset::Memory->new;
  $mem->add_chunk('foo bar baz');
  say $mem->slurp;

=head1 DESCRIPTION

L<Mojo::Asset::Memory> is an in-memory storage backend for HTTP 1.1 content.

=head1 ATTRIBUTES

L<Mojo::Asset::Memory> inherits all attributes from L<Mojo::Asset> and
implements the following new ones.

=head2 C<max_memory_size>

  my $size = $mem->max_memory_size;
  $mem     = $mem->max_memory_size(1024);

Maximum asset size in bytes, only attempt upgrading to a L<Mojo::Asset::File>
object after reaching this limit, defaults to the value of
C<MOJO_MAX_MEMORY_SIZE> or C<262144>.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojo::Asset::Memory> inherits all methods from L<Mojo::Asset> and
implements the following new ones.

=head2 C<new>

  my $mem = Mojo::Asset::Memory->new;

Construct a new L<Mojo::Asset::Memory> object.

=head2 C<add_chunk>

  $mem     = $mem->add_chunk('foo bar baz');
  my $file = $mem->add_chunk('abc' x 262144);

Add chunk of data and upgrade to L<Mojo::Asset::File> object if necessary.

=head2 C<contains>

  my $position = $mem->contains('bar');

Check if asset contains a specific string.

=head2 C<get_chunk>

  my $chunk = $mem->get_chunk($offset);

Get chunk of data starting from a specific position.

=head2 C<move_to>

  $mem = $mem->move_to('/foo/bar/baz.txt');

Move asset data into a specific file.

=head2 C<size>

  my $size = $mem->size;

Size of asset data in bytes.

=head2 C<slurp>

  my $string = mem->slurp;

Read all asset data at once.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
