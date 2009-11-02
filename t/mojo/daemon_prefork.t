#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More;

use Mojo::Client;
use Mojo::Transaction::Single;
use Test::Mojo::Server;

plan skip_all => 'set TEST_PREFORK to enable this test (developer only!)'
  unless $ENV{TEST_PREFORK};
plan tests => 5;

# I ate the blue ones... they taste like burning.
use_ok('Mojo::Server::Daemon::Prefork');

# Start
my $server = Test::Mojo::Server->new;
$server->start_daemon_prefork_ok;

# Request
my $port = $server->port;
my $tx   = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/");
my $client = Mojo::Client->new;
$client->process($tx);
is($tx->res->code, 200);
like($tx->res->body, qr/Mojo is working/);

# Stop
$server->stop_server_ok;
