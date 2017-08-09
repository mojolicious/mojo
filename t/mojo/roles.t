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
  my ($self) = @_;
  return $self->yell . ' ' . uc($self->name) . '!!!';
}

package Mojo::RoleTest::quiet;
use Role::Tiny;

requires 'name';

sub whisper {
  my ($self) = @_;
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

my $obj = Mojo::RoleTest::Base->new(name => 'Ted');
is($obj->name,  'Ted',       'attr works');
is($obj->hello, 'hello Ted', 'class method');

my $obj2 = Mojo::RoleTest::Base->with_roles('Mojo::RoleTest::LOUD')->new;
is($obj2->hello, 'HEY! BOB!!!', 'method from role overrides base method');
is($obj2->yell,  'HEY!',        'new method from role');

my $obj3 = Mojo::RoleTest::Base->with_roles('Mojo::RoleTest::quiet',
  'Mojo::RoleTest::LOUD')->new(name => 'Joel');
is($obj3->name,    'Joel',         'attr from base class');
is($obj3->whisper, 'psst, joel',   'method from role1');
is($obj3->hello,   'HEY! JOEL!!!', 'method override from role2');

done_testing();

