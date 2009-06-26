#!perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More;

plan skip_all => 'set TEST_PIPELINE to enable this test'
  unless $ENV{TEST_PIPELINE};
plan tests => 40;

# Are we there yet?
# No
# Are we there yet?
# No
# Are we there yet?
# No
# ...Where are we going?
use_ok('Mojo::Pipeline');
use_ok('Mojo::Transaction');

# Vanilla Pipeline
my $tx1  = Mojo::Transaction->new_get("http://127.0.0.1:3000/1/");
my $tx2  = Mojo::Transaction->new_get("http://127.0.0.1:3000/2/");
my $pipe = Mojo::Pipeline->new($tx1, $tx2);
$_->state('read_response') for @{$pipe->{_txs}};
$pipe->{_reader}      = 0;
$pipe->{_writer}      = 2;
$pipe->{_all_written} = 1;
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
ok($tx1->is_done);
ok($tx2->is_done);
is($tx1->res->code, 204);
is($tx2->res->code, 200);

# HEAD request
$tx1  = Mojo::Transaction->new_get("http://127.0.0.1:3000/3/");
$tx2  = Mojo::Transaction->new_head("http://127.0.0.1:3000/4/");
$pipe = Mojo::Pipeline->new($tx1, $tx2);
$_->state('read_response') for @{$pipe->{_txs}};
$pipe->{_reader}      = 0;
$pipe->{_writer}      = 2;
$pipe->{_all_written} = 1;
$responses            = <<EOF;
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
ok($tx1->is_done);
ok($tx2->is_done);
is($tx1->res->code, 404);
is($tx2->res->code, 200);

# HEAD request followed by regular request
$tx1  = Mojo::Transaction->new_head("http://127.0.0.1:3000/5/");
$tx2  = Mojo::Transaction->new_get("http://127.0.0.1:3000/6/");
$pipe = Mojo::Pipeline->new($tx1, $tx2);
$_->state('read_response') for @{$pipe->{_txs}};
$pipe->{_reader}      = 0;
$pipe->{_writer}      = 2;
$pipe->{_all_written} = 1;
$responses            = <<EOF;
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
ok($tx1->is_done);
ok($tx2->is_done);
is($tx1->res->code, 200);
is($tx2->res->code, 500);

# Bad Pipeline (host)
$tx1  = Mojo::Transaction->new_get("http://127.0.0.1:3000/7/");
$tx2  = Mojo::Transaction->new_get("http://labs.kraih.com:3000/8/");
$pipe = Mojo::Pipeline->new($tx1, $tx2);
ok($pipe->has_error);
is($tx1->state, 'start');
is($tx2->state, 'start');

# Bad Pipeline (port)
$tx1  = Mojo::Transaction->new_get("http://labs.kraih.com/7/");
$tx2  = Mojo::Transaction->new_get("http://labs.kraih.com:3000/8/");
$pipe = Mojo::Pipeline->new($tx1, $tx2);
ok($pipe->has_error);
is($tx1->state, 'start');
is($tx2->state, 'start');

# Unexpected 1xx response
$tx1  = Mojo::Transaction->new_head("http://127.0.0.1:3000/9/");
$tx2  = Mojo::Transaction->new_get("http://127.0.0.1:3000/10/");
$pipe = Mojo::Pipeline->new($tx1, $tx2);
$_->state('read_response') for @{$pipe->{_txs}};
$pipe->{_reader}      = 0;
$pipe->{_writer}      = 2;
$pipe->{_all_written} = 1;
$responses            = <<EOF;
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
ok($tx1->is_done);
ok($tx2->is_done);
is($tx1->res->code, 200);
is($tx2->res->code, 204);

# Unexpected 1xx response (variation)
$tx1  = Mojo::Transaction->new_head("http://127.0.0.1:3000/11/");
$tx2  = Mojo::Transaction->new_get("http://127.0.0.1:3000/12/");
$pipe = Mojo::Pipeline->new($tx1, $tx2);
$_->state('read_response') for @{$pipe->{_txs}};
$pipe->{_reader}      = 0;
$pipe->{_writer}      = 2;
$pipe->{_all_written} = 1;
$responses            = <<EOF;
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
ok($tx1->is_done);
ok($tx2->is_done);
is($tx1->res->code, 200);
is($tx2->res->code, 204);

# Unexpected 1xx response (other variation)
$tx1  = Mojo::Transaction->new_get("http://127.0.0.1:3000/13/");
$tx2  = Mojo::Transaction->new_get("http://127.0.0.1:3000/14/");
$pipe = Mojo::Pipeline->new($tx1, $tx2);
$_->state('read_response') for @{$pipe->{_txs}};
$pipe->{_reader}      = 0;
$pipe->{_writer}      = 2;
$pipe->{_all_written} = 1;
$responses            = <<EOF;
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
ok($tx1->is_done);
ok($tx2->is_done);
is($tx1->res->code, 200);
is($tx2->res->code, 204);

# Safe POST
$tx1 = Mojo::Transaction->new_get("http://127.0.0.1:3000/15/");
$tx2 = Mojo::Transaction->new_get("http://127.0.0.1:3000/16/");
my $tx3 = Mojo::Transaction->new_post('http://127.0.0.1:3000/17/');
$tx3->req->body('foo bar baz' x 10);
$pipe = Mojo::Pipeline->new($tx1, $tx2, $tx3);
$pipe->{_txs}->[$_]->state('read_response') for 0 .. $#{$pipe->{_txs}} - 1;
$pipe->{_txs}->[2]->state('write_start_line');
$pipe->{_reader} = 0;
$pipe->{_writer} = 2;
$responses       = <<EOF;
HTTP/1.1 200 OK
Connection: Keep-Alive
Date: Tue, 09 Jun 2009 18:24:14 GMT
Content-Type: text/plain
Content-length: 5

1
EOF
$pipe->client_read($responses);
$pipe->safe_post(1);
ok(!$pipe->is_writing);
$pipe->safe_post(0);
ok($pipe->is_writing);
