#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 6;

use Mojo::Client;
use Mojo::Transaction;
use Test::Mojo::Server;

# Daddy, I'm scared. Too scared to even wet my pants.
# Just relax and it'll come, son.
use_ok('Mojo::Server::Daemon');

# Start
my $server = Test::Mojo::Server->new;
$server->start_daemon_ok;

# 100 Continue request
my $port = $server->port;
my $tx = Mojo::Transaction->new_get("http://127.0.0.1:$port/",
    Expect => '100-continue'
);
$tx->req->body('Hello Mojo!');
my $client = Mojo::Client->new;
$client->continue_timeout(60);
$client->process_all($tx);
is($tx->res->code, 200);
is($tx->continued, 1);
like($tx->res->body, qr/Mojo is working/);

# Stop
$server->stop_server_ok;