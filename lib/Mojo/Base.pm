package Mojo::Base;

use strict;
use warnings;
use utf8;
use feature ();

# No imports because we get subclassed, a lot!
use Carp ();

# Only Perl 5.14+ requires it on demand
use IO::Handle ();

# Supported on Perl 5.22+
my $NAME
  = eval { require Sub::Util; Sub::Util->can('set_subname') } || sub { $_[1] };

# Protect subclasses using AUTOLOAD
sub DESTROY { }

# Declared here to avoid circular require problems in Mojo::Util
sub _monkey_patch {
  my ($class, %patch) = @_;
  no strict 'refs';
  no warnings 'redefine';
  *{"${class}::$_"} = $NAME->("${class}::$_", $patch{$_}) for keys %patch;
}

sub attr {
  my ($self, $attrs, $value) = @_;
  return unless (my $class = ref $self || $self) && $attrs;

  Carp::croak 'Default has to be a code reference or constant value'
    if ref $value && ref $value ne 'CODE';

  for my $attr (@{ref $attrs eq 'ARRAY' ? $attrs : [$attrs]}) {
    Carp::croak qq{Attribute "$attr" invalid} unless $attr =~ /^[a-zA-Z_]\w*$/;

    # Very performance-sensitive code with lots of micro-optimizations
    if (ref $value) {
      _monkey_patch $class, $attr, sub {
        return
          exists $_[0]{$attr} ? $_[0]{$attr} : ($_[0]{$attr} = $value->($_[0]))
          if @_ == 1;
        $_[0]{$attr} = $_[1];
        $_[0];
      };
    }
    elsif (defined $value) {
      _monkey_patch $class, $attr, sub {
        return exists $_[0]{$attr} ? $_[0]{$attr} : ($_[0]{$attr} = $value)
          if @_ == 1;
        $_[0]{$attr} = $_[1];
        $_[0];
      };
    }
    else {
      _monkey_patch $class, $attr,
        sub { return $_[0]{$attr} if @_ == 1; $_[0]{$attr} = $_[1]; $_[0] };
    }
  }
}

sub import {
  my $class = shift;
  return unless my $flag = shift;

  # Base
  if ($flag eq '-base') { $flag = $class }

  # Strict
  elsif ($flag eq '-strict') { $flag = undef }

  # Module
  elsif ((my $file = $flag) && !$flag->can('new')) {
    $file =~ s!::|'!/!g;
    require "$file.pm";
  }

  # ISA
  if ($flag) {
    my $caller = caller;
    no strict 'refs';
    push @{"${caller}::ISA"}, $flag;
    _monkey_patch $caller, 'has', sub { attr($caller, @_) };
  }

  # Mojo modules are strict!
  $_->import for qw(strict warnings utf8);
  feature->import(':5.10');
}

sub new {
  my $class = shift;
  bless @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {}, ref $class || $class;
}

sub tap {
  my ($self, $cb) = (shift, shift);
  $_->$cb(@_) for $self;
  return $self;
}

1;

=encoding utf8

=head1 NAME

Mojo::Base - Minimal base class for Mojo projects

=head1 SYNOPSIS

  package Cat;
  use Mojo::Base -base;

  has name => 'Nyan';
  has ['age', 'weight'] => 4;

  package Tiger;
  use Mojo::Base 'Cat';

  has friend  => sub { Cat->new };
  has stripes => 42;

  package main;
  use Mojo::Base -strict;

  my $mew = Cat->new(name => 'Longcat');
  say $mew->age;
  say $mew->age(3)->weight(5)->age;

  my $rawr = Tiger->new(stripes => 38, weight => 250);
  say $rawr->tap(sub { $_->friend->name('Tacgnol') })->weight;

=head1 DESCRIPTION

L<Mojo::Base> is a simple base class for L<Mojo> projects with fluent
interfaces.

  # Automatically enables "strict", "warnings", "utf8" and Perl 5.10 features
  use Mojo::Base -strict;
  use Mojo::Base -base;
  use Mojo::Base 'SomeBaseClass';

All three forms save a lot of typing.

  # use Mojo::Base -strict;
  use strict;
  use warnings;
  use utf8;
  use feature ':5.10';
  use IO::Handle ();

  # use Mojo::Base -base;
  use strict;
  use warnings;
  use utf8;
  use feature ':5.10';
  use IO::Handle ();
  use Mojo::Base;
  push @ISA, 'Mojo::Base';
  sub has { Mojo::Base::attr(__PACKAGE__, @_) }

  # use Mojo::Base 'SomeBaseClass';
  use strict;
  use warnings;
  use utf8;
  use feature ':5.10';
  use IO::Handle ();
  require SomeBaseClass;
  push @ISA, 'SomeBaseClass';
  use Mojo::Base;
  sub has { Mojo::Base::attr(__PACKAGE__, @_) }

=head1 FUNCTIONS

L<Mojo::Base> implements the following functions, which can be imported with
the C<-base> flag or by setting a base class.

=head2 has

  has 'name';
  has ['name1', 'name2', 'name3'];
  has name => 'foo';
  has name => sub {...};
  has ['name1', 'name2', 'name3'] => 'foo';
  has ['name1', 'name2', 'name3'] => sub {...};

Create attributes for hash-based objects, just like the L</"attr"> method.

=head1 METHODS

L<Mojo::Base> implements the following methods.

=head2 attr

  $object->attr('name');
  SubClass->attr('name');
  SubClass->attr(['name1', 'name2', 'name3']);
  SubClass->attr(name => 'foo');
  SubClass->attr(name => sub {...});
  SubClass->attr(['name1', 'name2', 'name3'] => 'foo');
  SubClass->attr(['name1', 'name2', 'name3'] => sub {...});

Create attribute accessors for hash-based objects, an array reference can be
used to create more than one at a time. Pass an optional second argument to set
a default value, it should be a constant or a callback. The callback will be
executed at accessor read time if there's no set value. Accessors can be
chained, that means they return their invocant when they are called with an
argument.

=head2 new

  my $object = SubClass->new;
  my $object = SubClass->new(name => 'value');
  my $object = SubClass->new({name => 'value'});

This base class provides a basic constructor for hash-based objects. You can
pass it either a hash or a hash reference with attribute values.

=head2 tap

  $object = $object->tap(sub {...});
  $object = $object->tap('some_method');
  $object = $object->tap('some_method', @args);

Tap into a method chain to perform operations on an object within the chain
(also known as a K combinator or Kestrel). The object will be the first argument
passed to the callback, and is also available as C<$_>. The callback's return
value will be ignored; instead, the object (the callback's first argument) will
be the return value. In this way, arbitrary code can be used within (i.e.,
spliced or tapped into) a chained set of object method calls.

  # Longer version
  $object = $object->tap(sub { $_->some_method(@args) });

  # Inject side effects into a method chain
  $object->foo('A')->tap(sub { say $_->foo })->foo('B');

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
