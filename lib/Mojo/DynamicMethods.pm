package Mojo::DynamicMethods;
use Mojo::Base -strict;

use Mojo::Util qw(class_to_path monkey_patch);
use Hash::Util::FieldHash 'fieldhash';
use Scalar::Util 'weaken';

fieldhash my %Dyn_Methods;

sub import {
  my ($flag, $caller) = (shift // '', caller);

  my $dyn_pkg = "${caller}::_DynamicMethods";
  monkey_patch $dyn_pkg, 'can', sub {
    my ($self, $method, @rest) = @_;

    # Delegate to our parent's "can" if there is one, without breaking if not
    my $can = $self->${\($self->next::can || 'UNIVERSAL::can')}($method, @rest);
    return undef unless $can;
    my $h = do { no strict 'refs'; *{"${dyn_pkg}::{$method}"}{CODE} };
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
