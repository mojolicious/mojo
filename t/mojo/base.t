use Mojo::Base -strict;

use Test::More;

use FindBin;
use lib "$FindBin::Bin/lib";

package Mojo::BaseTest;
use Mojo::Base -strict;

use base 'Mojo::BaseTest::Base2';

__PACKAGE__->attr(heads => 1);
__PACKAGE__->attr('name');

sub more_heads { shift->{heads} += shift // 1 }

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
my $monkey = Mojo::BaseTest->new->bananas(23);
my $monkey2 = Mojo::BaseTestTest->new(bananas => 24);
is $monkey2->bananas, 24, 'right attribute value';
is $monkey->bananas,  23, 'right attribute value';

# Instance method
$monkey = Mojo::BaseTestTestTest->new;
$monkey->attr('mojo');
is $monkey->mojo(23)->mojo, 23, 'monkey has mojo';
ok !Mojo::BaseTestTest->can('mojo'),   'base class does not have mojo';
ok !!Mojo::BaseTestTest->can('heads'), 'base class has heads';
ok !Mojo::BaseTest->can('mojo'),       'base class does not have mojo';
ok !!Mojo::BaseTest->can('heads'),     'base class has heads';

# Default value defined but false
ok defined($monkey->coconuts);
is $monkey->coconuts, 0, 'right attribute value';
is $monkey->coconuts(5)->coconuts, 5, 'right attribute value';

# Default value support
$monkey = Mojo::BaseTest->new;
isa_ok $monkey->name('foobarbaz'), 'Mojo::BaseTest',
  'attribute value has right class';
$monkey2 = Mojo::BaseTest->new->heads('3');
is $monkey2->heads, 3, 'right attribute value';
is $monkey->heads,  1, 'right attribute default value';

# Chained attributes and callback default value support
$monkey = Mojo::BaseTest->new;
is $monkey->ears, 2, 'right attribute value';
is $monkey->ears(6)->ears, 6, 'right chained attribute value';
is $monkey->eyes, 2, 'right attribute value';
is $monkey->eyes(6)->eyes, 6, 'right chained attribute value';

# Tap into chain
$monkey = Mojo::BaseTest->new;
is $monkey->tap(sub { $_->name('foo') })->name, 'foo', 'right attribute value';
is $monkey->tap(sub { shift->name('bar')->name })->name, 'bar',
  'right attribute value';
is $monkey->tap('heads')->heads, 1, 'right attribute value';
is $monkey->more_heads, 2, 'right attribute value';
is $monkey->tap('more_heads')->heads, 3, 'right attribute value';
is $monkey->tap(more_heads => 3)->heads, 6, 'right attribute value';

# Inherit -base flag
$monkey = Mojo::BaseTest::Base3->new(evil => 1);
is $monkey->evil,    1,     'monkey is evil';
is $monkey->bananas, undef, 'monkey has no bananas';
is $monkey->bananas(3)->bananas, 3, 'monkey has 3 bananas';

# Exceptions
eval { Mojo::BaseTest->attr(foo => []) };
like $@, qr/Default has to be a code reference or constant value/,
  'right error';
eval { Mojo::BaseTest->attr(23) };
like $@, qr/Attribute "23" invalid/, 'right error';

done_testing();
