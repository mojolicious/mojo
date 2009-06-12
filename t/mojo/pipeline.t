#!perl

use strict;
use warnings;

use Test::More;

plan skip_all => 'set TEST_PIPELINE to enable this test'
  unless $ENV{TEST_PIPELINE};
plan tests => 6;

# Grandpa: Are we there yet?
# Homer: No
# Grandpa: Are we there yet?
# Homer: No
# Grandpa: Are we there yet?
# Homer: No
# Grandpa: ........Where are we going? 

use_ok('Mojo::Pipeline');
use_ok('Mojo::Transaction');

# Set-up Transactions
my $tx1 = Mojo::Transaction->new_get("http://127.0.0.1:3000/1/");
my $tx2 = Mojo::Transaction->new_get("http://127.0.0.1:3000/2/");

# Set-up Pipeline
my $pipe = Mojo::Pipeline->new($tx1, $tx2);

# set up state to simulate that we're done writing
# NOTE: mucks with private state vars
# NOTE: DO NOT use this in any production code!
foreach (@{$pipe->{_txs}}) {
  $_->state('read_response');
}
$pipe->{_reader} = 0;
$pipe->{_writer} = 2;
$pipe->{_all_written} = 1;

my $responses = <<ENDOFRESPONSES;
HTTP/1.1 204 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT

HTTP/1.1 200 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT
Content-Type: text/plain
Content-length: 5

1234
ENDOFRESPONSES

# Need to spin?
$pipe->client_read($responses);

ok($tx1->is_done);
ok($tx2->is_done);
is($tx1->res->code, 204);
is($tx2->res->code, 200);

