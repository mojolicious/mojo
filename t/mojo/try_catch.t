use Mojo::Base -strict;

use Test::More;

BEGIN { plan skip_all => 'Perl 5.34+ required for this test!' if $] < 5.034 }

package MojoTryCatchBaseTest;
use Mojo::Base -base, -try_catch;

sub foo {
  my $self = shift;

  try {
    $self->bar($_) for (0..5);
  }
  catch ($e) {
    return $e;
  }

  return 0;
}

sub bar {
  my($self, $number) = @_;

  if ($number == 3) {
    die "$number is not allowed";
  }

  return 1;
}

package MojoTryCatchBaseTest2;
use Mojo::Base -try_catch, -base, -strict;

use Mojo::Exception qw(raise check);

sub foo {
  my $result;

  try {
    raise 'something wrong'
  }
  catch ($e) {
    check $e => [
      'Mojo::Exception' => sub {$result = $_}
    ];
  }

  return $result;
}

package main;

subtest 'Handle die message' => sub {
  my $test = MojoTryCatchBaseTest->new;
  is($test->foo(), "3 is not allowed at ./t/mojo/try_catch.t line 27.\n", 'right result');
};

subtest 'Random order flags' => sub {
  my $test2 = MojoTryCatchBaseTest2->new;
  isa_ok($test2->foo(), 'Mojo::Exception', 'Exception handled');
};

subtest 'Bad flag' => sub {
  eval "package MojoSignaturesTest3; use Mojo::Base -unsupported";
  like $@, qr/Unsupported flag: -unsupported/, 'right error';
};

done_testing();
