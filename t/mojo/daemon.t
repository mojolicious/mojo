#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More;

# I ate the blue ones... they taste like burning.
use FindBin;
use IO::Socket::INET;
use Mojo::Client;
use Mojo::IOLoop;
use Mojo::Transaction::HTTP;

plan skip_all => 'set TEST_DAEMON to enable this test (developer only!)'
  unless $ENV{TEST_DAEMON};
plan tests => 42;

# Daddy, I'm scared. Too scared to even wet my pants.
# Just relax and it'll come, son.
use_ok('Mojo::Server::Daemon');
use_ok('Mojo::Server::Daemon::Prefork');

# Test sane Mojo::Server subclassing capabilities
my $daemon = Mojo::Server::Daemon->new;
my $max    = $daemon->max_clients;
$daemon = Mojo::Server::Daemon->new(max_clients => $max + 10);
is($daemon->max_clients, $max + 10, 'right max clients value');

# Start
my $port = Mojo::IOLoop->generate_port;
my $pid = open my $server, '-|', $^X, "$FindBin::Bin/../../script/mojo",
  'daemon_prefork', '--listen', "http:\/\/*:$port";
sleep 1
  while !IO::Socket::INET->new(
    Proto    => 'tcp',
    PeerAddr => 'localhost',
    PeerPort => $port
  );

my $client = Mojo::Client->new;

# Single request without keep alive
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/0/");
$tx->req->headers->connection('close');
$client->process($tx);
ok($tx->is_done, 'transaction is done');
is($tx->res->code, 200, 'right status');
like($tx->res->headers->connection, qr/close/i, 'right "Connection" header');
like($tx->res->body,                qr/Mojo/,   'right content');

# Multiple requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/1/");
my $tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse("http://127.0.0.1:$port/2/");
$tx2->req->headers->expect('fun');
$tx2->req->body('foo bar baz');
my $tx3 = Mojo::Transaction::HTTP->new;
$tx3->req->method('GET');
$tx3->req->url->parse("http://127.0.0.1:$port/3/");
my $tx4 = Mojo::Transaction::HTTP->new;
$tx4->req->method('GET');
$tx4->req->url->parse("http://127.0.0.1:$port/4/");
$client->process($tx, $tx2, $tx3, $tx4);
ok($tx->is_done,  'transaction is done');
ok($tx2->is_done, 'transaction is done');
ok($tx3->is_done, 'transaction is done');
ok($tx4->is_done, 'transaction is done');
is($tx->res->code,  200, 'right status');
is($tx2->res->code, 200, 'right status');
is($tx3->res->code, 200, 'right status');
is($tx4->res->code, 200, 'right status');
like($tx2->res->content->asset->slurp, qr/Mojo/, 'right content');

# Request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/5/");
$tx->req->headers->expect('fun');
$tx->req->body('Hello Mojo!');
$client->process($tx);
is($tx->res->code, 200, 'right status');
like($tx->res->headers->connection,
    qr/Keep-Alive/i, 'right "Connection" header');
like($tx->res->body, qr/Mojo/, 'right content');

# Second keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/6/");
$client->process($tx);
is($tx->res->code,  200, 'right status');
is($tx->kept_alive, 1,   'connection was alive');
like($tx->res->headers->connection,
    qr/Keep-Alive/i, 'right "Connection" header');
like($tx->res->body, qr/Mojo/, 'right content');

# Third keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/7/");
$client->process($tx);
is($tx->res->code,  200, 'right status');
is($tx->kept_alive, 1,   'connection was kept alive');
like($tx->res->headers->connection,
    qr/Keep-Alive/i, 'right "Connection" header');
like($tx->res->body, qr/Mojo/, 'right content');

# Multiple requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/8/");
$tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse("http://127.0.0.1:$port/9/");
$client->process($tx, $tx2);
ok($tx->is_done,  'transaction is done');
ok($tx2->is_done, 'transaction is done');
is($tx->res->code,  200, 'right status');
is($tx2->res->code, 200, 'right status');
like($tx2->res->content->asset->slurp, qr/Mojo/, 'right content');

# Multiple requests with a chunked response
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/10/");
$tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse("http://127.0.0.1:$port/11/");
$tx2->req->headers->expect('fun');
$tx2->req->body('foo bar baz');
$tx3 = Mojo::Transaction::HTTP->new;
$tx3->req->method('GET');
$tx3->req->url->parse(
    "http://127.0.0.1:$port/diag/chunked_params?a=foo&b=12");
$tx4 = Mojo::Transaction::HTTP->new;
$tx4->req->method('GET');
$tx4->req->url->parse("http://127.0.0.1:$port/13/");
$client->process($tx, $tx2, $tx3, $tx4);
ok($tx->is_done,  'transaction is done');
ok($tx2->is_done, 'transaction is done');
ok($tx3->is_done, 'transaction is done');
ok($tx4->is_done, 'transaction is done');
is($tx->res->code,  200, 'right status');
is($tx2->res->code, 200, 'right status');
is($tx3->res->code, 200, 'right status');
is($tx4->res->code, 200, 'right status');
like($tx2->res->content->asset->slurp, qr/Mojo/, 'right content');
is($tx3->res->content->asset->slurp, 'foo12', 'right content');

# Stop
kill $^O eq 'MSWin32' ? 'KILL' : 'INT', $pid;
sleep 1
  while IO::Socket::INET->new(
    Proto    => 'tcp',
    PeerAddr => 'localhost',
    PeerPort => $port
  );
