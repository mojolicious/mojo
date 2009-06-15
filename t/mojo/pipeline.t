#!perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 6;

# Are we there yet?
# No
# Are we there yet?
# No
# Are we there yet?
# No
# ...Where are we going?
use_ok('Mojo::Pipeline');
use_ok('Mojo::Transaction');

# Transactions
my $tx1 = Mojo::Transaction->new_get("http://127.0.0.1:3000/1/");
my $tx2 = Mojo::Transaction->new_get("http://127.0.0.1:3000/2/");

# Pipeline
my $pipe = Mojo::Pipeline->new($tx1, $tx2);

# Set up state to simulate that we're done writing
# (Do not use this in any production code!)
$_->state('read_response') for @{$pipe->{_txs}};
$pipe->{_reader}      = 0;
$pipe->{_writer}      = 2;
$pipe->{_all_written} = 1;

my $responses = <<EOF;
HTTP/1.1 204 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT

HTTP/1.1 200 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT
Content-Type: text/plain
Content-length: 5

1234
EOF

# Read
$pipe->client_read($responses);

ok($tx1->is_done);
ok($tx2->is_done);
is($tx1->res->code, 204);
is($tx2->res->code, 200);
