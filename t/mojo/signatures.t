use Mojo::Base -strict;

use Test::More;

BEGIN { plan skip_all => 'Perl 5.20+ required for this test!' if $] < 5.020 }

package MojoSignatureBaseTest;
use Mojo::Base -base, -signatures;

sub foo ($self, $bar, $baz) { $bar + $baz }

package main;

my $test = MojoSignatureBaseTest->new;
is($test->foo(23, 24), 47, 'right result');

done_testing();
