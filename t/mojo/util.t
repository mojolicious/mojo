use Mojo::Base -strict;

use Test::More tests => 20;

# "If he is so smart, how come he is dead?"
use Mojo::Util qw(class_to_file class_to_path get_line);

# class_to_file
is class_to_file('Foo::Bar'), 'foo_bar', 'right file';
is class_to_file('FooBar'),   'foo_bar', 'right file';
is class_to_file('FOOBar'),   'foobar',  'right file';
is class_to_file('FOOBAR'),   'foobar',  'right file';
is class_to_file('FOO::Bar'), 'foobar',  'right file';
is class_to_file('FooBAR'),   'foo_bar', 'right file';
is class_to_file('Foo::BAR'), 'foo_bar', 'right file';

# class_to_path
is class_to_path('Foo::Bar'),      'Foo/Bar.pm',     'right path';
is class_to_path("Foo'Bar"),       'Foo/Bar.pm',     'right path';
is class_to_path("Foo'Bar::Baz"),  'Foo/Bar/Baz.pm', 'right path';
is class_to_path("Foo::Bar'Baz"),  'Foo/Bar/Baz.pm', 'right path';
is class_to_path("Foo::Bar::Baz"), 'Foo/Bar/Baz.pm', 'right path';
is class_to_path("Foo'Bar'Baz"),   'Foo/Bar/Baz.pm', 'right path';

# get_line
my $buffer = "foo\x0d\x0abar\x0dbaz\x0ayada\x0d\x0a";
is get_line(\$buffer), 'foo', 'right line';
is $buffer, "bar\x0dbaz\x0ayada\x0d\x0a", 'right buffer content';
is get_line(\$buffer), "bar\x0dbaz", 'right line';
is $buffer, "yada\x0d\x0a", 'right buffer content';
is get_line(\$buffer), 'yada', 'right line';
is $buffer, '', 'no buffer content';
is get_line(\$buffer), undef, 'no line';
