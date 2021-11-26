package Mojo::Asset::Memory;
use Mojo::Base 'Mojo::Asset';

use Mojo::Asset::File;
use Mojo::File qw(path);

has 'auto_upgrade';
has max_memory_size => sub { $ENV{MOJO_MAX_MEMORY_SIZE} || 262144 };
has mtime           => sub {$^T};

sub add_chunk {
  my ($self, $chunk) = @_;

  # Upgrade if necessary
  $self->{content} .= $chunk;
  return $self if !$self->auto_upgrade || $self->size <= $self->max_memory_size;
  $self->emit(upgrade => my $file = Mojo::Asset::File->new);
  return $file->add_chunk($self->slurp);
}

sub contains {
  my ($self, $str) = @_;

  my $start = $self->start_range;
  my $pos   = index $self->{content} // '', $str, $start;
  $pos -= $start if $start && $pos >= 0;
  my $end = $self->_end_range(0);

  return $end && ($pos + length $str) >= $end ? -1 : $pos;
}

sub get_chunk {
  my ($self, $offset, $max) = @_;
  $max //= 131072;

  $offset += $self->start_range;
  if (my $end = $self->end_range) { $max = $end + 1 - $offset if ($offset + $max) > $end }

  return substr shift->{content} // '', $offset, $max;
}

sub move_to { path($_[1])->spurt($_[0]{content} // '') and return $_[0] }

sub size {
  my $self = shift;
  return length($self->{content} // '') unless $self->is_range;
  return $self->_end_range(-1) - $self->start_range + 1;
}

sub slurp { shift->{content} // '' }

sub to_file { Mojo::Asset::File->new->add_chunk(shift->slurp) }

sub _end_range {
  my $self = shift;
  return undef unless $self->is_range;
  return $self->end_range || shift() + length($self->{content} // '');
}
1;

=encoding utf8

=head1 NAME

Mojo::Asset::Memory - In-memory storage for HTTP content

=head1 SYNOPSIS

  use Mojo::Asset::Memory;

  my $mem = Mojo::Asset::Memory->new;
  $mem->add_chunk('foo bar baz');
  say $mem->slurp;

=head1 DESCRIPTION

L<Mojo::Asset::Memory> is an in-memory storage backend for HTTP content.

=head1 EVENTS

L<Mojo::Asset::Memory> inherits all events from L<Mojo::Asset> and can emit the following new ones.

=head2 upgrade

  $mem->on(upgrade => sub ($mem, $file) {...});

Emitted when asset gets upgraded to a L<Mojo::Asset::File> object.

  $mem->on(upgrade => sub ($mem, $file) { $file->tmpdir('/tmp') });

=head1 ATTRIBUTES

L<Mojo::Asset::Memory> inherits all attributes from L<Mojo::Asset> and implements the following new ones.

=head2 auto_upgrade

  my $bool = $mem->auto_upgrade;
  $mem     = $mem->auto_upgrade($bool);

Try to detect if content size exceeds L</"max_memory_size"> limit and automatically upgrade to a L<Mojo::Asset::File>
object.

=head2 max_memory_size

  my $size = $mem->max_memory_size;
  $mem     = $mem->max_memory_size(1024);

Maximum size in bytes of data to keep in memory before automatically upgrading to a L<Mojo::Asset::File> object,
defaults to the value of the C<MOJO_MAX_MEMORY_SIZE> environment variable or C<262144> (256KiB).

=head2 mtime

  my $mtime = $mem->mtime;
  $mem      = $mem->mtime(1408567500);

Modification time of asset, defaults to the value of C<$^T>.

=head1 METHODS

L<Mojo::Asset::Memory> inherits all methods from L<Mojo::Asset> and implements the following new ones.

=head2 add_chunk

  $mem     = $mem->add_chunk('foo bar baz');
  my $file = $mem->add_chunk('abc' x 262144);

Add chunk of data and upgrade to L<Mojo::Asset::File> object if necessary.

=head2 contains

  my $position = $mem->contains('bar');

Check if asset contains a specific string.

=head2 get_chunk

  my $bytes = $mem->get_chunk($offset);
  my $bytes = $mem->get_chunk($offset, $max);

Get chunk of data starting from a specific position, defaults to a maximum chunk size of C<131072> bytes (128KiB).

=head2 move_to

  $mem = $mem->move_to('/home/sri/foo.txt');

Move asset data into a specific file.

=head2 size

  my $size = $mem->size;

Size of asset data in bytes. If <Mojo::Asset/"is_range"> is true, the size is that of the range.

=head2 slurp

  my $bytes = $mem->slurp;

Read all asset data at once.

=head2 to_file

  my $file = $mem->to_file;

Convert asset to L<Mojo::Asset::File> object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
