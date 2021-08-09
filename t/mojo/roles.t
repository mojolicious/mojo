use Mojo::Base -strict;

use Test::More;

BEGIN {
  plan skip_all => 'Role::Tiny 2.000001+ required for this test!' unless Mojo::Base->ROLES;
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

package main;

use Mojo::ByteStream;
use Mojo::Collection;
use Mojo::DOM;
use Mojo::File;

subtest 'Plain class' => sub {
  my $obj = Mojo::RoleTest->new(name => 'Ted');
  is $obj->name,  'Ted',       'attribute';
  is $obj->hello, 'hello Ted', 'method';
};

subtest 'Empty roles' => sub {
  my $fred = Mojo::RoleTest->with_roles()->new(name => 'Fred');
  is $fred->name,  'Fred',       'attribute';
  is $fred->hello, 'hello Fred', 'method';
};

subtest 'Empty object roles' => sub {
  my $obj       = Mojo::RoleTest->new(name => 'Ted');
  my $obj_empty = $obj->with_roles();
  is $obj_empty->name,  'Ted',       'attribute';
  is $obj_empty->hello, 'hello Ted', 'method';
};

subtest 'Single role' => sub {
  my $obj = Mojo::RoleTest->with_roles('Mojo::RoleTest::Role::LOUD')->new;
  is $obj->hello, 'HEY! BOB!!!', 'role method';
  is $obj->yell,  'HEY!',        'another role method';
};

subtest 'Single role (shorthand)' => sub {
  my $obj = Mojo::RoleTest->with_roles('+LOUD')->new;
  is $obj->hello, 'HEY! BOB!!!', 'role method';
  is $obj->yell,  'HEY!',        'another role method';
};

subtest 'Multiple roles' => sub {
  my $obj
    = Mojo::RoleTest->with_roles('Mojo::RoleTest::Role::quiet', 'Mojo::RoleTest::Role::LOUD')->new(name => 'Joel');
  is $obj->name,    'Joel',       'base attribute';
  is $obj->whisper, 'psst, joel', 'method from first role';
  $obj->prefix('psssst, ');
  is $obj->whisper, 'psssst, joel', 'method from first role';
  is $obj->hello,   'HEY! JOEL!!!', 'method from second role';
};

subtest 'Multiple roles (shorthand)' => sub {
  my $obj = Mojo::RoleTest->with_roles('+quiet', '+LOUD')->new(name => 'Joel');
  is $obj->name,    'Joel',         'base attribute';
  is $obj->whisper, 'psst, joel',   'method from first role';
  is $obj->hello,   'HEY! JOEL!!!', 'method from second role';
};

subtest 'Multiple roles (mixed)' => sub {
  my $obj = Mojo::RoleTest->with_roles('Mojo::RoleTest::Role::quiet', '+LOUD')->new(name => 'Joel');
  is $obj->name,    'Joel',         'base attribute';
  is $obj->whisper, 'psst, joel',   'method from first role';
  is $obj->hello,   'HEY! JOEL!!!', 'method from second role';
};

subtest 'Multiple object roles (mixed)' => sub {
  my $obj = Mojo::RoleTest->new(name => 'Joel')->with_roles('Mojo::RoleTest::Role::quiet', '+LOUD');
  is $obj->name,    'Joel',         'base attribute';
  is $obj->whisper, 'psst, joel',   'method from first role';
  is $obj->hello,   'HEY! JOEL!!!', 'method from second role';
};

subtest 'Multiple Mojo::Base roles' => sub {
  my $obj = Mojo::RoleTest->with_roles('+quiet', 'Mojo::RoleTest::Hello')->new(name => 'Joel');
  is $obj->name,    'Joel',        'base attribute';
  is $obj->whisper, 'psst, joel',  'method from first role';
  is $obj->hello,   'hello mojo!', 'method from second role';
};

subtest 'Classes that are not subclasses of Mojo::Base' => sub {
  my $stream = Mojo::ByteStream->with_roles('Mojo::RoleTest::Hello')->new;
  is $stream->hello, 'hello mojo!', 'right result';
  my $c = Mojo::Collection->with_roles('Mojo::RoleTest::Hello')->new;
  is $c->hello, 'hello mojo!', 'right result';
  my $dom = Mojo::DOM->with_roles('Mojo::RoleTest::Hello')->new;
  is $dom->hello, 'hello mojo!', 'right result';
  my $file = Mojo::File->with_roles('Mojo::RoleTest::Hello')->new;
  is $file->hello, 'hello mojo!', 'right result';
};

done_testing();
