use strict;
use warnings;

use Test::More tests => 7;

use FindBin;
use lib "$FindBin::Bin/lib";

use Mojo::Transaction;

use_ok('MojoliciousTest');

# in this case Mojo::Client doesn't work
# as it creates an application instance
# for each transaction

my $app = MojoliciousTest->new;

# check soundness first
{
    my $tx     = Mojo::Transaction->new_get('/foo');
    my $new_tx = $app->handler($tx);
    is($new_tx->res->code, 200);
    like($new_tx->res->body, qr/Hello Mojo from the template \/foo! Hello World!/);
}

# let it die (eventually leads to 404)
{
    my $tx     = Mojo::Transaction->new_get('/foo/willdie');
    my $new_tx = $app->handler($tx);
    is($new_tx->res->code, 404);
    like($new_tx->res->body, qr/File Not Found/);
}

# don't want it to die any more
{
    my $tx     = Mojo::Transaction->new_get('/foo');
    my $new_tx = $app->handler($tx);
    is($new_tx->res->code, 200);
    like($new_tx->res->body, qr/Hello Mojo from the template \/foo! Hello World!/);
}
