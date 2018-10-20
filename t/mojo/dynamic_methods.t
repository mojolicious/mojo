use Mojo::Base -base;

use Test::More;
use Mojo::DynamicMethods;

{
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
}

my ($t1, $t2) = map Mojo::TestDynamic->new, 1, 2;

Mojo::DynamicMethods::register
  'Mojo::TestDynamic', $t1->hashref, 'foo',
  sub { };

my $foo = \&Mojo::TestDynamic::_Dynamic::foo;

my $called_foo;

my $dyn_methods;

Mojo::DynamicMethods::register
  'Mojo::TestDynamic', $t1->hashref, 'foo',
  sub { $called_foo++; $dyn_methods = $_[1] };

is($foo, \&Mojo::TestDynamic::_Dynamic::foo, 'foo not reinstalled');

ok(!Mojo::TestDynamic->can('foo'), 'dynamic method hidden');

ok(eval { $t1->foo; 1 }, 'foo called ok');

cmp_ok($called_foo, '==', 1, 'called dynamic method');

ok(!eval { $t2->foo; 1 }, 'error calling foo on wrong object');

undef($t1); undef($t2);

ok(!keys(%$dyn_methods), 'dead object dynamic methods expired');

done_testing;
