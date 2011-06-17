#!/usr/bin/env perl

use strict;
use warnings;

# Disable IPv6, epoll and kqueue
BEGIN { $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1 }

use Test::More;

use FindBin;
use IO::Socket::INET;
use Mojo::IOLoop;
use Mojo::Transaction::HTTP;
use Mojo::UserAgent;

plan skip_all => 'set TEST_MORBO to enable this test (developer only!)'
  unless $ENV{TEST_MORBO};
plan tests => 40;

# "Morbo wishes these stalwart nomads peace among the Dutch tulips.
#  At least all those windmills will keep them cool.
#  WINDMILLS DO NOT WORK THAT WAY! GOODNIGHT!"
use_ok 'Mojo::Server::Morbo';

# Start
my $port   = Mojo::IOLoop->generate_port;
my $prefix = "$FindBin::Bin/../../script";
my $pid    = open my $server, '-|', $^X, "$prefix/morbo", '--listen',
  "http://*:$port", "$prefix/mojo";
sleep 1
  while !IO::Socket::INET->new(
  Proto    => 'tcp',
  PeerAddr => 'localhost',
  PeerPort => $port
  );

my $ua = Mojo::UserAgent->new;

# Single request without keep alive
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/0/");
$tx->req->headers->connection('close');
$ua->start($tx);
ok $tx->is_done, 'transaction is done';
is $tx->res->code, 200, 'right status';
like $tx->res->headers->connection, qr/close/i, 'right "Connection" header';
like $tx->res->body, qr/Mojo/, 'right content';

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
$ua->start($tx);
$ua->start($tx2);
$ua->start($tx3);
$ua->start($tx4);
ok $tx->is_done,  'transaction is done';
ok $tx2->is_done, 'transaction is done';
ok $tx3->is_done, 'transaction is done';
ok $tx4->is_done, 'transaction is done';
is $tx->res->code,  200, 'right status';
is $tx2->res->code, 200, 'right status';
is $tx3->res->code, 200, 'right status';
is $tx4->res->code, 200, 'right status';
like $tx2->res->content->asset->slurp, qr/Mojo/, 'right content';

# Request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/5/");
$tx->req->headers->expect('fun');
$tx->req->body('Hello Mojo!');
$ua->start($tx);
is $tx->res->code, 200, 'right status';
like $tx->res->headers->connection, qr/Keep-Alive/i,
  'right "Connection" header';
like $tx->res->body, qr/Mojo/, 'right content';

# Second keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/6/");
$ua->start($tx);
is $tx->res->code, 200, 'right status';
is $tx->kept_alive, 1, 'connection was alive';
like $tx->res->headers->connection,
  qr/Keep-Alive/i, 'right "Connection" header';
like $tx->res->body, qr/Mojo/, 'right content';

# Third keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/7/");
$ua->start($tx);
is $tx->res->code, 200, 'right status';
is $tx->kept_alive, 1, 'connection was kept alive';
like $tx->res->headers->connection,
  qr/Keep-Alive/i, 'right "Connection" header';
like $tx->res->body, qr/Mojo/, 'right content';

# Multiple requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse("http://127.0.0.1:$port/8/");
$tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse("http://127.0.0.1:$port/9/");
$ua->start($tx);
$ua->start($tx2);
ok $tx->is_done,  'transaction is done';
ok $tx2->is_done, 'transaction is done';
is $tx->res->code,  200, 'right status';
is $tx2->res->code, 200, 'right status';
like $tx2->res->content->asset->slurp, qr/Mojo/, 'right content';

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
$ua->start($tx);
$ua->start($tx2);
$ua->start($tx3);
$ua->start($tx4);
ok $tx->is_done,  'transaction is done';
ok $tx2->is_done, 'transaction is done';
ok $tx3->is_done, 'transaction is done';
ok $tx4->is_done, 'transaction is done';
is $tx->res->code,  200, 'right status';
is $tx2->res->code, 200, 'right status';
is $tx3->res->code, 200, 'right status';
is $tx4->res->code, 200, 'right status';
like $tx2->res->content->asset->slurp, qr/Mojo/, 'right content';
is $tx3->res->content->asset->slurp,   'foo12',  'right content';

# Stop
kill 'INT', $pid;
sleep 1
  while IO::Socket::INET->new(
  Proto    => 'tcp',
  PeerAddr => 'localhost',
  PeerPort => $port
  );
