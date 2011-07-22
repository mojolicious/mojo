#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 1;

use Mojo::Content::MultiPart;
use Mojo::Message::Request;

local $SIG{ALRM} = sub { die "timeout\n" }; alarm 2;

my $req_seed = <<EOF;
GET /foo HTTP/1.0
Content-Type: multipart/mixed; boundary="abcdefg"

Content
--abcdefg--
EOF

$req_seed =~ s{\x0a}{\x0d\x0a}g;
my $req = Mojo::Message::Request->new;
$req->parse($req_seed);
$req->parse({});

is(1, 1, 'no infinit loop');
