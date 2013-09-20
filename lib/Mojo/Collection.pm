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

  my ($package, $method) = our $AUTOLOAD =~ /^([\w:]+)::(\w+)$/;
  croak "Undefined subroutine &${package}::$method called"
    unless blessed $self && $self->isa(__PACKAGE__);

  croak qq{Can't locate object method "$method" via package "$package"}
    unless @$self;
  return $self->pluck($method, @_);
}

sub DESTROY { }

sub new {
  my $class = shift;
  return bless [@_], ref $class || $class;
}

sub c { __PACKAGE__->new(@_) }

sub compact {
  shift->grep(sub { length($_ // '') });
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

sub join { Mojo::ByteStream->new(join $_[1], map({"$_"} @{$_[0]})) }

sub map {
  my ($self, $cb) = @_;
  return $self->new(map { $_->$cb } @$self);
}

sub pluck {
  my ($self, $method, @args) = @_;
  return $self->map(sub { $_->$method(@args) });
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
  return $self->new($cb ? sort { $a->$cb($b) } @$self : sort @$self);
}

sub tap { shift->Mojo::Base::tap(@_) }

sub uniq {
  my $self = shift;
  my %seen;
  return $self->grep(sub { !$seen{$_}++ });
}

sub _flatten {
  map { _ref($_) ? _flatten(@$_) : $_ } @_;
}

sub _ref { defined $_[0] && (ref $_[0] eq 'ARRAY' || $_[0]->isa(__PACKAGE__)) }

1;

=encoding utf8

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

=head2 c

  my $collection = c(1, 2, 3);

Construct a new array-based L<Mojo::Collection> object.

=head1 METHODS

L<Mojo::Collection> implements the following methods.

=head2 new

  my $collection = Mojo::Collection->new(1, 2, 3);

Construct a new array-based L<Mojo::Collection> object.

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

  my $five = $collection->first(sub { $_ == 5 });

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

  my $interesting = $collection->grep(qr/mojo/i);

=head2 join

  my $stream = $collection->join("\n");

Turn collection into L<Mojo::ByteStream>.

  $collection->join("\n")->say;

=head2 map

  my $new = $collection->map(sub {...});

Evaluate callback for each element in collection and create a new collection
from the results. The element will be the first argument passed to the
callback and is also available as C<$_>.

  my $doubled = $collection->map(sub { $_ * 2 });

=head2 pluck

  my $new = $collection->pluck($method);
  my $new = $collection->pluck($method, @args);

Call method on each element in collection and create a new collection from the
results.

  # Equal to but more convenient than
  my $new = $collection->map(sub { $_->$method(@args) });

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

  my $insensitive = $collection->sort(sub { uc(shift) cmp uc(shift) });

=head2 tap

  $collection = $collection->tap(sub {...});

Alias for L<Mojo::Base/"tap">.

=head2 uniq

  my $new = $collection->uniq;

Create a new collection without duplicate elements.

=head1 ELEMENT METHODS

In addition to the methods above, you can also call methods provided by all
elements in the collection directly and create a new collection from the
results, similar to C<pluck>.

  push @$collection, Mojo::ByteStream->new("/home/sri/$_.txt") for 1 .. 9;
  say $collection->slurp->b64_encode('');

=head1 ELEMENTS

Direct array reference access to elements is also possible.

  say $collection->[23];
  say for @$collection;

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
