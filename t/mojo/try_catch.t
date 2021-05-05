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
  like($test->foo(), qr/3 is not allowed/, 'right result');
};

subtest 'Random order flags' => sub {
  my $test2 = MojoTryCatchBaseTest2->new;
  my $result = $test2->foo();
  isa_ok($result, 'Mojo::Exception', 'Exception handled');
  is($result->message, 'something wrong', 'Exception message is ok');
};

subtest 'Bad flag' => sub {
  eval "package MojoSignaturesTest3; use Mojo::Base -unsupported";
  like $@, qr/Unsupported flag: -unsupported/, 'right error';
};

done_testing();
