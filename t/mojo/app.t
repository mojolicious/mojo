#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More tests => 43;

# I was so bored I cut the pony tail off the guy in front of us.
# Look at me, I'm a grad student. I'm 30 years old and I made $600 last year.
# Bart, don't make fun of grad students.
# They've just made a terrible life choice.
use_ok 'Mojo';
use_ok 'Mojo::Client';
use_ok 'Mojo::Transaction::HTTP';
use_ok 'Mojo::HelloWorld';

# Logger
my $logger = Mojo::Log->new;
my $app = Mojo->new({log => $logger});
is $app->log, $logger, 'right logger';

$app = Mojo::HelloWorld->new;
my $client = Mojo::Client->new->app($app);

# Continue
my $port   = $client->test_server;
my $buffer = '';
$client->ioloop->connect(
    address    => 'localhost',
    port       => $port,
    on_connect => sub {
        my ($self, $id, $chunk) = @_;
        $self->write($id,
                "GET /1/ HTTP/1.1\x0d\x0a"
              . "Expect: 100-continue\x0d\x0a"
              . "Content-Length: 4\x0d\x0a\x0d\x0a");
    },
    on_read => sub {
        my ($self, $id, $chunk) = @_;
        $buffer .= $chunk;
        $self->drop($id) and $self->stop if $buffer =~ /Mojo is working!/;
        $self->write($id, '4321')
          if $buffer =~ /HTTP\/1.1 100 Continue.*\x0d\x0a\x0d\x0a/gs;
    }
);
$client->ioloop->start;
like $buffer, qr/HTTP\/1.1 100 Continue/, 'request was continued';

# Pipelined
$buffer = '';
$client->ioloop->connect(
    address    => 'localhost',
    port       => $port,
    on_connect => sub {
        my ($self, $id) = @_;
        $self->write($id,
                "GET /2/ HTTP/1.1\x0d\x0a"
              . "Content-Length: 0\x0d\x0a\x0d\x0a"
              . "GET /3/ HTTP/1.1\x0d\x0a"
              . "Content-Length: 0\x0d\x0a\x0d\x0a");
    },
    on_read => sub {
        my ($self, $id, $chunk) = @_;
        $buffer .= $chunk;
        $self->drop($id) and $self->stop if $buffer =~ /Mojo.*Mojo/gs;
    }
);
$client->ioloop->start;
like $buffer, qr/Mojo/, 'transactions were pipelined';

# Normal request
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/5/');
$client->start($tx);
ok $tx->keep_alive, 'will be kept alive';
is $tx->res->code,   200,      'right status';
like $tx->res->body, qr/Mojo/, 'right content';

# Keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/6/');
$client->start($tx);
ok $tx->keep_alive, 'will be kept alive';
ok $tx->kept_alive, 'was kept alive';
is $tx->res->code,   200,      'right status';
like $tx->res->body, qr/Mojo/, 'right content';

# Non keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/7/');
$tx->req->headers->connection('close');
$client->start($tx);
ok !$tx->keep_alive, 'will not be kept alive';
ok $tx->kept_alive, 'was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->headers->connection, 'Close', 'right "Connection" value';
like $tx->res->body, qr/Mojo/, 'right content';

# Second non keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/8/');
$tx->req->headers->connection('close');
$client->start($tx);
ok !$tx->keep_alive, 'will not be kept alive';
ok !$tx->kept_alive, 'was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->headers->connection, 'Close', 'right "Connection" value';
like $tx->res->body, qr/Mojo/, 'right content';

# POST request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/9/');
$tx->req->headers->expect('fun');
$tx->req->body('foo bar baz' x 128);
$client->start($tx);
is $tx->res->code,   200,      'right status';
like $tx->res->body, qr/Mojo/, 'right content';

# POST request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/10/');
$tx->req->headers->expect('fun');
$tx->req->body('bar baz foo' x 128);
$client->start($tx);
ok defined $tx->connection, 'has connection id';
is $tx->res->code,   200,      'right status';
like $tx->res->body, qr/Mojo/, 'right content';

# Multiple requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/11/');
my $tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('/12/');
$client->start($tx, $tx2);
ok defined $tx->connection,  'has connection id';
ok defined $tx2->connection, 'has connection id';
ok $tx->is_done,  'transaction is done';
ok $tx2->is_done, 'transaction is done';

# Multiple requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/13/');
$tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('POST');
$tx2->req->url->parse('/14/');
$tx2->req->headers->expect('fun');
$tx2->req->body('bar baz foo' x 128);
my $tx3 = Mojo::Transaction::HTTP->new;
$tx3->req->method('GET');
$tx3->req->url->parse('/15/');
$client->start($tx, $tx2, $tx3);
ok $tx->is_done, 'transaction is done';
ok !$tx->error, 'has no errors';
ok $tx2->is_done, 'transaction is done';
ok !$tx2->error, 'has no error';
ok $tx3->is_done, 'transaction is done';
ok !$tx3->error, 'has no error';

# Form with chunked response
my $params = {};
for my $i (1 .. 10) { $params->{"test$i"} = $i }
my $result = '';
for my $key (sort keys %$params) { $result .= $params->{$key} }
my ($code, $body);
$client->post_form(
    "http://127.0.0.1:$port/diag/chunked_params" => $params => sub {
        my $self = shift;
        $code = $self->res->code;
        $body = $self->res->body;
    }
)->start;
is $code, 200, 'right status';
is $body, $result, 'right content';

# Upload
($code, $body) = undef;
$client->post_form(
    "http://127.0.0.1:$port/diag/upload" => {file => {content => $result}} =>
      sub {
        my $self = shift;
        $code = $self->res->code;
        $body = $self->res->body;
    }
)->start;
is $code, 200, 'right status';
is $body, $result, 'right content';
