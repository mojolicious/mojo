#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More tests => 47;

use_ok 'Mojo::Client';

# The strong must protect the sweet.
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => {text => 'works'};

my $client = Mojo::Client->singleton->app(app);

# Server
my $port   = $client->ioloop->generate_port;
my $buffer = {};
my $last;
my $id = $client->ioloop->listen(
    port      => $port,
    on_accept => sub {
        my ($loop, $id) = @_;
        $last = $id;
        $buffer->{$id} = '';
    },
    on_read => sub {
        my ($loop, $id, $chunk) = @_;
        $buffer->{$id} .= $chunk;
        if (index $buffer->{$id}, "\x0d\x0a\x0d\x0a") {
            delete $buffer->{$id};
            $loop->write($id => "HTTP/1.1 200 OK\x0d\x0a"
                  . "Connection: keep-alive\x0d\x0a"
                  . "Content-Length: 6\x0d\x0a\x0d\x0aworks!");
        }
    },
    on_error => sub {
        my ($self, $id) = @_;
        delete $buffer->{$id};
    }
);

# Broken server (missing Content-Length header)
my $port2   = $client->ioloop->generate_port;
my $buffer2 = {};
$client->ioloop->listen(
    port      => $port2,
    on_accept => sub {
        my ($loop, $id) = @_;
        $buffer2->{$id} = '';
    },
    on_read => sub {
        my ($loop, $id, $chunk) = @_;
        $buffer2->{$id} .= $chunk;
        if (index $buffer2->{$id}, "\x0d\x0a\x0d\x0a") {
            delete $buffer2->{$id};
            $loop->write(
                $id => "HTTP/1.1 200 OK\x0d\x0a"
                  . "Connection: close\x0d\x0a\x0d\x0aworks too!",
                sub { shift->drop(shift) }
            );
        }
    },
    on_error => sub {
        my ($self, $id) = @_;
        delete $buffer2->{$id};
    }
);

# GET /
my $tx = $client->get('/');
ok $tx->success, 'successful';
is $tx->res->code, 200,     'right status';
is $tx->res->body, 'works', 'right content';

# GET / (missing Content-Lengt header)
$tx = $client->get("http://localhost:$port2/");
ok $tx->success,    'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->keep_alive, 0, 'keep connection not alive';
is $tx->res->code, 200,          'right status';
is $tx->res->body, 'works too!', 'no content';

# GET / (mock server)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'no content';

# GET / (mock server again)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, 1, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'no content';

# Close connection (bypassing safety net)
$client->ioloop->_drop_immediately($last);

# GET / (mock server closed connection)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'no content';

# GET / (mock server again)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, 1, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'no content';

# Close connection (bypassing safety net)
$client->ioloop->_drop_immediately($last);

# GET / (mock server closed connection)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'no content';

# GET / (mock server again)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, 1, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'no content';

# Taint connection (on UNIX)
$^O eq 'MSWin32'
  ? $client->ioloop->_drop_immediately($last)
  : $client->ioloop->write($last => 'broken!');

# GET / (mock server tainted connection)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'no content';

# GET / (mock server again)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, 1, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'no content';

# Taint connection (on UNIX)
$^O eq 'MSWin32'
  ? $client->ioloop->_drop_immediately($last)
  : $client->ioloop->write($last => 'broken!');

# GET / (mock server tainted connection)
$tx = $client->get("http://localhost:$port/mock");
ok $tx->success, 'successful';
is $tx->kept_alive, undef, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'no content';

# Nested keep alive
my @kept_alive;
$client->async->get(
    '/',
    sub {
        my ($self, $tx) = @_;
        push @kept_alive, $tx->kept_alive;
        $self->async->get(
            '/',
            sub {
                my ($self, $tx) = @_;
                push @kept_alive, $tx->kept_alive;
                $self->async->get(
                    '/',
                    sub {
                        my ($self, $tx) = @_;
                        push @kept_alive, $tx->kept_alive;
                        $self->async->ioloop->stop;
                    }
                )->start;
            }
        )->start;
    }
)->start;
$client->async->ioloop->start;
is_deeply \@kept_alive, [undef, 1, 1], 'connections kept alive';

# Simple nested keep alive with timers
@kept_alive = ();
my $async = $client->async;
my $loop  = $async->ioloop;
$async->get(
    '/',
    sub {
        push @kept_alive, pop->kept_alive;
        $loop->timer(
            '0.25' => sub {
                $async->get(
                    '/',
                    sub {
                        push @kept_alive, pop->kept_alive;
                        $loop->timer('0.25' => sub { $loop->stop });
                    }
                )->start;
            }
        );
    }
)->start;
$loop->start;
is_deeply \@kept_alive, [1, 1], 'connections kept alive';
