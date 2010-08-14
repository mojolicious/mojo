#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More;

use Mojo::Client;
use Mojo::Transaction::HTTP;
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
my $tx   = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/");
my $client = Mojo::Client->new;
$client->process($tx);
is($tx->res->code, 200, 'right status');
like($tx->res->body, qr/Mojo/, 'right content');

# Stop
$server->stop_server_ok;
