#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll and kqueue
BEGIN { $ENV{MOJO_POLL} = 1 }

use Test::More;
use Mojo::IOLoop;
plan skip_all => 'IO::Socket::SSL 1.34 required for this test!'
  unless Mojo::IOLoop::TLS;
plan tests => 9;

# That does not compute.
# Really?
# Well, it computes a little.
use Mojo::Client;

# Client
my $client = Mojo::Client->singleton;

# Silence
$client->log->level('fatal');

# Server
my $port = $client->ioloop->generate_port;
my $error;
my $id = $client->ioloop->listen(
    port     => $port,
    tls      => 1,
    tls_cert => 't/mojo/certs/server.crt',
    tls_key  => 't/mojo/certs/server.key',
    tls_ca   => 't/mojo/certs/ca.crt',
    on_read  => sub {
        my ($loop, $id) = @_;
        $loop->write($id => "HTTP/1.1 200 OK\x0d\x0a"
              . "Connection: keep-alive\x0d\x0a"
              . "Content-Length: 6\x0d\x0a\x0d\x0aworks!");
        $loop->drop($id);
    },
    on_error => sub {
        shift->drop(shift);
        $error = shift;
    }
);

# No certificate
my $tx = $client->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $error, 'has error';
$error = '';
$tx    = $client->cert('')->key('')->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $error, 'has error';

# Valid certificate
$tx =
  $client->cert('t/mojo/certs/client.crt')->key('t/mojo/certs/client.key')
  ->get("https://localhost:$port");
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Invalid certificate
$tx =
  $client->cert('t/mojo/certs/badclient.crt')
  ->key('t/mojo/certs/badclient.key')->get("https://localhost:$port");
ok $error, 'has error';

# Empty certificate
$tx =
  $client->cert('no file')->key('no file')->get("https://localhost:$port");
ok $error, 'has error';
