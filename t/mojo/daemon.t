#!perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More;

use Mojo::Client;
use Mojo::Pipeline;
use Mojo::Transaction;
use Test::Mojo::Server;

plan skip_all => 'set TEST_DAEMON to enable this test (developer only!)'
  unless $ENV{TEST_DAEMON};
plan tests => 31;

# Daddy, I'm scared. Too scared to even wet my pants.
# Just relax and it'll come, son.
use_ok('Mojo::Server::Daemon');

# Test sane Mojo::Server subclassing capabilities
my $daemon = Mojo::Server::Daemon->new;
my $size   = $daemon->listen_queue_size;
$daemon = Mojo::Server::Daemon->new(listen_queue_size => $size + 10);
is($daemon->listen_queue_size, $size + 10);

# Start
my $server = Test::Mojo::Server->new;
$server->start_daemon_ok;

my $port = $server->port;

my $client = Mojo::Client->new;
$client->continue_timeout(60);

# Pipelined with 100 Continue
my $tx  = Mojo::Transaction->new_get("http://127.0.0.1:$port/1/");
my $tx2 = Mojo::Transaction->new_get("http://127.0.0.1:$port/2/");
$tx2->req->headers->expect('100-continue');
$tx2->req->body('foo bar baz');
my $tx3 = Mojo::Transaction->new_get("http://127.0.0.1:$port/3/");
my $tx4 = Mojo::Transaction->new_get("http://127.0.0.1:$port/4/");
$client->process_all(Mojo::Pipeline->new($tx, $tx2, $tx3, $tx4));
ok($tx->is_done);
ok($tx2->is_done);
ok($tx3->is_done);
ok($tx4->is_done);
is($tx->res->code,  200);
is($tx2->res->code, 200);
is($tx2->continued, 1);
is($tx3->res->code, 200);
is($tx4->res->code, 200);
like($tx2->res->content->file->slurp, qr/Mojo is working/);

# 100 Continue request
$tx =
  Mojo::Transaction->new_get("http://127.0.0.1:$port/5/",
    Expect => '100-continue');
$tx->req->body('Hello Mojo!');
$client->process_all($tx);
is($tx->res->code, 200);
is($tx->continued, 1);
like($tx->res->headers->connection, qr/Keep-Alive/i);
like($tx->res->body,                qr/Mojo is working/);

# Second keep alive request
$tx = Mojo::Transaction->new_get("http://127.0.0.1:$port/6/");
$client->process_all($tx);
is($tx->res->code,  200);
is($tx->kept_alive, 1);
like($tx->res->headers->connection, qr/Keep-Alive/i);
like($tx->res->body,                qr/Mojo is working/);

# Third keep alive request
$tx = Mojo::Transaction->new_get("http://127.0.0.1:$port/7/");
$client->process_all($tx);
is($tx->res->code,  200);
is($tx->kept_alive, 1);
like($tx->res->headers->connection, qr/Keep-Alive/i);
like($tx->res->body,                qr/Mojo is working/);

# Pipelined
$tx  = Mojo::Transaction->new_get("http://127.0.0.1:$port/8/");
$tx2 = Mojo::Transaction->new_get("http://127.0.0.1:$port/9/");
$client->process_all(Mojo::Pipeline->new($tx, $tx2));
ok($tx->is_done);
ok($tx2->is_done);
is($tx->res->code,  200);
is($tx2->res->code, 200);
like($tx2->res->content->file->slurp, qr/Mojo is working/);

# Stop
$server->stop_server_ok;
