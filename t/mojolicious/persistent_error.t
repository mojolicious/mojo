#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 7;

use FindBin;
use lib "$FindBin::Bin/lib";

use Mojo::Transaction;

use_ok('MojoliciousTest');

my $app = MojoliciousTest->new;

# Check soundness first
my $tx = Mojo::Transaction->new_get('/foo');
$app->handler($tx);
is($tx->res->code, 200);
like($tx->res->body, qr/Hello Mojo from the template \/foo! Hello World!/);

# Let it die (eventually leads to 404)
$tx = Mojo::Transaction->new_get('/foo/willdie');
$app->handler($tx);
is($tx->res->code, 404);
like($tx->res->body, qr/File Not Found/);

# Shouldn't die
$tx = Mojo::Transaction->new_get('/foo');
$app->handler($tx);
is($tx->res->code, 200);
like($tx->res->body, qr/Hello Mojo from the template \/foo! Hello World!/);
