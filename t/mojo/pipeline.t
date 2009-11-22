#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 54;

# Are we there yet?
# No
# Are we there yet?
# No
# Are we there yet?
# No
# ...Where are we going?
use_ok('Mojo::Transaction::Pipeline');
use_ok('Mojo::Transaction::Single');

# Vanilla Pipeline
my $tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://127.0.0.1:3000/1/');
my $tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://127.0.0.1:3000/2/');
my $pipe = Mojo::Transaction::Pipeline->new($tx, $tx2);
$_->state('read_response') for @{$pipe->active};
$pipe->_all_written(1);
my $responses = <<EOF;
HTTP/1.1 204 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT

HTTP/1.1 200 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT
Content-Type: text/plain
Content-length: 5

1234
EOF
$pipe->client_read($responses);
ok($pipe->is_done);
ok($tx->is_done);
ok($tx2->is_done);
is($tx->res->code,  204);
is($tx2->res->code, 200);

# HEAD request
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://127.0.0.1:3000/3/');
$tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('HEAD');
$tx2->req->url->parse('http://127.0.0.1:3000/4/');
$pipe = Mojo::Transaction::Pipeline->new($tx, $tx2);
$_->state('read_response') for @{$pipe->active};
$pipe->_all_written(1);
$responses = <<EOF;
HTTP/1.1 404 Not Found
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT

HTTP/1.1 200 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT
Content-Type: text/plain
Content-length: 200

EOF
$pipe->client_read($responses);
ok($pipe->is_done);
ok($tx->is_done);
ok($tx2->is_done);
is($tx->res->code,  404);
is($tx2->res->code, 200);

# HEAD request followed by regular request
$tx = Mojo::Transaction::Single->new;
$tx->req->method('HEAD');
$tx->req->url->parse('http://127.0.0.1:3000/5/');
$tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://127.0.0.1:3000/6/');
$pipe = Mojo::Transaction::Pipeline->new($tx, $tx2);
$_->state('read_response') for @{$pipe->active};
$pipe->_all_written(1);
$responses = <<EOF;
HTTP/1.1 200 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT
Content-Type: text/plain
Content-length: 200

HTTP/1.1 500 Internal Server Error
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT
Content-Type: text/plain
Content-length: 5

1234
EOF
$pipe->client_read($responses);
ok($pipe->is_done);
ok($tx->is_done);
ok($tx2->is_done);
is($tx->res->code,  200);
is($tx2->res->code, 500);

# Unexpected 1xx response
$tx = Mojo::Transaction::Single->new;
$tx->req->method('HEAD');
$tx->req->url->parse('http://127.0.0.1:3000/9/');
$tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://127.0.0.1:3000/10/');
$pipe = Mojo::Transaction::Pipeline->new($tx, $tx2);
$_->state('read_response') for @{$pipe->active};
$pipe->_all_written(1);
$responses = <<EOF;
HTTP/1.1 151 Weird

HTTP/1.1 152 Weirder

HTTP/1.1 200 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT
Content-Type: text/plain
Content-length: 2000

HTTP/1.1 204 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT

EOF
$pipe->client_read($responses);
ok($pipe->is_done);
ok($tx->is_done);
ok($tx2->is_done);
is($tx->res->code,  200);
is($tx2->res->code, 204);

# Unexpected 1xx response (variation)
$tx = Mojo::Transaction::Single->new;
$tx->req->method('HEAD');
$tx->req->url->parse('http://127.0.0.1:3000/11/');
$tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://127.0.0.1:3000/12/');
$pipe = Mojo::Transaction::Pipeline->new($tx, $tx2);
$_->state('read_response') for @{$pipe->active};
$pipe->_all_written(1);
$responses = <<EOF;
HTTP/1.1 200 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT
Content-Type: text/plain
Content-length: 2000

HTTP/1.1 151 Weird

HTTP/1.1 152 Weirder

HTTP/1.1 204 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT

EOF
$pipe->client_read($responses);
ok($pipe->is_done);
ok($tx->is_done);
ok($tx2->is_done);
is($tx->res->code,  200);
is($tx2->res->code, 204);

# Unexpected 1xx response (other variation)
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://127.0.0.1:3000/13/');
$tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://127.0.0.1:3000/14/');
$pipe = Mojo::Transaction::Pipeline->new($tx, $tx2);
$_->state('read_response') for @{$pipe->active};
$pipe->_all_written(1);
$responses = <<EOF;
HTTP/1.1 151 Weird

HTTP/1.1 200 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT
Content-Type: text/plain
Content-length: 5

1234
HTTP/1.1 152 Weirder

HTTP/1.1 169 Weirdest

HTTP/1.1 204 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT

EOF
$pipe->client_read($responses);
ok($pipe->is_done);
ok($tx->is_done);
ok($tx2->is_done);
is($tx->res->code,  200);
is($tx2->res->code, 204);

# Safe POST
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://127.0.0.1:3000/15/');
$tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://127.0.0.1:3000/16/');
my $tx3 = Mojo::Transaction::Single->new;
$tx3->req->method('POST');
$tx3->req->url->parse('http://127.0.0.1:3000/17/');
$tx3->req->body('foo bar baz' x 10);
$pipe = Mojo::Transaction::Pipeline->new($tx, $tx2, $tx3);
$pipe->active->[$_]->state('read_response') for 0 .. $#{$pipe->active} - 1;
$pipe->active->[2]->state('write_start_line');
$pipe->_current(2);
$responses = <<EOF;
HTTP/1.1 200 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT
Content-Type: text/plain
Content-length: 5

1
EOF
$pipe->client_read($responses);
$pipe->safe_post(1);
ok(!$pipe->client_is_writing);
$pipe->safe_post(0);
ok($pipe->client_is_writing);

# Premature connection close
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://127.0.0.1:3000/18/');
$tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://127.0.0.1:3000/19/');
$tx3 = Mojo::Transaction::Single->new;
$tx3->req->method('GET');
$tx3->req->url->parse('http://127.0.0.1:3000/20/');
$pipe = Mojo::Transaction::Pipeline->new($tx, $tx2, $tx3);
$_->state('read_response') for @{$pipe->active};
$pipe->_all_written(1);
$responses = <<EOF;
HTTP/1.1 204 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT

HTTP/1.1 200 OK
Connection: Close
Date: Tue, 09 Jun 2009 18:24:14 GMT
Content-Type: text/plain
Content-length: 5

1234
EOF
$pipe->client_read($responses);
ok($tx->is_done);
ok($tx2->is_done);
ok(!$tx3->is_done);
is($tx->res->code,  204);
is($tx2->res->code, 200);
ok(!$pipe->keep_alive);
is($pipe->state,              'read_response');
is($tx3->state,               'read_response');
is(scalar @{$pipe->finished}, 2);
is(scalar @{$pipe->active},   1);
is(scalar @{$pipe->inactive}, 0);

# Rubbish on the wire
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('http://127.0.0.1:3000/21/');
$tx2 = Mojo::Transaction::Single->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://127.0.0.1:3000/22/');
$tx3 = Mojo::Transaction::Single->new;
$tx3->req->method('GET');
$tx3->req->url->parse('http://127.0.0.1:3000/23/');
$pipe = Mojo::Transaction::Pipeline->new($tx, $tx2, $tx3);
$_->state('read_response') for @{$pipe->active};
$pipe->_all_written(1);
$responses = <<EOF;
HTTP/1.1 200 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT
Content-Type: text/plain
Content-length: 5

1234


EOF
$pipe->client_read($responses);
ok($tx->is_done);
ok(!$tx2->is_done);
ok($tx2->has_error);
ok(!$tx3->is_done);
ok($pipe->has_error);
like($pipe->error, qr/Transaction Error/);
is(scalar @{$pipe->finished}, 2);
is(scalar @{$pipe->active},   1);
is(scalar @{$pipe->inactive}, 0);
