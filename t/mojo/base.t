use Mojo::Base -strict;

use Test::More;

use FindBin;
use lib "$FindBin::Bin/lib";

package Mojo::BaseTest;
use Mojo::Base -strict;

use base 'Mojo::BaseTest::Base2';

__PACKAGE__->attr(tests => 1);
__PACKAGE__->attr('name');

sub more_tests { shift->{tests} += shift // 1 }

package Mojo::BaseTestTest;
use Mojo::Base 'Mojo::BaseTest';

package Mojo::BaseTestTestTest;
use Mojo::Base "Mojo'BaseTestTest";

package main;

use Mojo::Base;
use Mojo::BaseTest::Base1;
use Mojo::BaseTest::Base2;
use Mojo::BaseTest::Base3;

# Basic functionality
my $object = Mojo::BaseTest->new->foo(23);
my $object2 = Mojo::BaseTestTest->new(foo => 24);
is $object2->foo, 24, 'right attribute value';
is $object->foo,  23, 'right attribute value';

# Instance method
$object = Mojo::BaseTestTestTest->new;
$object->attr('mojo');
is $object->mojo(23)->mojo, 23, 'object has mojo';
ok !Mojo::BaseTestTest->can('mojo'),   'base class does not have mojo';
ok !!Mojo::BaseTestTest->can('tests'), 'base class has tests';
ok !Mojo::BaseTest->can('mojo'),       'base class does not have mojo';
ok !!Mojo::BaseTest->can('tests'),     'base class has tests';

# Default value defined but false
ok defined($object->yada);
is $object->yada, 0, 'right attribute value';
is $object->yada(5)->yada, 5, 'right attribute value';

# Default value support
$object = Mojo::BaseTest->new;
isa_ok $object->name('foobarbaz'), 'Mojo::BaseTest',
  'attribute value has right class';
$object2 = Mojo::BaseTest->new->tests('3');
is $object2->tests, 3, 'right attribute value';
is $object->tests,  1, 'right attribute default value';

# Chained attributes and callback default value support
$object = Mojo::BaseTest->new;
is $object->bar, 2, 'right attribute value';
is $object->bar(6)->bar, 6, 'right chained attribute value';
is $object->baz, 2, 'right attribute value';
is $object->baz(6)->baz, 6, 'right chained attribute value';

# Tap into chain
$object = Mojo::BaseTest->new;
is $object->tap(sub { $_->name('foo') })->name, 'foo', 'right attribute value';
is $object->tap(sub { shift->name('bar')->name })->name, 'bar',
  'right attribute value';
is $object->tap('tests')->tests, 1, 'right attribute value';
is $object->more_tests, 2, 'right attribute value';
is $object->tap('more_tests')->tests, 3, 'right attribute value';
is $object->tap(more_tests => 3)->tests, 6, 'right attribute value';

# Inherit -base flag
$object = Mojo::BaseTest::Base3->new(test => 1);
is $object->test, 1,     'right attribute value';
is $object->foo,  undef, 'no attribute value';
is $object->foo(3)->foo, 3, 'right attribute value';

# Exceptions
eval { Mojo::BaseTest->attr(foo => []) };
like $@, qr/Default has to be a code reference or constant value/,
  'right error';
eval { Mojo::BaseTest->attr(23) };
like $@, qr/Attribute "23" invalid/, 'right error';

done_testing();
