#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More tests => 29;

# Oh, dear. She’s stuck in an infinite loop and he’s an idiot.
# Well, that’s love for you.
use IO::Socket::INET;
use Mojolicious::Lite;
use Mojo::Client;

# Mojolicious::Lite and ojo
use ojo;

# Silence
app->log->level('fatal');

# Avoid exception template
app->renderer->root(app->home->rel_dir('public'));

# GET /link
get '/link' => sub {
    my $self = shift;
    $self->render(text => $self->url_for('index')->to_abs);
};

# WebSocket /
my $flag;
websocket '/' => sub {
    my $self = shift;
    $self->on_finish(sub { $flag += 4 });
    $self->on_message(
        sub {
            my ($self, $message) = @_;
            my $url = $self->url_for->to_abs;
            $self->send_message("${message}test2$url");
            $flag = 20;
        }
    );
} => 'index';

# WebSocket /socket
websocket '/socket' => sub {
    my $self = shift;
    $self->send_message($self->req->headers->host);
    $self->finish;
};

# WebSocket /early_start
websocket '/early_start' => sub {
    my $self = shift;
    $self->send_message('test1');
    $self->on_message(
        sub {
            my ($self, $message) = @_;
            $self->send_message("${message}test2");
            $self->finish;
        }
    );
};

# WebSocket /denied
my ($handshake, $denied) = 0;
websocket '/denied' => sub {
    my $self = shift;
    $self->tx->handshake->on_finish(sub { $handshake += 2 });
    $self->on_finish(sub                { $denied    += 1 });
    $self->render(text => 'denied', status => 403);
};

# WebSocket /subreq
my $subreq = 0;
websocket '/subreq' => sub {
    my $self = shift;
    $self->client->async->websocket(
        '/echo' => sub {
            my $client = shift;
            $client->on_message(
                sub {
                    my ($client, $message) = @_;
                    $self->send_message($message);
                    $client->finish;
                    $self->finish;
                }
            );
            $client->send_message('test1');
        }
    )->start;
    $self->send_message('test0');
    $self->on_finish(sub { $subreq += 3 });
};

# WebSocket /echo
websocket '/echo' => sub {
    shift->on_message(
        sub {
            my ($self, $message) = @_;
            $self->send_message($message);
        }
    );
};

# WebSocket /dead
websocket '/dead' => sub { die 'i see dead processes' };

# WebSocket /foo
websocket '/foo' =>
  sub { shift->rendered->res->code('403')->message("i'm a teapot") };

# WebSocket /deadcallback
websocket '/deadcallback' => sub {
    my $self = shift;
    $self->on_message(sub { die 'i see dead callbacks' });
};

my $client = Mojo::Client->singleton->app(app);

# GET /link
my $res = $client->get('/link')->success;
is $res->code, 200, 'right status';
like $res->body, qr/ws\:\/\/localhost\:\d+\//, 'right content';

# WebSocket /
my $result;
$client->websocket(
    '/' => sub {
        my $self = shift;
        $self->on_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->finish;
            }
        );
        $self->send_message('test1');
    }
)->start;
like $result, qr/test1test2ws\:\/\/localhost\:\d+\//, 'right result';

# WebSocket / (ojo)
$result = undef;
w '/' => sub {
    shift->on_message(
        sub {
            shift->finish;
            $result = shift;
        }
    )->send_message('test1');
};
like $result, qr/test1test2ws\:\/\/localhost\:\d+\//, 'right result';

# WebSocket /socket (using an already prepared socket)
my $peer  = $client->test_server;
my $local = $client->ioloop->generate_port;
$result = undef;
my $tx     = $client->build_websocket_tx('ws://lalala/socket');
my $socket = IO::Socket::INET->new(
    PeerAddr  => 'localhost',
    PeerPort  => $peer,
    LocalPort => $local
);
$tx->connection($socket);
my $port;
$client->start(
    $tx => sub {
        my $self = shift;
        $self->on_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->finish;
            }
        );
        $port = $self->ioloop->local_info($self->tx->connection)->{port};
    }
);
is $result, 'lalala', 'right result';
is $port, $local, 'right local port';

# WebSocket /early_start (server directly sends a message)
my $flag2;
$result = undef;
$client->websocket(
    '/early_start' => sub {
        my $self = shift;
        $self->on_finish(sub { $flag2 += 5 });
        $self->on_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->send_message('test3');
                $flag2 = 18;
            }
        );
    }
)->start;
is $result, 'test3test2', 'right result';
is $flag2,  23,           'finished callback';

# WebSocket /denied (connection denied)
my $code = undef;
$client->websocket('/denied' => sub { $code = shift->res->code })->start;
is $code,      403, 'right status';
is $handshake, 2,   'finished handshake';
is $denied,    1,   'finished websocket';

# WebSocket /subreq
my $finished = 0;
($code, $result) = undef;
$client->websocket(
    '/subreq' => sub {
        my $self = shift;
        $code   = $self->res->code;
        $result = '';
        $self->on_message(
            sub {
                my ($self, $message) = @_;
                $result .= $message;
                $self->finish if $message eq 'test1';
            }
        );
        $self->on_finish(sub { $finished += 4 });
    }
)->start;
is $code,     101,          'right status';
is $result,   'test0test1', 'right result';
is $finished, 4,            'finished client websocket';
is $subreq,   3,            'finished server websocket';

# WebSocket /subreq (async)
my $running = 2;
my ($code2, $result2);
($code, $result) = undef;
$client->async->websocket(
    '/subreq' => sub {
        my $self = shift;
        $code   = $self->res->code;
        $result = '';
        $self->on_message(
            sub {
                my ($self, $message) = @_;
                $result .= $message;
                $self->finish and $running-- if $message eq 'test1';
                $self->ioloop->on_idle(sub { shift->stop }) unless $running;
            }
        );
        $self->on_finish(sub { $finished += 1 });
    }
)->start;
$client->async->websocket(
    '/subreq' => sub {
        my $self = shift;
        $code2   = $self->res->code;
        $result2 = '';
        $self->on_message(
            sub {
                my ($self, $message) = @_;
                $result2 .= $message;
                $self->finish and $running-- if $message eq 'test1';
                $self->ioloop->on_idle(sub { shift->stop }) unless $running;
            }
        );
        $self->on_finish(sub { $finished += 2 });
    }
)->start;
$client->ioloop->start;
is $code,     101,          'right status';
is $result,   'test0test1', 'right result';
is $code2,    101,          'right status';
is $result2,  'test0test1', 'right result';
is $finished, 7,            'finished client websocket';
is $subreq,   9,            'finished server websocket';

# WebSocket /dead (dies)
$code = undef;
my ($done, $websocket, $message);
$client->websocket(
    '/dead' => sub {
        my $self = shift;
        $done      = $self->tx->is_done;
        $websocket = $self->tx->is_websocket;
        $code      = $self->res->code;
        $message   = $self->res->message;
    }
)->start;
is $done,      1,                       'transaction is done';
is $websocket, 0,                       'no websocket';
is $code,      500,                     'right status';
is $message,   'Internal Server Error', 'right message';

# WebSocket /foo (forbidden)
($websocket, $code, $message) = undef;
$client->websocket(
    '/foo' => sub {
        my $self = shift;
        $websocket = $self->tx->is_websocket;
        $code      = $self->res->code;
        $message   = $self->res->message;
    }
)->start;
is $websocket, 0,              'no websocket';
is $code,      403,            'right status';
is $message,   "i'm a teapot", 'right message';

# WebSocket /deadcallback (dies in callback)
$client->websocket(
    '/deadcallback' => sub {
        my $self = shift;
        $self->send_message('test1');
    }
)->start;

# Server side "finished" callback
is $flag, 24, 'finished callback';
