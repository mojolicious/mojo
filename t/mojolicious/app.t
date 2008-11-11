#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 13;

use FindBin;
use lib "$FindBin::Bin/lib";

use Mojo::Client;
use Mojo::Transaction;

# Congratulations Fry, you've snagged the perfect girlfriend.
# Amy's rich, she's probably got other characteristics...
use_ok('MojoliciousTest');

my $client = Mojo::Client->new;

# Foo::test()
my $tx = Mojo::Transaction->new_get('/foo/test', 'X-Test' => 'Hi there!');
$client->process_local('MojoliciousTest', $tx);
is($tx->res->code, 200);
is($tx->res->headers->header('X-Bender'), 'Kiss my shiny metal ass!');
like($tx->res->body, qr/\/bar\/test/);

# Foo::index()
$tx = Mojo::Transaction->new_get('/foo', 'X-Test' => 'Hi there!');
$client->process_local('MojoliciousTest', $tx);
is($tx->res->code, 200);
is($tx->res->headers->content_type, 'text/html');
like($tx->res->body, qr/Hello Mojo from the template \/foo!/);

# Static file /hello.txt in a production environment
my $backup = $ENV{MOJO_ENV} || '';
$ENV{MOJO_ENV} = 'production';
$tx = Mojo::Transaction->new_get('/hello.txt');
$client->process_local('MojoliciousTest', $tx);
is($tx->res->code, 200);
is($tx->res->headers->content_type, 'text/plain');
like($tx->res->content->file->slurp, qr/Hello Mojo from a static file!/);
$ENV{MOJO_ENV} = $backup;

# Static file /hello.txt in a development environment
$backup = $ENV{MOJO_ENV} || '';
$ENV{MOJO_ENV} = 'development';
$tx = Mojo::Transaction->new_get('/hello.txt');
$client->process_local('MojoliciousTest', $tx);
is($tx->res->code, 200);
is($tx->res->headers->content_type, 'text/plain');
like($tx->res->content->file->slurp,
  qr/Hello Mojo from a development static file!/);
$ENV{MOJO_ENV} = $backup;