use Mojo::Base -strict;

use Test::More;

BEGIN {
  plan skip_all => 'Role::Tiny 2.000001+ required for this test!'
    unless Mojo::Base->ROLES;
}

package Mojo::RoleTest::Role::LOUD;
use Role::Tiny;

sub yell {'HEY!'}

requires 'name';

sub hello {
  my $self = shift;
  return $self->yell . ' ' . uc($self->name) . '!!!';
}

package Mojo::RoleTest::Role::quiet;
use Mojo::Base -role;

requires 'name';

has prefix => 'psst, ';

sub whisper {
  my $self = shift;
  return $self->prefix . lc($self->name);
}

package Mojo::RoleTest;
use Mojo::Base -base;

has name => 'bob';

sub hello {
  my ($self) = shift;
  return 'hello ' . $self->name;
}

package Mojo::RoleTest::Hello;
use Mojo::Base -role;

sub hello {'hello mojo!'}

package Mojo::RoleListApplied::Role::LOUD;
use Role::Tiny;

sub yell {'HEY!'}

package Mojo::RoleApplied::Role::LOUD;
use Role::Tiny;

sub yell {'HEY!'}

package Mojo::RoleListApplied;
use Mojo::Base -base, -with => ['Mojo::RoleTest::Hello', '+LOUD'];

package Mojo::RoleApplied;
use Mojo::Base -base, -with => '+LOUD';

package Mojo::RolePathApplied;
use Mojo::Base -base, -with => 'Mojo::RoleTest::Hello';

package main;

use Mojo::ByteStream;
use Mojo::Collection;
use Mojo::DOM;
use Mojo::File;

# Plain class
my $obj = Mojo::RoleTest->new(name => 'Ted');
is $obj->name,  'Ted',       'attribute';
is $obj->hello, 'hello Ted', 'method';

# Empty roles
my $fred = Mojo::RoleTest->with_roles()->new(name => 'Fred');
is $fred->name,  'Fred',       'attribute';
is $fred->hello, 'hello Fred', 'method';

# Empty object roles
my $obj_empty = $obj->with_roles();
is $obj_empty->name,  'Ted',       'attribute';
is $obj_empty->hello, 'hello Ted', 'method';

# Single role
my $obj2 = Mojo::RoleTest->with_roles('Mojo::RoleTest::Role::LOUD')->new;
is $obj2->hello, 'HEY! BOB!!!', 'role method';
is $obj2->yell,  'HEY!',        'another role method';

# Single role (shorthand)
my $obj4 = Mojo::RoleTest->with_roles('+LOUD')->new;
is $obj4->hello, 'HEY! BOB!!!', 'role method';
is $obj4->yell,  'HEY!',        'another role method';

# Multiple roles
my $obj3 = Mojo::RoleTest->with_roles('Mojo::RoleTest::Role::quiet',
  'Mojo::RoleTest::Role::LOUD')->new(name => 'Joel');
is $obj3->name,    'Joel',       'base attribute';
is $obj3->whisper, 'psst, joel', 'method from first role';
$obj3->prefix('psssst, ');
is $obj3->whisper, 'psssst, joel', 'method from first role';
is $obj3->hello,   'HEY! JOEL!!!', 'method from second role';

# Multiple roles (shorthand)
my $obj5 = Mojo::RoleTest->with_roles('+quiet', '+LOUD')->new(name => 'Joel');
is $obj5->name,    'Joel',         'base attribute';
is $obj5->whisper, 'psst, joel',   'method from first role';
is $obj5->hello,   'HEY! JOEL!!!', 'method from second role';

# Multiple roles (mixed)
my $obj6 = Mojo::RoleTest->with_roles('Mojo::RoleTest::Role::quiet', '+LOUD')
  ->new(name => 'Joel');
is $obj6->name,    'Joel',         'base attribute';
is $obj6->whisper, 'psst, joel',   'method from first role';
is $obj6->hello,   'HEY! JOEL!!!', 'method from second role';

# Multiple object roles (mixed)
my $obj7 = Mojo::RoleTest->new(name => 'Joel')
  ->with_roles('Mojo::RoleTest::Role::quiet', '+LOUD');
is $obj7->name,    'Joel',         'base attribute';
is $obj7->whisper, 'psst, joel',   'method from first role';
is $obj7->hello,   'HEY! JOEL!!!', 'method from second role';

# Multiple Mojo::Base roles
my $obj8 = Mojo::RoleTest->with_roles('+quiet', 'Mojo::RoleTest::Hello')
  ->new(name => 'Joel');
is $obj8->name,    'Joel',        'base attribute';
is $obj8->whisper, 'psst, joel',  'method from first role';
is $obj8->hello,   'hello mojo!', 'method from second role';

# Classes that are not subclasses of Mojo::Base
my $stream = Mojo::ByteStream->with_roles('Mojo::RoleTest::Hello')->new;
is $stream->hello, 'hello mojo!', 'right result';
my $c = Mojo::Collection->with_roles('Mojo::RoleTest::Hello')->new;
is $c->hello, 'hello mojo!', 'right result';
my $dom = Mojo::DOM->with_roles('Mojo::RoleTest::Hello')->new;
is $dom->hello, 'hello mojo!', 'right result';
my $file = Mojo::File->with_roles('Mojo::RoleTest::Hello')->new;
is $file->hello, 'hello mojo!', 'right result';

# role applied to package, do not create a new class
my $list_applied = Mojo::RoleListApplied->new;
is $list_applied->hello, 'hello mojo!';
is $list_applied->yell, 'HEY!';

my $role_applied = Mojo::RoleApplied->new;
is $role_applied->yell, 'HEY!';

my $path_applied = Mojo::RolePathApplied->new;
is $path_applied->hello, 'hello mojo!';

done_testing();

