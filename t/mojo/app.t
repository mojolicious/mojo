#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 44;

# "I was so bored I cut the pony tail off the guy in front of us.
#  Look at me, I'm a grad student.
#  I'm 30 years old and I made $600 last year.
#  Bart, don't make fun of grad students.
#  They've just made a terrible life choice."
use Mojo::IOLoop;
use Mojo::Transaction::HTTP;
use Mojo::UserAgent;

use_ok 'Mojo';
use_ok 'Mojo::HelloWorld';

# Logger
my $logger = Mojo::Log->new;
my $app = Mojo->new({log => $logger});
is $app->log, $logger, 'right logger';

$app = Mojo::HelloWorld->new;
my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton)->app($app);

# Continue
my $port   = $ua->test_server->port;
my $buffer = '';
my $id;
$id = Mojo::IOLoop->client(
  {port => $port} => sub {
    my ($loop, $stream) = @_;
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;
        $buffer .= $chunk;
        Mojo::IOLoop->drop($id) and Mojo::IOLoop->stop
          if $buffer =~ /Mojo is working!/;
        $stream->write('4321')
          if $buffer =~ m#HTTP/1.1 100 Continue.*\x0d\x0a\x0d\x0a#gs;
      }
    );
    $stream->write("GET /1/ HTTP/1.1\x0d\x0a"
        . "Expect: 100-continue\x0d\x0a"
        . "Content-Length: 4\x0d\x0a\x0d\x0a");
  }
);
Mojo::IOLoop->start;
like $buffer, qr#HTTP/1.1 100 Continue#, 'request was continued';

# Pipelined
$buffer = '';
$id     = Mojo::IOLoop->client(
  {port => $port} => sub {
    my ($loop, $stream) = @_;
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;
        $buffer .= $chunk;
        Mojo::IOLoop->drop($id) and Mojo::IOLoop->stop
          if $buffer =~ /Mojo.*Mojo/gs;
      }
    );
    $stream->write("GET /2/ HTTP/1.1\x0d\x0a"
        . "Content-Length: 0\x0d\x0a\x0d\x0a"
        . "GET /3/ HTTP/1.1\x0d\x0a"
        . "Content-Length: 0\x0d\x0a\x0d\x0a");
  }
);
Mojo::IOLoop->start;
like $buffer, qr/Mojo/, 'transactions were pipelined';

# Normal request
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/5/');
$ua->start($tx);
ok $tx->keep_alive, 'will be kept alive';
is $tx->res->code,   200,      'right status';
like $tx->res->body, qr/Mojo/, 'right content';

# Keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/6/');
$ua->start($tx);
ok $tx->keep_alive, 'will be kept alive';
ok $tx->kept_alive, 'was kept alive';
is $tx->res->code,   200,      'right status';
like $tx->res->body, qr/Mojo/, 'right content';

# Non keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/7/');
$tx->req->headers->connection('close');
$ua->start($tx);
ok !$tx->keep_alive, 'will not be kept alive';
ok $tx->kept_alive, 'was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->headers->connection, 'close', 'right "Connection" value';
like $tx->res->body, qr/Mojo/, 'right content';

# Second non keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('/8/');
$tx->req->headers->connection('close');
$ua->start($tx);
ok !$tx->keep_alive, 'will not be kept alive';
ok !$tx->kept_alive, 'was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->headers->connection, 'close', 'right "Connection" value';
like $tx->res->body, qr/Mojo/, 'right content';

# POST request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/9/');
$tx->req->headers->expect('fun');
$tx->req->body('foo bar baz' x 128);
$ua->start($tx);
is $tx->res->code,   200,      'right status';
like $tx->res->body, qr/Mojo/, 'right content';

# POST request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/10/');
$tx->req->headers->expect('fun');
$tx->req->body('bar baz foo' x 128);
$ua->start($tx);
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
$ua->start($tx);
$ua->start($tx2);
ok defined $tx->connection,  'has connection id';
ok defined $tx2->connection, 'has connection id';
ok $tx->is_finished,  'transaction is finished';
ok $tx2->is_finished, 'transaction is finished';

# Form with chunked response
my $params = {};
for my $i (1 .. 10) { $params->{"test$i"} = $i }
my $result = '';
for my $key (sort keys %$params) { $result .= $params->{$key} }
my ($code, $body);
$tx = $ua->post_form("http://127.0.0.1:$port/diag/chunked_params" => $params);
is $tx->res->code, 200, 'right status';
is $tx->res->body, $result, 'right content';

# Upload
($code, $body) = undef;
$tx = $ua->post_form(
  "http://127.0.0.1:$port/diag/upload" => {file => {content => $result}});
is $tx->res->code, 200, 'right status';
is $tx->res->body, $result, 'right content';

# Parallel requests
my $delay = Mojo::IOLoop->delay;
$ua->get('/13/', $delay->begin);
$ua->post('/14/', {Expect => 'fun'}, 'bar baz foo' x 128, $delay->begin);
$ua->get('/15/', $delay->begin);
($tx, $tx2, my $tx3) = $delay->wait;
ok $tx->is_finished, 'transaction is finished';
is $tx->res->body, 'Your Mojo is working!', 'right content';
ok !$tx->error, 'no error';
ok $tx2->is_finished, 'transaction is finished';
is $tx2->res->body, 'Your Mojo is working!', 'right content';
ok !$tx2->error, 'no error';
ok $tx3->is_finished, 'transaction is finished';
is $tx3->res->body, 'Your Mojo is working!', 'right content';
ok !$tx3->error, 'no error';
