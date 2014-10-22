package Mojo::Collection;
use Mojo::Base -strict;
use overload bool => sub {1}, '""' => sub { shift->join("\n") }, fallback => 1;

use Carp 'croak';
use Exporter 'import';
use List::Util;
use Mojo::ByteStream;
use Scalar::Util 'blessed';

our @EXPORT_OK = ('c');

sub AUTOLOAD {
  my $self = shift;
  my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;
  croak "Undefined subroutine &${package}::$method called"
    unless blessed $self && $self->isa(__PACKAGE__);
  return $self->pluck($method, @_);
}

sub DESTROY { }

sub c { __PACKAGE__->new(@_) }

sub compact {
  $_[0]->new(grep { defined && (ref || length) } @{$_[0]});
}

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
  return List::Util::first { $cb->($_) } @$self if ref $cb eq 'CODE';
  return List::Util::first { $_ =~ $cb } @$self;
}

sub flatten { $_[0]->new(_flatten(@{$_[0]})) }

sub grep {
  my ($self, $cb) = @_;
  return $self->new(grep { $cb->($_) } @$self) if ref $cb eq 'CODE';
  return $self->new(grep { $_ =~ $cb } @$self);
}

sub join {
  Mojo::ByteStream->new(join $_[1] // '', map {"$_"} @{$_[0]});
}

sub last { shift->[-1] }

sub map {
  my ($self, $cb) = @_;
  return $self->new(map { $_->$cb } @$self);
}

sub new {
  my $class = shift;
  return bless [@_], ref $class || $class;
}

sub pluck {
  my ($self, $key) = (shift, shift);
  return $self->new(map { ref eq 'HASH' ? $_->{$key} : $_->$key(@_) } @$self);
}

sub reduce {
  my $self = shift;
  @_ = (@_, @$self);
  goto &List::Util::reduce;
}

sub reverse { $_[0]->new(reverse @{$_[0]}) }

sub shuffle { $_[0]->new(List::Util::shuffle @{$_[0]}) }

sub size { scalar @{$_[0]} }

sub slice {
  my $self = shift;
  return $self->new(@$self[@_]);
}

sub sort {
  my ($self, $cb) = @_;

  return $self->new(sort @$self) unless $cb;

  my $caller = caller;
  no strict 'refs';
  my @sorted = sort {
    local (*{"${caller}::a"}, *{"${caller}::b"}) = (\$a, \$b);
    $a->$cb($b);
  } @$self;
  return $self->new(@sorted);
}

sub tap { shift->Mojo::Base::tap(@_) }

sub uniq {
  my %seen;
  return $_[0]->new(grep { !$seen{$_}++ } @{$_[0]});
}

sub _flatten {
  map { _ref($_) ? _flatten(@$_) : $_ } @_;
}

sub _ref { ref $_[0] eq 'ARRAY' || blessed $_[0] && $_[0]->isa(__PACKAGE__) }

1;

=encoding utf8

=head1 NAME

Mojo::Collection - Collection

=head1 SYNOPSIS

  use Mojo::Collection;

  # Manipulate collection
  my $collection = Mojo::Collection->new(qw(just works));
  unshift @$collection, 'it';

  # Chain methods
  $collection->map(sub { ucfirst })->shuffle->each(sub {
    my ($word, $count) = @_;
    say "$count: $word";
  });

  # Stringify collection
  say $collection->join("\n");
  say "$collection";

  # Use the alternative constructor
  use Mojo::Collection 'c';
  c(qw(a b c))->join('/')->url_escape->say;

=head1 DESCRIPTION

L<Mojo::Collection> is an array-based container for collections.

  # Access array directly to manipulate collection
  my $collection = Mojo::Collection->new(1 .. 25);
  $collection->[23] += 100;
  say for @$collection;

=head1 FUNCTIONS

L<Mojo::Collection> implements the following functions, which can be imported
individually.

=head2 c

  my $collection = c(1, 2, 3);

Construct a new array-based L<Mojo::Collection> object.

=head1 METHODS

L<Mojo::Collection> implements the following methods.

=head2 compact

  my $new = $collection->compact;

Create a new collection with all elements that are defined and not an empty
string.

=head2 each

  my @elements = $collection->each;
  $collection  = $collection->each(sub {...});

Evaluate callback for each element in collection or return all elements as a
list if none has been provided. The element will be the first argument passed
to the callback and is also available as C<$_>.

  # Make a numbered list
  $collection->each(sub {
    my ($e, $count) = @_;
    say "$count: $e";
  });

=head2 first

  my $first = $collection->first;
  my $first = $collection->first(qr/foo/);
  my $first = $collection->first(sub {...});

Evaluate regular expression or callback for each element in collection and
return the first one that matched the regular expression, or for which the
callback returned true. The element will be the first argument passed to the
callback and is also available as C<$_>.

  # Find first value that is greater than 5
  my $greater = $collection->first(sub { $_ > 5 });

=head2 flatten

  my $new = $collection->flatten;

Flatten nested collections/arrays recursively and create a new collection with
all elements.

=head2 grep

  my $new = $collection->grep(qr/foo/);
  my $new = $collection->grep(sub {...});

Evaluate regular expression or callback for each element in collection and
create a new collection with all elements that matched the regular expression,
or for which the callback returned true. The element will be the first
argument passed to the callback and is also available as C<$_>.

  # Find all values that contain the word "mojo"
  my $interesting = $collection->grep(qr/mojo/i);

=head2 join

  my $stream = $collection->join;
  my $stream = $collection->join("\n");

Turn collection into L<Mojo::ByteStream>.

  # Join all values with commas
  $collection->join(', ')->say;

=head2 last

  my $last = $collection->last;

Return the last element in collection.

=head2 map

  my $new = $collection->map(sub {...});

Evaluate callback for each element in collection and create a new collection
from the results. The element will be the first argument passed to the
callback and is also available as C<$_>.

  # Append the word "mojo" to all values
  my $mojoified = $collection->map(sub { $_ . 'mojo' });

=head2 new

  my $collection = Mojo::Collection->new(1, 2, 3);

Construct a new array-based L<Mojo::Collection> object.

=head2 pluck

  my $new = $collection->pluck($key);
  my $new = $collection->pluck($method);
  my $new = $collection->pluck($method, @args);

Extract hash reference value from, or call method on, each element in
collection and create a new collection from the results.

  # Longer version
  my $new = $collection->map(sub { $_->{$key} });
  my $new = $collection->map(sub { $_->$method(@args) });

=head2 reduce

  my $result = $collection->reduce(sub {...});
  my $result = $collection->reduce(sub {...}, $initial);

Reduce elements in collection with callback, the first element will be used as
initial value if none has been provided.

  # Calculate the sum of all values
  my $sum = $collection->reduce(sub { $a + $b });

  # Count how often each value occurs in collection
  my $hash = $collection->reduce(sub { $a->{$b}++; $a }, {});

=head2 reverse

  my $new = $collection->reverse;

Create a new collection with all elements in reverse order.

=head2 slice

  my $new = $collection->slice(4 .. 7);

Create a new collection with all selected elements.

=head2 shuffle

  my $new = $collection->shuffle;

Create a new collection with all elements in random order.

=head2 size

  my $size = $collection->size;

Number of elements in collection.

=head2 sort

  my $new = $collection->sort;
  my $new = $collection->sort(sub {...});

Sort elements based on return value of callback and create a new collection
from the results.

  # Sort values case insensitive
  my $insensitive = $collection->sort(sub { uc($a) cmp uc($b) });

=head2 tap

  $collection = $collection->tap(sub {...});

Alias for L<Mojo::Base/"tap">.

=head2 uniq

  my $new = $collection->uniq;

Create a new collection without duplicate elements.

=head1 AUTOLOAD

In addition to the L</"METHODS"> above, you can also call methods provided by
all elements in the collection directly and create a new collection from the
results, similar to L</"pluck">.

  # "<h2>Test1</h2><h2>Test2</h2>"
  my $collection = Mojo::Collection->new(
    Mojo::DOM->new("<h1>1</h1>"), Mojo::DOM->new("<h1>2</h1>"));
  $collection->at('h1')->type('h2')->prepend_content('Test')->join;

=head1 OPERATORS

L<Mojo::Collection> overloads the following operators.

=head2 bool

  my $bool = !!$collection;

Always true.

=head2 stringify

  my $str = "$collection";

Stringify elements in collection and L</"join"> them with newlines.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
