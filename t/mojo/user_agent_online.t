#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and TLS
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_TLS} = 1 }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test (developer only!)'
  unless $ENV{TEST_ONLINE};
plan tests => 96;

# "So then I said to the cop, "No, you're driving under the influence...
#  of being a jerk"."
use_ok 'Mojo::IOLoop';
use_ok 'Mojo::Transaction::HTTP';
use_ok 'Mojo::UserAgent';
use_ok 'ojo';

# Make sure user agents dont taint the ioloop
my $loop = Mojo::IOLoop->singleton;
my $ua   = Mojo::UserAgent->new;
my $code;
$ua->get(
  'http://cpan.org' => sub {
    my $tx = pop;
    $code = $tx->res->code;
    $loop->stop;
  }
);
$loop->start;
$ua = undef;
my $ticks     = 0;
my $recurring = $loop->recurring(sub { $ticks++ });
my $idle      = $loop->idle(sub { $loop->stop });
$loop->start;
$loop->drop($recurring);
$loop->drop($idle);
is $ticks, 1,   'loop not tainted';
is $code,  301, 'right status';

# Fresh user agent
$ua = Mojo::UserAgent->new;

# Connection refused
$ua->log->level('fatal');
my $tx = $ua->build_tx(GET => 'http://localhost:99999');
$ua->start($tx);
ok !$tx->is_done, 'transaction is not done';

# Connection refused
$tx = $ua->build_tx(GET => 'http://127.0.0.1:99999');
$ua->start($tx);
ok !$tx->is_done, 'transaction is not done';

# Host does not exist
$tx = $ua->build_tx(GET => 'http://cdeabcdeffoobarnonexisting.com');
$ua->start($tx);
is $tx->error, "Couldn't connect.", 'right error';
ok !$tx->is_done, 'transaction is not done';

# Fresh user agent again
$ua = Mojo::UserAgent->new;

# Keep alive
$ua->get('http://mojolicio.us', sub { Mojo::IOLoop->singleton->stop });
Mojo::IOLoop->singleton->start;
my $kept_alive;
$ua->get(
  'http://mojolicio.us',
  sub {
    my $tx = pop;
    Mojo::IOLoop->singleton->stop;
    $kept_alive = $tx->kept_alive;
  }
);
Mojo::IOLoop->singleton->start;
is $kept_alive, 1, 'connection was kept alive';

# Nested keep alive
my @kept_alive;
$ua->get(
  'http://mojolicio.us',
  sub {
    my ($self, $tx) = @_;
    push @kept_alive, $tx->kept_alive;
    $self->get(
      'http://mojolicio.us',
      sub {
        my ($self, $tx) = @_;
        push @kept_alive, $tx->kept_alive;
        $self->get(
          'http://mojolicio.us',
          sub {
            my ($self, $tx) = @_;
            push @kept_alive, $tx->kept_alive;
            Mojo::IOLoop->singleton->stop;
          }
        );
      }
    );
  }
);
Mojo::IOLoop->singleton->start;
is_deeply \@kept_alive, [1, 1, 1], 'connections kept alive';

# Fresh user agent again
$ua = Mojo::UserAgent->new;

# Custom non keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://cpan.org');
$tx->req->headers->connection('close');
$ua->start($tx);
ok $tx->is_done, 'transaction is done';
is $tx->res->code, 301, 'right status';
like $tx->res->headers->connection, qr/close/i, 'right "Connection" header';

# Oneliner
is g('mojolicio.us')->code,          200, 'right status';
is h('mojolicio.us')->code,          200, 'right status';
is p('mojolicio.us/lalalala')->code, 404, 'right status';
is g('http://mojolicio.us')->code,   200, 'right status';
is p('http://mojolicio.us')->code,   404, 'right status';
is oO('http://mojolicio.us')->code,  200, 'right status';
is oO(POST => 'http://mojolicio.us')->code, 404, 'right status';
my $res = f('search.cpan.org/search' => {query => 'mojolicious'});
like $res->body, qr/Mojolicious/, 'right content';
is $res->code,   200,             'right status';

# Simple request
$tx = $ua->get('cpan.org');
is $tx->req->method, 'GET',             'right method';
is $tx->req->url,    'http://cpan.org', 'right url';
is $tx->res->code,   301,               'right status';

# HTTPS request without TLS support
$tx = $ua->get('https://www.google.com');
ok !!$tx->error, 'request failed';

# Simple request with body
$tx = $ua->get('http://mojolicio.us' => 'Hi there!');
is $tx->req->method, 'GET', 'right method';
is $tx->req->url, 'http://mojolicio.us', 'right url';
is $tx->req->headers->content_length, 9, 'right content length';
is $tx->req->body, 'Hi there!', 'right content';
is $tx->res->code, 200,         'right status';

# Simple form post
$tx =
  $ua->post_form('http://search.cpan.org/search' => {query => 'mojolicious'});
is $tx->req->method, 'POST', 'right method';
is $tx->req->url, 'http://search.cpan.org/search', 'right url';
is $tx->req->headers->content_length, 17, 'right content length';
is $tx->req->body,   'query=mojolicious', 'right content';
like $tx->res->body, qr/Mojolicious/,     'right content';
is $tx->res->code,   200,                 'right status';

# Simple request
$tx = $ua->get('http://www.apache.org');
is $tx->req->method, 'GET',                   'right method';
is $tx->req->url,    'http://www.apache.org', 'right url';
is $tx->req->body,   '',                      'no content';
is $tx->res->code,   200,                     'right status';

# Simple keep alive requests
$tx = $ua->get('http://google.com');
is $tx->req->method, 'GET',               'right method';
is $tx->req->url,    'http://google.com', 'right url';
is $tx->res->code,   301,                 'right status';
$tx = $ua->get('http://www.apache.org');
is $tx->req->method, 'GET',                   'right method';
is $tx->req->url,    'http://www.apache.org', 'right url';
is $tx->res->code,   200,                     'right status';
is $tx->kept_alive, 1, 'connection was kept alive';
$tx = $ua->get('http://www.google.de');
is $tx->req->method, 'GET',                  'right method';
is $tx->req->url,    'http://www.google.de', 'right url';
is $tx->res->code,   200,                    'right status';

# Simple requests with redirect
$ua->max_redirects(3);
$tx = $ua->get('http://www.google.com');
$ua->max_redirects(0);
is $tx->req->method, 'GET',                   'right method';
is $tx->req->url,    'http://www.google.de/', 'right url';
is $tx->res->code,   200,                     'right status';
is $tx->previous->req->method, 'GET',                   'right method';
is $tx->previous->req->url,    'http://www.google.com', 'right url';
is $tx->previous->res->code,   302,                     'right status';

# Simple requests with redirect and no callback
$ua->max_redirects(3);
$tx = $ua->get('http://www.google.com');
$ua->max_redirects(0);
is $tx->req->method, 'GET',                   'right method';
is $tx->req->url,    'http://www.google.de/', 'right url';
is $tx->res->code,   200,                     'right status';
is $tx->previous->req->method, 'GET',                   'right method';
is $tx->previous->req->url,    'http://www.google.com', 'right url';
is $tx->previous->res->code,   302,                     'right status';

# Custom chunked request without callback
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.google.com');
$tx->req->headers->transfer_encoding('chunked');
$tx->req->write_chunk(
  'hello world!' => sub {
    shift->write_chunk('hello world2!' => sub { shift->write_chunk('') });
  }
);
$ua->start($tx);
is_deeply([$tx->error],      ['Bad Request', 400], 'right error');
is_deeply([$tx->res->error], ['Bad Request', 400], 'right error');

# Custom requests with keep alive
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.apache.org');
ok(!$tx->kept_alive, 'connection was not kept alive');
$ua->start($tx);
ok($tx->is_done,    'transaction is done');
ok($tx->kept_alive, 'connection was kept alive');
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.apache.org');
ok(!$tx->kept_alive, 'connection was not kept alive');
$ua->start($tx);
ok($tx->is_done,        'transaction is done');
ok($tx->kept_alive,     'connection was kept alive');
ok($tx->local_address,  'has local address');
ok($tx->local_port > 0, 'has local port');

# Multiple requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.apache.org');
my $tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://www.apache.org');
my $tx3 = Mojo::Transaction::HTTP->new;
$tx3->req->method('GET');
$tx3->req->url->parse('http://www.apache.org');
$ua->start($tx);
$ua->start($tx2);
$ua->start($tx3);
ok($tx->is_done,  'transaction is done');
ok($tx2->is_done, 'transaction is done');
ok($tx3->is_done, 'transaction is done');
is($tx->res->code,  200, 'right status');
is($tx2->res->code, 200, 'right status');
is($tx3->res->code, 200, 'right status');
like($tx2->res->content->asset->slurp, qr/Apache/, 'right content');

# Mixed HEAD and GET requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('HEAD');
$tx->req->url->parse('http://www.apache.org');
$tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://www.apache.org');
$ua->start($tx);
$ua->start($tx2);
ok($tx->is_done,  'transaction is done');
ok($tx2->is_done, 'transaction is done');
is($tx->res->code,  200, 'right status');
is($tx2->res->code, 200, 'right status');
like($tx2->res->content->asset->slurp, qr/Apache/, 'right content');

# Multiple requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.apache.org');
$tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://www.apache.org');
$tx3 = Mojo::Transaction::HTTP->new;
$tx3->req->method('GET');
$tx3->req->url->parse('http://www.apache.org');
my $tx4 = Mojo::Transaction::HTTP->new;
$tx4->req->method('GET');
$tx4->req->url->parse('http://www.apache.org');
$ua->start($tx);
$ua->start($tx2);
$ua->start($tx3);
$ua->start($tx4);
ok($tx->is_done,  'transaction is done');
ok($tx2->is_done, 'transaction is done');
ok($tx3->is_done, 'transaction is done');
ok($tx4->is_done, 'transaction is done');
is($tx->res->code,  200, 'right status');
is($tx2->res->code, 200, 'right status');
is($tx3->res->code, 200, 'right status');
is($tx4->res->code, 200, 'right status');
like($tx2->res->content->asset->slurp, qr/Apache/, 'right content');
