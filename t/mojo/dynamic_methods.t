use Mojo::Base -strict;

use Test::More;

package Mojo::TestDynamic;
use Mojo::Base -base;

use Mojo::DynamicMethods -dispatch;

has hashref => sub { {} };

sub BUILD_DYNAMIC {
  my ($class, $method, $dyn_methods) = @_;

  return sub {
    my $self    = shift;
    my $dynamic = $dyn_methods->{$self->hashref}{$method};
    return $self->$dynamic($dyn_methods) if $dynamic;
    my $package = ref $self;
    Carp::croak qq{Can't locate object method "$method" via package "$package"};
  };
}

package main;

# Basics
my ($t1, $t2) = (Mojo::TestDynamic->new, Mojo::TestDynamic->new);
Mojo::DynamicMethods::register 'Mojo::TestDynamic', $t1->hashref, 'foo',
  sub { };
my $foo = \&Mojo::TestDynamic::_Dynamic::foo;
my ($called_foo, $dyn_methods);
Mojo::DynamicMethods::register 'Mojo::TestDynamic', $t1->hashref, 'foo',
  sub { $called_foo++; $dyn_methods = $_[1] };
is $foo, \&Mojo::TestDynamic::_Dynamic::foo, 'foo not reinstalled';
ok !Mojo::TestDynamic->can('foo'), 'dynamic method is hidden';
ok eval { $t1->foo; 1 }, 'foo called ok';
cmp_ok $called_foo, '==', 1, 'called dynamic method';
ok !eval { $t2->foo; 1 }, 'error calling foo on wrong object';

# Garbage collection
undef($t1);
undef($t2);
ok(!keys(%$dyn_methods), 'dynamic methods expired');

done_testing;
