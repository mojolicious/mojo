use Mojo::Base -strict;

use Test::More;
use Mojo::Exception;

# Basics
my $e = Mojo::Exception->new;
is $e->message, 'Exception!', 'right message';
is "$e", 'Exception!', 'right message';
$e = Mojo::Exception->new('Test!');
is $e->message, 'Test!', 'right message';
is "$e", 'Test!', 'right message';

# Throwing
eval {

  # test

  my $wrapper = sub { Mojo::Exception->throw('Works!') };
  $wrapper->();

  # test

};
$e = $@;
isa_ok $e, 'Mojo::Exception', 'right class';
is $e,     'Works!',          'right result';
like $e->filename, qr/exception\.t/, 'right name';
like $e->frames->[0][1],     qr/exception\.t/, 'right file';
is $e->lines_before->[0][0], 15,               'right number';
is $e->lines_before->[0][1], 'eval {',         'right line';
is $e->lines_before->[1][0], 16,               'right number';
ok !$e->lines_before->[1][1], 'empty line';
is $e->lines_before->[2][0], 17,         'right number';
is $e->lines_before->[2][1], '  # test', 'right line';
is $e->lines_before->[3][0], 18,         'right number';
ok !$e->lines_before->[3][1], 'empty line';
is $e->lines_before->[4][0], 19, 'right number';
is $e->lines_before->[4][1],
  "  my \$wrapper = sub { Mojo::Exception->throw('Works!') };", 'right line';
is $e->line->[0], 20, 'right number';
is $e->line->[1], "  \$wrapper->();", 'right line';
is $e->lines_after->[0][0], 21, 'right number';
ok !$e->lines_after->[0][1], 'empty line';
is $e->lines_after->[1][0], 22,         'right number';
is $e->lines_after->[1][1], '  # test', 'right line';
is $e->lines_after->[2][0], 23,         'right number';
ok !$e->lines_after->[2][1], 'empty line';
is $e->lines_after->[3][0], 24,         'right number';
is $e->lines_after->[3][1], '};',       'right line';
is $e->lines_after->[4][0], 25,         'right number';
is $e->lines_after->[4][1], '$e = $@;', 'right line';

done_testing();
