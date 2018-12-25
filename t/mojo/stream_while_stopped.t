use Mojo::Base -strict;

use Test::More;
use Mojo::IOLoop;

Mojo::IOLoop->client({address => 'localhost'}, sub {});

ok(!exists Mojo::IOLoop->singleton->reactor->{io}, 'no handles created');

done_testing;

1;
