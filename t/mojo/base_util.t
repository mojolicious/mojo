use Mojo::Base -strict;

use Test::More;
use Sub::Util qw(subname);

use Mojo::BaseUtil qw(class_to_path monkey_patch);

subtest 'class_to_path' => sub {
  is Mojo::BaseUtil::class_to_path('Foo::Bar'),      'Foo/Bar.pm',     'right path';
  is Mojo::BaseUtil::class_to_path("Foo'Bar"),       'Foo/Bar.pm',     'right path';
  is Mojo::BaseUtil::class_to_path("Foo'Bar::Baz"),  'Foo/Bar/Baz.pm', 'right path';
  is Mojo::BaseUtil::class_to_path("Foo::Bar'Baz"),  'Foo/Bar/Baz.pm', 'right path';
  is Mojo::BaseUtil::class_to_path("Foo::Bar::Baz"), 'Foo/Bar/Baz.pm', 'right path';
  is Mojo::BaseUtil::class_to_path("Foo'Bar'Baz"),   'Foo/Bar/Baz.pm', 'right path';
};

subtest 'monkey_patch' => sub {
  {

    package MojoMonkeyTest;
    sub foo {'foo'}
  }
  ok !!MojoMonkeyTest->can('foo'), 'function "foo" exists';
  is MojoMonkeyTest::foo(), 'foo', 'right result';
  ok !MojoMonkeyTest->can('bar'), 'function "bar" does not exist';
  monkey_patch 'MojoMonkeyTest', bar => sub {'bar'};
  ok !!MojoMonkeyTest->can('bar'), 'function "bar" exists';
  is MojoMonkeyTest::bar(), 'bar', 'right result';
  monkey_patch 'MojoMonkeyTest', foo => sub {'baz'};
  ok !!MojoMonkeyTest->can('foo'), 'function "foo" exists';
  is MojoMonkeyTest::foo(), 'baz', 'right result';
  ok !MojoMonkeyTest->can('yin'),  'function "yin" does not exist';
  ok !MojoMonkeyTest->can('yang'), 'function "yang" does not exist';
  monkey_patch 'MojoMonkeyTest',
    yin  => sub {'yin'},
    yang => sub {'yang'};
  ok !!MojoMonkeyTest->can('yin'), 'function "yin" exists';
  is MojoMonkeyTest::yin(), 'yin', 'right result';
  ok !!MojoMonkeyTest->can('yang'), 'function "yang" exists';
  is MojoMonkeyTest::yang(), 'yang', 'right result';
};

subtest 'monkey_patch (with name)' => sub {
  is subname(MojoMonkeyTest->can('foo')), 'MojoMonkeyTest::foo', 'right name';
  is subname(MojoMonkeyTest->can('bar')), 'MojoMonkeyTest::bar', 'right name';
};

done_testing();
