use Mojo::Base -strict;

use Test::More;

BEGIN { plan skip_all => 'Perl 5.20+ required for this test!' if $] < 5.020 }

package MojoSignatureBaseTest;
use Mojo::Base -base, -signatures;

sub foo ($self, $bar, $baz) { $bar + $baz }

package MojoSignatureBaseTest2;
use Mojo::Base -signatures, -base;

sub foo ($self, $bar, $baz) { $bar - $baz }

package main;

# Basics
my $test = MojoSignatureBaseTest->new;
is($test->foo(23, 24), 47, 'right result');

# Random order flags
my $test2 = MojoSignatureBaseTest2->new;
is($test2->foo(26, 24), 2, 'right result');

# Bad flag
eval "package MojoSignaturesTest3; use Mojo::Base -unsupported";
like $@, qr/Unsupported flag: -unsupported/, 'right error';

done_testing();
