use Mojo::Base -strict;

use Test::More;
use Mojo::Exception qw(check raise);
use Mojo::File 'path';

package MojoTest::X::Foo;
use Mojo::Base 'Mojo::Exception';

package MojoTest::X::Bar;
use Mojo::Base 'Mojo::Exception';

package MojoTest::X::Yada;
use Mojo::Base 'MojoTest::X::Bar';

package main;

# Basics
my $e = Mojo::Exception->new;
is $e->message, 'Exception!', 'right message';
is "$e", "Exception!\n", 'right message';
$e = Mojo::Exception->new('Test!');
is $e->message, 'Test!', 'right message';
is "$e", "Test!\n", 'right message';

# Context information
my $line = __LINE__;
eval {

  # test

  my $wrapper = sub { Mojo::Exception->throw('Works!') };
  $wrapper->();

  # test

};
$e = $@;
isa_ok $e, 'Mojo::Exception', 'right class';
like $e->inspect, qr/^Works!/, 'right result';
like $e->frames->[0][1], qr/exception\.t/, 'right file';
is $e->lines_before->[0][0], $line, 'right number';
is $e->lines_before->[0][1], 'my $line = __LINE__;', 'right line';
is $e->lines_before->[1][0], $line + 1, 'right number';
is $e->lines_before->[1][1], 'eval {', 'right line';
is $e->lines_before->[2][0], $line + 2, 'right number';
ok !$e->lines_before->[2][1], 'empty line';
is $e->lines_before->[3][0], $line + 3, 'right number';
is $e->lines_before->[3][1], '  # test', 'right line';
is $e->lines_before->[4][0], $line + 4, 'right number';
ok !$e->lines_before->[4][1], 'empty line';
is $e->line->[0], $line + 5, 'right number';
is $e->line->[1], "  my \$wrapper = sub { Mojo::Exception->throw('Works!') };",
  'right line';
is $e->lines_after->[0][0], $line + 6, 'right number';
is $e->lines_after->[0][1], '  $wrapper->();', 'right line';
is $e->lines_after->[1][0], $line + 7, 'right number';
ok !$e->lines_after->[1][1], 'empty line';
is $e->lines_after->[2][0], $line + 8, 'right number';
is $e->lines_after->[2][1], '  # test', 'right line';
is $e->lines_after->[3][0], $line + 9, 'right number';
ok !$e->lines_after->[3][1], 'empty line';
is $e->lines_after->[4][0], $line + 10, 'right number';
is $e->lines_after->[4][1], '};', 'right line';

# Trace
sub wrapper2 { Mojo::Exception->new->trace(@_) }
sub wrapper1 { wrapper2(@_) }
like wrapper1()->frames->[0][3], qr/wrapper2/, 'right subroutine';
like wrapper1(0)->frames->[0][3], qr/trace/,    'right subroutine';
like wrapper1(1)->frames->[0][3], qr/wrapper2/, 'right subroutine';
like wrapper1(2)->frames->[0][3], qr/wrapper1/, 'right subroutine';

# Inspect (UTF-8)
my $file = path(__FILE__)->sibling('exception', 'utf8.txt');
$e = Mojo::Exception->new("Whatever at $file line 3.");
is_deeply $e->lines_before, [], 'no lines';
is_deeply $e->line,         [], 'no line';
is_deeply $e->lines_after,  [], 'no lines';
$e->inspect;
is_deeply $e->lines_before->[-1], [2, 'use warnings;'], 'right line';
is_deeply $e->line,               [3, 'use utf8;'],     'right line';
is_deeply $e->lines_after->[0],   [4, ''],              'right line';
$e = Mojo::Exception->new("Died at $file line 4.")->inspect;
is_deeply $e->lines_before->[-1], [3, 'use utf8;'], 'right line';
is_deeply $e->line,               [4, ''],          'right line';
is_deeply $e->lines_after->[0], [5, "my \$s = 'Über•résumé';"],
  'right line';

# Inspect (non UTF-8)
$file = $file->sibling('non_utf8.txt');
$e    = Mojo::Exception->new("Whatever at $file line 3.");
is_deeply $e->lines_before, [], 'no lines';
is_deeply $e->line,         [], 'no line';
is_deeply $e->lines_after,  [], 'no lines';
$e->inspect->inspect;
is_deeply $e->lines_before->[-1], [2, 'use warnings;'], 'right line';
is_deeply $e->line,               [3, 'no utf8;'],      'right line';
is_deeply $e->lines_after->[0],   [4, ''],              'right line';
$e = Mojo::Exception->new("Died at $file line 4.")->inspect;
is_deeply $e->lines_before->[-1], [3, 'no utf8;'], 'right line';
is_deeply $e->line,               [4, ''],         'right line';
is_deeply $e->lines_after->[0], [5, "my \$s = '\xDCber\x95r\xE9sum\xE9';"],
  'right line';

# Verbose
$e = Mojo::Exception->new->verbose(1);
is $e, "Exception!\n", 'right result';
$e = Mojo::Exception->new->inspect->inspect->verbose(1);
is $e, "Exception!\n", 'right result';
$e = Mojo::Exception->new('Test!')->verbose(1);
$e->frames([
  ['Sandbox',     'template',      4],
  ['MyApp::Test', 'MyApp/Test.pm', 3],
  ['main',        'foo.pl',        4]
]);
$e->lines_before([[3, 'foo();']])->line([4, 'die;'])
  ->lines_after([[5, 'bar();']]);
is $e, <<EOF, 'right result';
Test!
Context:
  3: foo();
  4: die;
  5: bar();
Traceback (most recent call first):
  File "template", line 4, in "Sandbox"
  File "MyApp/Test.pm", line 3, in "MyApp::Test"
  File "foo.pl", line 4, in "main"
EOF
$e->message("Works!\n")->lines_before([])->lines_after([]);
is $e, <<EOF, 'right result';
Works!
Context:
  4: die;
Traceback (most recent call first):
  File "template", line 4, in "Sandbox"
  File "MyApp/Test.pm", line 3, in "MyApp::Test"
  File "foo.pl", line 4, in "main"
EOF

# Missing error
$e = Mojo::Exception->new->inspect;
is_deeply $e->lines_before, [], 'no lines';
is_deeply $e->line,         [], 'no line';
is_deeply $e->lines_after,  [], 'no lines';
is $e->message, 'Exception!', 'right message';
$e = Mojo::Exception->new(undef)->inspect;
is_deeply $e->lines_before, [], 'no lines';
is_deeply $e->line,         [], 'no line';
is_deeply $e->lines_after,  [], 'no lines';
is $e->message, 'Exception!', 'right message';
$e = Mojo::Exception->new('')->inspect;
is_deeply $e->lines_before, [], 'no lines';
is_deeply $e->line,         [], 'no line';
is_deeply $e->lines_after,  [], 'no lines';
is $e->message, '', 'right message';

# Check (string exception)
my $result;
eval { die "test1\n" };
ok check(default => sub { $result = $_ }), 'exception handled';
is $result, "test1\n", 'exception arrived in handler';
$result = undef;
eval { die "test2\n" };
ok check(default => sub { $result = shift }), 'exception handled';
is $result, "test2\n", 'exception arrived in handler';
$result = undef;
eval { die "test3\n" };
check
  default    => sub { $result = 'fail' },
  qr/^test2/ => sub { $result = 'fail' },
  qr/^test3/ => sub { $result = 'test10' },
  qr/^test4/ => sub { $result = 'fail' };
is $result, 'test10', 'regular expression matched';
$result = undef;
check "test4\n",
  qr/^test3/ => sub { $result = 'fail' },
  qr/^test4/ => sub { $result = 'test11' },
  qr/^test5/ => sub { $result = 'fail' };
is $result, 'test11', 'regular expression matched';

# Check (exception objects)
$result = undef;
eval { MojoTest::X::Foo->throw('whatever') };
check
  default            => sub { $result = 'fail' },
  'MojoTest::X::Foo' => sub { $result = 'test12' },
  'MojoTest::X::Bar' => sub { $result = 'fail' };
is $result, 'test12', 'class matched';
$result = undef;
eval { MojoTest::X::Bar->throw('whatever') };
check
  'MojoTest::X::Foo' => sub { $result = 'fail' },
  'MojoTest::X::Bar' => sub { $result = 'test13' };
is $result, 'test13', 'class matched';
$result = undef;
check(
  MojoTest::X::Yada->new('whatever'),
  qr/whatever/       => sub { $result = 'fail' },
  'MojoTest::X::Foo' => sub { $result = 'fail' },
  'MojoTest::X::Bar' => sub { $result = 'test14' }
);
is $result, 'test14', 'class matched';

# Check (multiple)
$result = undef;
check(
  MojoTest::X::Yada->new('whatever'),
  ['MojoTest::X::Foo', 'MojoTest::X::Bar'] => sub { $result = 'test15' },
  default => sub { $result = 'fail' }
);
is $result, 'test15', 'class matched';
$result = undef;
check(
  MojoTest::X::Bar->new('whatever'),
  ['MojoTest::X::Foo', 'MojoTest::X::Yada'] => sub { $result = 'fail' },
  ['MojoTest::X::Bar'] => sub { $result = 'test16' }
);
is $result, 'test16', 'class matched';

# Check (rethrow)
eval {
  check "test5\n", qr/test4/ => sub { die 'fail' };
};
is $@, "test5\n", 'exception has been rethrown';

# Check (finally)
my $finally;
eval {
  check "test7\n", finally => sub { $finally = 'finally7' };
};
is $@,       "test7\n",  'exception has been rethrown';
is $finally, 'finally7', 'finally handler used';
$result = [];
check "test8\n",
  qr/test7/ => sub { push @$result, 'fail' },
  default   => sub { push @$result, $_ },
  finally   => sub { push @$result, 'finally8' };
is_deeply $result, ["test8\n", 'finally8'], 'default and finally handlers used';
$finally = undef;
eval {
  check "fail\n",
    default => sub { die "test17\n" },
    finally => sub { $finally = 'finally17' };
};
is $@,       "test17\n",  'right exception';
is $finally, 'finally17', 'finally handler used';

# Check (nothing)
ok !check(undef, default => sub { die 'fail' }), 'no exception';
{
  local $@;
  ok !check(default => sub { die 'fail' }), 'no exception';
}

# Raise
eval { raise 'MyApp::X::Baz', 'test19' };
my $err = $@;
isa_ok $err, 'MyApp::X::Baz',   'is a MyApp::X::Baz';
isa_ok $err, 'Mojo::Exception', 'is a Mojo::Exception';
like $err,   qr/^test19/,       'right error';
eval { raise 'MyApp::X::Baz', 'test20' };
$err = $@;
isa_ok $err, 'MyApp::X::Baz',   'is a MyApp::X::Baz';
isa_ok $err, 'Mojo::Exception', 'is a Mojo::Exception';
like $err,   qr/^test20/,       'right error again';
eval { raise 'test22' };
$err = $@;
isa_ok $err, 'Mojo::Exception', 'is a Mojo::Exception';
like $err,   qr/^test22/,       'right error';
eval { raise 'MojoTest::X::Foo', 'test21' };
$err = $@;
isa_ok $err, 'MojoTest::X::Foo', 'is a MojoTest::X::Baz';
like $err,   qr/^test21/,        'right error';
eval { raise 'Mojo::Base', 'fail' };
like $@, qr/^Mojo::Base is not a Mojo::Exception subclass/, 'right error';

done_testing();
