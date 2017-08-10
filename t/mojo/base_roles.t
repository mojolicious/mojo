use Mojo::Base -strict;

use Test::More;

BEGIN {
  plan skip_all => 'Role::Tiny 2.000001+ required for this test!'
    unless Mojo::Base->can_roles;
}

package Mojo::RoleTest::LOUD;
use Role::Tiny;

sub yell {'HEY!'}

requires 'name';

sub hello {
  my $self = shift;
  return $self->yell . ' ' . uc($self->name) . '!!!';
}

package Mojo::RoleTest::quiet;
use Role::Tiny;

requires 'name';

sub whisper {
  my $self = shift;
  return 'psst, ' . lc($self->name);
}

package Mojo::RoleTest::Base;
use Mojo::Base -base;

has name => 'bob';

sub hello {
  my ($self) = shift;
  return 'hello ' . $self->name;
}

package main;

# Plain class
my $obj = Mojo::RoleTest::Base->new(name => 'Ted');
is $obj->name,  'Ted',       'attribute';
is $obj->hello, 'hello Ted', 'method';

# Single role
my $obj2 = Mojo::RoleTest::Base->with_roles('Mojo::RoleTest::LOUD')->new;
is $obj2->hello, 'HEY! BOB!!!', 'role method';
is $obj2->yell,  'HEY!',        'another role method';

# Multiple roles
my $obj3 = Mojo::RoleTest::Base->with_roles('Mojo::RoleTest::quiet',
  'Mojo::RoleTest::LOUD')->new(name => 'Joel');
is $obj3->name,    'Joel',         'base attribute';
is $obj3->whisper, 'psst, joel',   'method from first role';
is $obj3->hello,   'HEY! JOEL!!!', 'method from second role';

done_testing();

