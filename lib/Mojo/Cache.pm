package Mojo::Cache;
use Mojo::Base -base;

has 'max_keys' => 100;

# "Maybe I should hook up with you guys.
#  After all, how long do any of us have to live?
#  Well, if you like the ribwich, not very.
#  *holds up ribwich box with Krusty saying 'WILL CAUSE EARLY DEATH'*
#  D'oh!"
sub get { (shift->{_cache} || {})->{shift()} }

sub set {
  my ($self, $key, $value) = @_;

  # Keys
  my $keys = $self->max_keys;

  # Cache
  my $cache = $self->{_cache} ||= {};

  # Stack
  my $stack = $self->{_stack} ||= [];

  # Limit
  delete $cache->{shift @$stack} while @$stack >= $keys;

  # Add
  push @$stack, $key;
  $cache->{$key} = $value;

  return $self;
}

1;
__END__

=head1 NAME

Mojo::Cache - Naive In-Memory Cache

=head1 SYNOPSIS

  use Mojo::Cache;

  my $cache = Mojo::Cache->new(max_keys => 50);
  $cache->set(foo => 'bar');
  my $foo = $cache->get('foo');

=head1 DESCRIPTION

L<Mojo::Cache> is a naive in-memory cache with size limits.

Note that this module is EXPERIMENTAL and might change without warning!

=head1 ATTRIBUTES

L<Mojo::Cache> implements the following attributes.

=head2 C<max_keys>

  my $max_keys = $cache->max_keys;
  $cache       = $cache->max_keys(50);

Maximum number of cache keys, defaults to C<100>.

=head1 METHODS

L<Mojo::Cache> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<get>

  my $value = $cache->get('foo');

Get cached value.

=head2 C<set>

  $cache = $cache->set(foo => 'bar');

Set cached value.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
