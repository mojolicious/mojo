use Mojo::Base -strict;

use Test::More;

BEGIN { plan skip_all => 'Perl 5.20+ required for this test!' if $] < 5.020 }

package MojoSignatureBaseTest;
use Mojo::Base -base, -signatures;

sub foo ($self, $bar, $baz) { $bar + $baz }

package MojoSignatureBaseTest2;
use Mojo::Base -signatures, -base, -strict;

sub foo ($self, $bar, $baz) { $bar - $baz }

package main;

subtest 'Basics' => sub {
  my $test = MojoSignatureBaseTest->new;
  is($test->foo(23, 24), 47, 'right result');
};

subtest 'Random order flags' => sub {
  my $test2 = MojoSignatureBaseTest2->new;
  is($test2->foo(26, 24), 2, 'right result');
};

subtest 'Bad flag' => sub {
  eval "package MojoSignaturesTest3; use Mojo::Base -unsupported";
  like $@, qr/Unsupported flag: -unsupported/, 'right error';
};

done_testing();
