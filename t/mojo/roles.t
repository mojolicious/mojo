use Mojo::Base -strict;

use Test::More;

BEGIN {
  plan skip_all => 'Role::Tiny 2.000001+ required for this test!'
    unless Mojo::Base->ROLES;
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

package Mojo::RoleTest::Hello;
use Role::Tiny;

sub hello {'hello mojo!'}

package main;

use Mojo::ByteStream;
use Mojo::Collection;
use Mojo::DOM;
use Mojo::File;

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

# Classes that are not subclasses of Mojo::Base
my $stream = Mojo::ByteStream->with_roles('Mojo::RoleTest::Hello')->new;
is $stream->hello, 'hello mojo!', 'right result';
my $c = Mojo::Collection->with_roles('Mojo::RoleTest::Hello')->new;
is $c->hello, 'hello mojo!', 'right result';
my $dom = Mojo::DOM->with_roles('Mojo::RoleTest::Hello')->new;
is $dom->hello, 'hello mojo!', 'right result';
my $file = Mojo::File->with_roles('Mojo::RoleTest::Hello')->new;
is $file->hello, 'hello mojo!', 'right result';

done_testing();

