package Mojo::Collection;
use Mojo::Base -base;
use overload
  'bool'   => sub {1},
  '""'     => sub { shift->join("\n") },
  fallback => 1;

# "Sweet Zombie Jesus!"
use Exporter 'import';
use List::Util;
use Mojo::ByteStream;

our @EXPORT_OK = ('c');

sub new {
  my $class = shift;
  return bless [@_], ref $class || $class;
}

sub c { __PACKAGE__->new(@_) }

sub each {
  my ($self, $cb) = @_;
  return @$self unless $cb;
  my $i = 1;
  $_->$cb($i++) for @$self;
  return $self;
}

sub first {
  my ($self, $cb) = @_;
  return $self->[0] unless $cb;
  return List::Util::first { $_ ~~ $cb } @$self;
}

# "All right, let's not panic.
#  I'll make the money by selling one of my livers.
#  I can get by with one."
sub grep {
  my ($self, $cb) = @_;
  return $self->new(grep { $_ ~~ $cb } @$self);
}

sub join {
  my ($self, $expression) = @_;
  return Mojo::ByteStream->new(join $expression, map({"$_"} @$self));
}

sub map {
  my ($self, $cb) = @_;
  return $self->new(map { $_->$cb } @$self);
}

# "Facts are meaningless.
#  You could use facts to prove anything that's even remotely true!"
sub pluck {
  my ($self, $method, @args) = @_;
  return $self->map(sub { $_->$method(@args) });
}

sub reverse {
  my $self = shift;
  return $self->new(reverse @$self);
}

# "You told Bart to kiss that girl?
#  Why not encourage him to knock her out and drag her to a cave?
#  Second base? Oh, Bart is a little too young for that."
sub shuffle {
  my $self = shift;
  return $self->new(List::Util::shuffle @$self);
}

sub size { scalar @{$_[0]} }

sub slice {
  my $self = shift;
  return $self->new(@$self[@_]);
}

sub sort {
  my ($self, $cb) = @_;
  return $self->new(sort @$self) unless $cb;
  return $self->new(sort { $a->$cb($b) } @$self);
}

sub uniq {
  my $self = shift;
  my %seen;
  return $self->grep(sub { !$seen{$_}++ });
}

1;

=head1 NAME

Mojo::Collection - Collection

=head1 SYNOPSIS

  # Manipulate collections
  use Mojo::Collection;
  my $collection = Mojo::Collection->new(qw(just works));
  unshift @$collection, 'it';
  $collection->map(sub { ucfirst })->each(sub {
    my ($word, $count) = @_;
    say "$count: $word";
  });

  # Use the alternative constructor
  use Mojo::Collection 'c';
  c(qw(a b c))->join('/')->url_escape->say;

=head1 DESCRIPTION

L<Mojo::Collection> is a container for collections.

=head1 FUNCTIONS

L<Mojo::Collection> implements the following functions.

=head2 C<c>

  my $collection = c(1, 2, 3);

Construct a new L<Mojo::Collection> object.

=head1 METHODS

L<Mojo::Collection> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $collection = Mojo::Collection->new(1, 2, 3);

Construct a new array-based L<Mojo::Collection> object.

=head2 C<each>

  my @elements = $collection->each;
  $collection  = $collection->each(sub {...});

Evaluate closure for each element in collection.

  $collection->each(sub {
    my ($e, $count) = @_;
    say "$count: $e";
  });

=head2 C<first>

  my $first = $collection->first;
  my $first = $collection->first(qr/foo/);
  my $first = $collection->first(sub {...});

Evaluate regular expression or closure for each element in collection and
return the first one that matched the regular expression, or for which the
closure returned true.

  my $five = $collection->first(sub { $_ == 5 });

=head2 C<grep>

  my $new = $collection->grep(qr/foo/);
  my $new = $collection->grep(sub {...});

Evaluate regular expression or closure for each element in collection and
create a new collection with all elements that matched the regular expression,
or for which the closure returned true.

  my $interesting = $collection->grep(qr/mojo/i);

=head2 C<join>

  my $stream = $collection->join("\n");

Turn collection into L<Mojo::ByteStream>.

  $collection->join("\n")->say;

=head2 C<map>

  my $new = $collection->map(sub {...});

Evaluate closure for each element in collection and create a new collection
from the results.

  my $doubled = $collection->map(sub { $_ * 2 });

=head2 C<pluck>

  my $new = $collection->pluck($method);
  my $new = $collection->pluck($method, @args);

Call method on each element in collection and create a new collection from the
results.

  # Equal to but more convenient than
  my $new = $collection->map(sub { $_->$method(@args) });

=head2 C<reverse>

  my $new = $collection->reverse;

Create a new collection with all elements in reverse order.

=head2 C<slice>

  my $new = $collection->slice(4 .. 7);

Create a new collection with all selected elements.

=head2 C<shuffle>

  my $new = $collection->shuffle;

Create a new collection with all elements in random order.

=head2 C<size>

  my $size = $collection->size;

Number of elements in collection.

=head2 C<sort>

  my $new = $collection->sort;
  my $new = $collection->sort(sub {...});

Sort elements based on return value of closure and create a new collection
from the results.

  my $insensitive = $collection->sort(sub { uc(shift) cmp uc(shift) });

=head2 C<uniq>

  my $new = $collection->uniq;

Create a new collection without duplicate elements.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
