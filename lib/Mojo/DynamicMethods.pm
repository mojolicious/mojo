package Mojo::DynamicMethods;
use Mojo::Base -strict;

use Mojo::Util qw(class_to_path monkey_patch);
use Hash::Util::FieldHash 'fieldhash';
use Scalar::Util 'weaken';

fieldhash my %Dyn_Methods;

sub import {
  my ($flag, $caller) = ($_[1] // '', caller);
  return unless $flag eq '-dispatch';

  my $dyn_pkg = "${caller}::_DynamicMethods";
  monkey_patch $dyn_pkg, 'can', sub {
    my ($self, $method, @rest) = @_;

    # Delegate to our parent's "can" if there is one, without breaking if not
    my $can = $self->${\($self->next::can || 'UNIVERSAL::can')}($method, @rest);
    return undef unless $can;
    my $h = do { no strict 'refs'; *{"${dyn_pkg}::${method}"}{CODE} };
    return $h && $h eq $can ? undef : $can;
  };

  $INC{class_to_path($dyn_pkg)} = __FILE__;
  {
    no strict 'refs';
    unshift @{"${caller}::ISA"}, $dyn_pkg;
  }
}

sub register {
  my ($target, $object, $name, $code) = @_;

  my $dyn_pkg = "${target}::_DynamicMethods";
  monkey_patch($dyn_pkg, $name, $target->BUILD_DYNAMIC($name, \%Dyn_Methods))
    unless $dyn_pkg->can($name);
  $Dyn_Methods{$object}{$name} = $code;
}

1;

=encoding utf8

=head1 NAME

Mojo::DynamicMethods - Dynamic method dispatch for helpers and related code

=head1 SYNOPSIS

  package MyClass;
  
  use Mojo::Base -base;
  
  use Mojo::DynamicMethods -dispatch;
  
  sub BUILD_DYNAMIC {
    my ($class, $method, $dyn_methods) = @_;
    return sub {
      my $self    = shift;
      my $dynamic = $dyn_methods->{$self}{$method};
      return $self->$dynamic(@_) if $dynamic;
      my $package = ref $self;
      Carp::croak qq{Can't locate object method "$method" via package "$package"};
    };
  }
  
  sub add_helper {
    my ($self, $name, $code) = @_;
    Mojo::DynamicMethods::register 'MyClass', $self, $name, $code;
  }
  
  package main;
  
  my $obj = MyClass->new->add_helper(foo => sub { warn "foo" });
  
  $obj->foo;

=head1 DESCRIPTION

L<Mojo::DynamicMethods> provides dynamic method dispatch for per-object
helper methods without requiring use of C<AUTOLOAD>.

To opt your class into dynamic dispatch, simply pass the -dispatch flag:

  use Mojo::DynamicMethods -dispatch;

and implement L</BUILD_DYNAMIC> as a method in your class.

=head1 FUNCTIONS

L<Mojo::DynamicMethods> provides the following function, which is not exported:

=head2 register

  Mojo::DynamicMethods::register $class, $ref, $name, $code;

Registers the method C<$name> as eligible for dynamic dispatch for C<$class>,
and sets C<$code> to be looked up for C<$name> by reference C<$ref> in a
dynamic method contructed by L</BUILD_DYNAMIC>.

=head1 METHODS

L<Mojo::DynamicMethods> requires you to implement the following method on
any class participating in dynamic dispatch:

=head2 BUILD_DYNAMIC
  
  sub BUILD_DYNAMIC {
    my ($class, $method, $dyn_methods) = @_;
    return sub {
      my $self    = shift;
      my $dynamic = $dyn_methods->{$self}{$method};
      return $self->$dynamic(@_) if $dynamic;
      my $package = ref $self;
      Carp::croak qq{Can't locate object method "$method" via package "$package"};
    };
  }

Then later:

  Mojo::DynamicMethods::register $class, $self, $name, $code;

Must return a subroutine suitable for installation under name C<$method>
which will look up the dynamic method coderef in the supplied C<$dyn_methods>
hashref using the same reference passed to L</register>.
