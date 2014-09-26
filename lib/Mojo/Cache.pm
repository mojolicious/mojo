package Mojo::Cache;
use Mojo::Base -base;

has 'max_keys' => 100;

sub get { (shift->{cache} || {})->{shift()} }

sub set {
  my ($self, $key, $value) = @_;

  return $self unless (my $max = $self->max_keys) > 0;

  my $cache = $self->{cache} ||= {};
  my $queue = $self->{queue} ||= [];
  delete $cache->{shift @$queue} while @$queue >= $max;
  push @$queue, $key unless exists $cache->{$key};
  $cache->{$key} = $value;

  return $self;
}

1;

=encoding utf8

=head1 NAME

Mojo::Cache - Naive in-memory cache

=head1 SYNOPSIS

  use Mojo::Cache;

  my $cache = Mojo::Cache->new(max_keys => 50);
  $cache->set(foo => 'bar');
  my $foo = $cache->get('foo');

=head1 DESCRIPTION

L<Mojo::Cache> is a naive in-memory cache with size limits.

=head1 ATTRIBUTES

L<Mojo::Cache> implements the following attributes.

=head2 max_keys

  my $max = $cache->max_keys;
  $cache  = $cache->max_keys(50);

Maximum number of cache keys, defaults to C<100>. Setting the value to C<0>
will disable caching.

=head1 METHODS

L<Mojo::Cache> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 get

  my $value = $cache->get('foo');

Get cached value.

=head2 set

  $cache = $cache->set(foo => 'bar');

Set cached value.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
