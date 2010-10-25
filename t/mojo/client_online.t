#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = $ENV{MOJO_NO_TLS} = 1 }

use Test::More;

plan skip_all => 'set TEST_CLIENT to enable this test (developer only!)'
  unless $ENV{TEST_CLIENT};
plan tests => 101;

# So then I said to the cop, "No, you're driving under the influence...
# of being a jerk".
use_ok 'Mojo::Client';
use_ok 'Mojo::IOLoop';
use_ok 'Mojo::Transaction::HTTP';
use_ok 'ojo';

# Make sure clients dont taint the ioloop
my $loop   = Mojo::IOLoop->new;
my $client = Mojo::Client->new;
my $code;
$client->get(
    'http://cpan.org' => sub {
        my $self = shift;
        $code = $self->res->code;
    }
)->start;
$client = undef;
my $ticks = 0;
$loop->on_tick(sub { $ticks++ });
$loop->on_idle(sub { shift->stop });
$loop->start;
is $ticks, 1,   'loop not tainted';
is $code,  301, 'right status';

# Fresh client
$client = Mojo::Client->new;

# Connection refused
$client->log->level('fatal');
my $tx = $client->build_tx(GET => 'http://localhost:99999');
$client->start($tx);
ok !$tx->is_done, 'transaction is not done';

# Fresh client again
$client = Mojo::Client->new;

# Host does not exist
$tx = $client->build_tx(GET => 'http://cdeabcdeffoobarnonexisting.com');
$client->start($tx);
ok !$tx->is_done, 'transaction is not done';

# Keep alive
my $async = $client->async;
$async->get('http://mojolicio.us', sub { shift->ioloop->stop })->start;
$async->ioloop->start;
my $kept_alive = undef;
$async->get(
    'http://mojolicio.us',
    sub {
        my $self = shift;
        $self->ioloop->stop;
        $kept_alive = shift->kept_alive;
    }
)->start;
$async->ioloop->start;
is $kept_alive, 1, 'connection was kept alive';

# Resolve TXT record
my $record;
$async->ioloop->resolve(
    'google.com',
    'TXT',
    sub {
        my ($self, $records) = @_;
        $record = $records->[0];
        $self->stop;
    }
)->start;
like $record, qr/spf/, 'right record';

# Nested keep alive
my @kept_alive;
$client->async->get(
    'http://mojolicio.us',
    sub {
        my ($self, $tx) = @_;
        push @kept_alive, $tx->kept_alive;
        $self->async->get(
            'http://mojolicio.us',
            sub {
                my ($self, $tx) = @_;
                push @kept_alive, $tx->kept_alive;
                $self->async->get(
                    'http://mojolicio.us',
                    sub {
                        my ($self, $tx) = @_;
                        push @kept_alive, $tx->kept_alive;
                        $self->ioloop->stop;
                    }
                )->start;
            }
        )->start;
    }
)->start;
$client->ioloop->start;
is_deeply \@kept_alive, [1, 1, 1], 'connections kept alive';

# Custom non keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://cpan.org');
$tx->req->headers->connection('close');
$client->start($tx);
ok $tx->is_done, 'transaction is done';
is $tx->res->code, 301, 'right status';
like $tx->res->headers->connection, qr/close/i, 'right "Connection" header';

# Proxy check
my $backup  = $ENV{HTTP_PROXY}  || '';
my $backup2 = $ENV{HTTPS_PROXY} || '';
$ENV{HTTP_PROXY}  = 'http://127.0.0.1';
$ENV{HTTPS_PROXY} = 'https://127.0.0.1';
$client->detect_proxy;
is $client->http_proxy,  'http://127.0.0.1',  'right proxy';
is $client->https_proxy, 'https://127.0.0.1', 'right proxy';
$client->http_proxy(undef);
$client->https_proxy(undef);
is $client->http_proxy,  undef, 'right proxy';
is $client->https_proxy, undef, 'right proxy';
$ENV{HTTP_PROXY}  = $backup;
$ENV{HTTPS_PROXY} = $backup2;

# Oneliner
is g('mojolicious.org')->code,          200, 'right status';
is h('mojolicious.org')->code,          200, 'right status';
is p('mojolicious.org/lalalala')->code, 404, 'right status';
is g('http://mojolicious.org')->code,   200, 'right status';
is p('http://mojolicious.org')->code,   404, 'right status';
is oO('http://mojolicious.org')->code,  200, 'right status';
is oO(POST => 'http://mojolicious.org')->code, 404, 'right status';
my $res = f('search.cpan.org/search' => {query => 'mojolicious'});
like $res->body, qr/Mojolicious/, 'right content';
is $res->code,   200,             'right status';

# Simple request
my ($method, $url);
$code = undef;
$client->get(
    'cpan.org' => sub {
        my $self = shift;
        $method = $self->req->method;
        $url    = $self->req->url;
        $code   = $self->res->code;
    }
)->start;
is $method, 'GET',             'right method';
is $url,    'http://cpan.org', 'right url';
is $code,   301,               'right status';

# HTTPS request without TLS support
$tx = $client->get('https://www.google.com');
ok !!$tx->error, 'request failed';

# Simple request with body
$tx = $client->get('http://mojolicious.org' => 'Hi there!');
is $tx->req->method, 'GET', 'right method';
is $tx->req->url, 'http://mojolicious.org', 'right url';
is $tx->req->headers->content_length, 9, 'right content length';
is $tx->req->body, 'Hi there!', 'right content';
is $tx->res->code, 200,         'right status';

# Simple form post
$tx = $client->post_form(
    'http://search.cpan.org/search' => {query => 'mojolicious'});
is $tx->req->method, 'POST', 'right method';
is $tx->req->url, 'http://search.cpan.org/search', 'right url';
is $tx->req->headers->content_length, 17, 'right content length';
is $tx->req->body,   'query=mojolicious', 'right content';
like $tx->res->body, qr/Mojolicious/,     'right content';
is $tx->res->code,   200,                 'right status';

# Simple request
my $body;
($method, $url, $code) = undef;
$client->get(
    'http://www.apache.org' => sub {
        my $self = shift;
        $method = $self->req->method;
        $url    = $self->req->url;
        $body   = $self->req->body;
        $code   = $self->res->code;
    }
)->start;
is $method, 'GET',                   'right method';
is $url,    'http://www.apache.org', 'right url';
is $body,   '',                      'right content';
is $code,   200,                     'right status';

# Simple parallel requests with keep alive
($method, $url, $code) = undef;
$client->get(
    'http://google.com' => sub {
        my $self = shift;
        $method = $self->req->method;
        $url    = $self->req->url;
        $code   = $self->res->code;
    }
);
my ($method2, $url2, $code2);
$kept_alive = undef;
$client->get(
    'http://www.apache.org' => sub {
        my $self = shift;
        $method2    = $self->req->method;
        $url2       = $self->req->url;
        $code2      = $self->res->code;
        $kept_alive = $self->tx->kept_alive;
    }
);
my ($method3, $url3, $code3);
$client->get(
    'http://www.google.de' => sub {
        my $self = shift;
        $method3 = $self->req->method;
        $url3    = $self->req->url;
        $code3   = $self->res->code;
    }
);
$client->start;
is $method,     'GET',                   'right method';
is $url,        'http://google.com',     'right url';
is $code,       301,                     'right status';
is $method2,    'GET',                   'right method';
is $url2,       'http://www.apache.org', 'right url';
is $code2,      200,                     'right status';
is $kept_alive, 1,                       'connection was kept alive';
is $method3,    'GET',                   'right method';
is $url3,       'http://www.google.de',  'right url';
is $code3,      200,                     'right status';

# Simple requests with redirect
($method, $url, $code, $method2, $url2, $code2) = undef;
$client->max_redirects(3);
$client->get(
    'http://www.google.com' => sub {
        my ($self, $tx) = @_;
        $method  = $tx->req->method;
        $url     = $tx->req->url;
        $code    = $tx->res->code;
        $method2 = $tx->previous->req->method;
        $url2    = $tx->previous->req->url;
        $code2   = $tx->previous->res->code;
    }
)->start;
$client->max_redirects(0);
is $method,  'GET',                   'right method';
is $url,     'http://www.google.de/', 'right url';
is $code,    200,                     'right status';
is $method2, 'GET',                   'right method';
is $url2,    'http://www.google.com', 'right url';
is $code2,   302,                     'right status';

# Simple requests with redirect and no callback
$client->max_redirects(3);
$tx = $client->get('http://www.google.com');
$client->max_redirects(0);
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
$client->start($tx);
is_deeply([$tx->error],      ['Bad Request', 400], 'right error');
is_deeply([$tx->res->error], ['Bad Request', 400], 'right error');

# Custom requests with keep alive
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.apache.org');
ok(!$tx->kept_alive, 'connection was not kept alive');
my $done;
$kept_alive = undef;
$client->queue(
    $tx => sub {
        my ($self, $tx) = @_;
        $done       = $tx->is_done;
        $kept_alive = $tx->kept_alive;
    }
);
$client->start;
ok($done,        'transaction is done');
ok($kept_alive,  'connection was kept alive');
ok($tx->is_done, 'transaction is done');
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.apache.org');
ok(!$tx->kept_alive, 'connection was not kept alive');
my ($address, $port, $port2);
($done, $kept_alive) = undef;
$client->start(
    $tx => sub {
        my ($self, $tx) = @_;
        $done       = $tx->is_done;
        $kept_alive = $tx->kept_alive;
        $address    = $tx->local_address;
        $port       = $tx->local_port;
        $port2      = $tx->remote_port, 80;
    }
);
ok($done,        'transaction is done');
ok($kept_alive,  'connection was kept alive');
ok($address,     'has local address');
ok($port > 0,    'has local port');
ok($tx->is_done, 'transaction is done');

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
$client->start($tx, $tx2, $tx3);
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
$client->start($tx, $tx2);
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
$client->start($tx, $tx2, $tx3, $tx4);
ok($tx->is_done,  'transaction is done');
ok($tx2->is_done, 'transaction is done');
ok($tx3->is_done, 'transaction is done');
ok($tx4->is_done, 'transaction is done');
is($tx->res->code,  200, 'right status');
is($tx2->res->code, 200, 'right status');
is($tx3->res->code, 200, 'right status');
is($tx4->res->code, 200, 'right status');
like($tx2->res->content->asset->slurp, qr/Apache/, 'right content');
