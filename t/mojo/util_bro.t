use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Mojo::Util;

BEGIN {
  plan skip_all => 'IO::Compress::Brotli 0.004001+ required for this test!'
    unless Mojo::Util->IO_COMPRESS_BROTLI;
}

# bro/unbro
my $uncompressed = 'a' x 1000;
my $compressed   = Mojo::Util::bro($uncompressed);
isnt $compressed, $uncompressed, 'string changed';
ok length $compressed < length $uncompressed, 'string is shorter';
my $result = Mojo::Util::unbro($compressed, 1_000);
is $result, $uncompressed, 'same string';

done_testing();
