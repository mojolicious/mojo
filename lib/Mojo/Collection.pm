package Mojo::Collection;
use Mojo::Base -strict;

use re qw(is_regexp);
use Carp qw(croak);
use Exporter qw(import);
use List::Util;
use Mojo::ByteStream;
use Scalar::Util qw(blessed);

our @EXPORT_OK = ('c');

sub TO_JSON { [@{shift()}] }

sub c { __PACKAGE__->new(@_) }

sub compact {
  my $self = shift;
  return $self->new(grep { defined && (ref || length) } @$self);
}

sub each {
  my ($self, $cb) = @_;
  return @$self unless $cb;
  my $i = 1;
  $_->$cb($i++) for @$self;
  return $self;
}

sub first {
  my ($self, $cb) = (shift, shift);
  return $self->[0] unless $cb;
  return List::Util::first { $_ =~ $cb } @$self if is_regexp $cb;
  return List::Util::first { $_->$cb(@_) } @$self;
}

sub flatten { $_[0]->new(_flatten(@{$_[0]})) }

sub grep {
  my ($self, $cb) = (shift, shift);
  return $self->new(grep { $_ =~ $cb } @$self) if is_regexp $cb;
  return $self->new(grep { $_->$cb(@_) } @$self);
}

sub head {
  my ($self, $size) = @_;
  return $self->new(@$self)                   if $size > @$self;
  return $self->new(@$self[0 .. ($size - 1)]) if $size >= 0;
  return $self->new(@$self[0 .. ($#$self + $size)]);
}

sub join {
  Mojo::ByteStream->new(join $_[1] // '', map {"$_"} @{$_[0]});
}

sub last { shift->[-1] }

sub map {
  my ($self, $cb) = (shift, shift);
  return $self->new(map { $_->$cb(@_) } @$self);
}

sub new {
  my $class = shift;
  return bless [@_], ref $class || $class;
}

sub reduce {
  my $self = shift;
  @_ = (@_, @$self);
  goto &List::Util::reduce;
}

sub reverse { $_[0]->new(reverse @{$_[0]}) }

sub shuffle { $_[0]->new(List::Util::shuffle @{$_[0]}) }

sub size { scalar @{$_[0]} }

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

sub tail {
  my ($self, $size) = @_;
  return $self->new(@$self)                                     if $size > @$self;
  return $self->new(@$self[($#$self - ($size - 1)) .. $#$self]) if $size >= 0;
  return $self->new(@$self[(0 - $size) .. $#$self]);
}

sub tap { shift->Mojo::Base::tap(@_) }

sub to_array { [@{shift()}] }

sub uniq {
  my ($self, $cb) = (shift, shift);
  my %seen;
  return $self->new(grep { !$seen{$_->$cb(@_) // ''}++ } @$self) if $cb;
  return $self->new(grep { !$seen{$_ // ''}++ } @$self);
}

sub with_roles { shift->Mojo::Base::with_roles(@_) }

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
  say $collection->join("\n");

  # Chain methods
  $collection->map(sub { ucfirst })->shuffle->each(sub ($word, $num) {
    say "$num: $word";
  });

  # Use the alternative constructor
  use Mojo::Collection qw(c);
  c(qw(a b c))->join('/')->url_escape->say;

=head1 DESCRIPTION

L<Mojo::Collection> is an array-based container for collections.

  # Access array directly to manipulate collection
  my $collection = Mojo::Collection->new(1 .. 25);
  $collection->[23] += 100;
  say for @$collection;

=head1 FUNCTIONS

L<Mojo::Collection> implements the following functions, which can be imported individually.

=head2 c

  my $collection = c(1, 2, 3);

Construct a new array-based L<Mojo::Collection> object.

=head1 METHODS

L<Mojo::Collection> implements the following methods.

=head2 TO_JSON

  my $array = $collection->TO_JSON;

Alias for L</"to_array">.

=head2 compact

  my $new = $collection->compact;

Create a new collection with all elements that are defined and not an empty string.

  # "0, 1, 2, 3"
  c(0, 1, undef, 2, '', 3)->compact->join(', ');

=head2 each

  my @elements = $collection->each;
  $collection  = $collection->each(sub {...});

Evaluate callback for each element in collection, or return all elements as a list if none has been provided. The
element will be the first argument passed to the callback, and is also available as C<$_>.

  # Make a numbered list
  $collection->each(sub ($e, $num) {
    say "$num: $e";
  });

=head2 first

  my $first = $collection->first;
  my $first = $collection->first(qr/foo/);
  my $first = $collection->first(sub {...});
  my $first = $collection->first('some_method');
  my $first = $collection->first('some_method', @args);

Evaluate regular expression/callback for, or call method on, each element in collection and return the first one that
matched the regular expression, or for which the callback/method returned true. The element will be the first argument
passed to the callback, and is also available as C<$_>.

  # Longer version
  my $first = $collection->first(sub { $_->some_method(@args) });

  # Find first value that contains the word "mojo"
  my $interesting = $collection->first(qr/mojo/i);

  # Find first value that is greater than 5
  my $greater = $collection->first(sub { $_ > 5 });

=head2 flatten

  my $new = $collection->flatten;

Flatten nested collections/arrays recursively and create a new collection with all elements.

  # "1, 2, 3, 4, 5, 6, 7"
  c(1, [2, [3, 4], 5, [6]], 7)->flatten->join(', ');

=head2 grep

  my $new = $collection->grep(qr/foo/);
  my $new = $collection->grep(sub {...});
  my $new = $collection->grep('some_method');
  my $new = $collection->grep('some_method', @args);

Evaluate regular expression/callback for, or call method on, each element in collection and create a new collection
with all elements that matched the regular expression, or for which the callback/method returned true. The element will
be the first argument passed to the callback, and is also available as C<$_>.

  # Longer version
  my $new = $collection->grep(sub { $_->some_method(@args) });

  # Find all values that contain the word "mojo"
  my $interesting = $collection->grep(qr/mojo/i);

  # Find all values that are greater than 5
  my $greater = $collection->grep(sub { $_ > 5 });

=head2 head

  my $new = $collection->head(4);
  my $new = $collection->head(-2);

Create a new collection with up to the specified number of elements from the beginning of the collection. A negative
number will count from the end.

  # "A B C"
  c('A', 'B', 'C', 'D', 'E')->head(3)->join(' ');

  # "A B"
  c('A', 'B', 'C', 'D', 'E')->head(-3)->join(' ');

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
  my $new = $collection->map('some_method');
  my $new = $collection->map('some_method', @args);

Evaluate callback for, or call method on, each element in collection and create a new collection from the results. The
element will be the first argument passed to the callback, and is also available as C<$_>.

  # Longer version
  my $new = $collection->map(sub { $_->some_method(@args) });

  # Append the word "mojo" to all values
  my $mojoified = $collection->map(sub { $_ . 'mojo' });

=head2 new

  my $collection = Mojo::Collection->new(1, 2, 3);

Construct a new array-based L<Mojo::Collection> object.

=head2 reduce

  my $result = $collection->reduce(sub {...});
  my $result = $collection->reduce(sub {...}, $initial);

Reduce elements in collection with a callback and return its final result, setting C<$a> and C<$b> each time the
callback is executed. The first time C<$a> will be set to an optional initial value or the first element in the
collection. And from then on C<$a> will be set to the return value of the callback, while C<$b> will always be set to
the next element in the collection.

  # Calculate the sum of all values
  my $sum = $collection->reduce(sub { $a + $b });

  # Count how often each value occurs in collection
  my $hash = $collection->reduce(sub { $a->{$b}++; $a }, {});

=head2 reverse

  my $new = $collection->reverse;

Create a new collection with all elements in reverse order.

=head2 shuffle

  my $new = $collection->shuffle;

Create a new collection with all elements in random order.

=head2 size

  my $size = $collection->size;

Number of elements in collection.

=head2 sort

  my $new = $collection->sort;
  my $new = $collection->sort(sub {...});

Sort elements based on return value of a callback and create a new collection from the results, setting C<$a> and C<$b>
to the elements being compared, each time the callback is executed.

  # Sort values case-insensitive
  my $case_insensitive = $collection->sort(sub { uc($a) cmp uc($b) });

=head2 tail

  my $new = $collection->tail(4);
  my $new = $collection->tail(-2);

Create a new collection with up to the specified number of elements from the end of the collection. A negative number
will count from the beginning.

  # "C D E"
  c('A', 'B', 'C', 'D', 'E')->tail(3)->join(' ');

  # "D E"
  c('A', 'B', 'C', 'D', 'E')->tail(-3)->join(' ');

=head2 tap

  $collection = $collection->tap(sub {...});

Alias for L<Mojo::Base/"tap">.

=head2 to_array

  my $array = $collection->to_array;

Turn collection into array reference.

=head2 uniq

  my $new = $collection->uniq;
  my $new = $collection->uniq(sub {...});
  my $new = $collection->uniq('some_method');
  my $new = $collection->uniq('some_method', @args);

Create a new collection without duplicate elements, using the string representation of either the elements or the
return value of the callback/method to decide uniqueness. Note that C<undef> and empty string are treated the same.

  # Longer version
  my $new = $collection->uniq(sub { $_->some_method(@args) });

  # "foo bar baz"
  c('foo', 'bar', 'bar', 'baz')->uniq->join(' ');

  # "[[1, 2], [2, 1]]"
  c([1, 2], [2, 1], [3, 2])->uniq(sub{ $_->[1] })->to_array;

=head2 with_roles

  my $new_class = Mojo::Collection->with_roles('Mojo::Collection::Role::One');
  my $new_class = Mojo::Collection->with_roles('+One', '+Two');
  $collection   = $collection->with_roles('+One', '+Two');

Alias for L<Mojo::Base/"with_roles">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
