#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll and kqueue
BEGIN { $ENV{MOJO_POLL} = 1 }

use Test::More;
plan skip_all => 'Windows is too fragile for this test!' if $^O eq 'MSWin32';

plan tests => 9;

use_ok 'Mojo::Client';

use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => {text => 'works'};

my $client = Mojo::Client->singleton->app(app);

# Server
my $port = $client->ioloop->generate_port;
my $error;
my $id = $client->ioloop->listen(
    tls      => 1,
    tls_cert => 't/certs/server/server.crt',
    tls_key  => 't/certs/server/server.key',
    tls_ca   => 't/certs/ca/ca.crt',
    port     => $port,
    on_read  => sub {
        my ($loop, $id) = @_;
        $loop->write($id => "HTTP/1.1 200 OK\x0d\x0a"
              . "Connection: keep-alive\x0d\x0a"
              . "Content-Length: 6\x0d\x0a\x0d\x0aworks!");
        $loop->drop($id);
    },
    on_error => sub {
        my ($self, $id) = @_;
        $self->drop($id);
        $error = pop;
    }
);

# Fail - no cert
my $tx = $client->get("https://localhost:$port");
ok !$tx->success, 'failed';
like $error, qr/peer did not return a certificate$/, 'no client cert';

# Fail - clear cert
$error = '';
$tx    = $client->cert('')->key('')->get("https://localhost:$port");
ok !$tx->success, 'failed';
like $error, qr/peer did not return a certificate$/, 'no client cert';

# Success - good cert
$tx =
  $client->cert('t/certs/client/client.crt')->key('t/certs/client/client.key')
  ->get("https://localhost:$port");
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Fail - bad cert
$client->ioloop->timer(1 => sub { shift->stop });
$tx =
  $client->cert('t/certs/badclient/badclient.crt')
  ->key('t/certs/badclient/badclient.key')->get("https://localhost:$port");
like $error, qr/^SSL connect accept failed because of handshake problems/,
  'bad client cert';
