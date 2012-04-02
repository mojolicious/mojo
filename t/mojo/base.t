use Mojo::Base -strict;

use Test::More tests => 409;

use FindBin;
use lib "$FindBin::Bin/lib";

package BaseTest;
use Mojo::Base -strict;

use base 'BaseTest::Base2';

# "When I first heard that Marge was joining the police academy,
#  I thought it would be fun and zany, like that movie Spaceballs.
#  But instead it was dark and disturbing.
#  Like that movie... Police Academy."
__PACKAGE__->attr(heads => 1);
__PACKAGE__->attr('name');

package BaseTestTest;
use Mojo::Base '+BaseTest';

package main;

use Mojo::Base;
use BaseTest::Base1;
use BaseTest::Base2;
use BaseTest::Base3;

# Basic functionality
my $monkeys = [];
for my $i (1 .. 50) {
  $monkeys->[$i] = BaseTest->new;
  $monkeys->[$i]->bananas($i);
  is $monkeys->[$i]->bananas, $i, 'right attribute value';
}
for my $i (51 .. 100) {
  $monkeys->[$i] = BaseTestTest->new(bananas => $i);
  is $monkeys->[$i]->bananas, $i, 'right attribute value';
}

# Instance method
my $monkey = BaseTest->new;
$monkey->attr('mojo');
$monkey->mojo(23);
is $monkey->mojo, 23, 'monkey has mojo';

# "default" defined but false
my $m = $monkeys->[1];
ok defined($m->coconuts);
is $m->coconuts, 0, 'right attribute value';
$m->coconuts(5);
is $m->coconuts, 5, 'right attribute value';

# "default" support
my $y = 1;
for my $i (101 .. 150) {
  $y = !$y;
  $monkeys->[$i] = BaseTest->new;
  isa_ok $monkeys->[$i]->name('foobarbaz'),
    'BaseTest', 'attribute value has right class';
  $monkeys->[$i]->heads('3') if $y;
  $y
    ? is($monkeys->[$i]->heads, 3, 'right attribute value')
    : is($monkeys->[$i]->heads, 1, 'right attribute default value');
}

# "chained" and coderef "default" support
for my $i (151 .. 200) {
  $monkeys->[$i] = BaseTest->new;
  is $monkeys->[$i]->ears, 2, 'right attribute value';
  is $monkeys->[$i]->ears(6)->ears, 6, 'right chained attribute value';
  is $monkeys->[$i]->eyes, 2, 'right attribute value';
  is $monkeys->[$i]->eyes(6)->eyes, 6, 'right chained attribute value';
}

# Inherit -base flag
$monkey = BaseTest::Base3->new(evil => 1);
is $monkey->evil,    1,     'monkey is evil';
is $monkey->bananas, undef, 'monkey has no bananas';
$monkey->bananas(3);
is $monkey->bananas, 3, 'monkey has 3 bananas';

# Exceptions
eval { BaseTest->attr(foo => []) };
like $@, qr/Default has to be a code reference or constant value/,
  'right error';
eval { BaseTest->attr(23) };
like $@, qr/Attribute "23" invalid/, 'right error';

1;
