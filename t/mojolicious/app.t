#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 19;

use FindBin;
use lib "$FindBin::Bin/lib";

use File::stat;
use File::Spec;
use Mojo::Date;
use Mojo::Client;
use Mojo::Transaction;

# Congratulations Fry, you've snagged the perfect girlfriend.
# Amy's rich, she's probably got other characteristics...
use_ok('MojoliciousTest');

my $client = Mojo::Client->new;

# Foo::test()
my $tx = Mojo::Transaction->new_get('/foo/test', 'X-Test' => 'Hi there!');
$client->process_local('MojoliciousTest', $tx);
is($tx->res->code,                        200);
is($tx->res->headers->header('X-Bender'), 'Kiss my shiny metal ass!');
like($tx->res->body, qr/\/bar\/test/);

# Foo::index()
$tx = Mojo::Transaction->new_get('/foo', 'X-Test' => 'Hi there!');
$client->process_local('MojoliciousTest', $tx);
is($tx->res->code,                  200);
is($tx->res->headers->content_type, 'text/html');
like($tx->res->body, qr/Hello Mojo from the template \/foo!/);

# Foo::Bar::index()
$tx = Mojo::Transaction->new_get('/foo-bar', 'X-Test' => 'Hi there!');
$client->process_local('MojoliciousTest', $tx);
is($tx->res->code,                  200);
is($tx->res->headers->content_type, 'text/html');
like($tx->res->body, qr/Hello Mojo from the other template \/foo-bar!/);

# Static file /hello.txt in a production mode
my $backup = $ENV{MOJO_MODE} || '';
$ENV{MOJO_MODE} = 'production';
$tx = Mojo::Transaction->new_get('/hello.txt');
$client->process_local('MojoliciousTest', $tx);
is($tx->res->code,                  200);
is($tx->res->headers->content_type, 'text/plain');
like($tx->res->content->file->slurp, qr/Hello Mojo from a static file!/);
$ENV{MOJO_MODE} = $backup;

# Check Last-Modified header for static files
my $path  = File::Spec->catdir($FindBin::Bin, 'public_dev', 'hello.txt');
my $stat  = stat($path);
my $mtime = Mojo::Date->new(stat($path)->mtime)->to_string;

# Static file /hello.txt in a development mode
$backup = $ENV{MOJO_MODE} || '';
$ENV{MOJO_MODE} = 'development';
$tx = Mojo::Transaction->new_get('/hello.txt');
$client->process_local('MojoliciousTest', $tx);
is($tx->res->code,                  200);
is($tx->res->headers->content_type, 'text/plain');
is($tx->res->headers->header('Last-Modified'),
    $mtime, 'Last-Modified header is set correctly');
like($tx->res->content->file->slurp,
    qr/Hello Mojo from a development static file!/);
$ENV{MOJO_MODE} = $backup;

# Check If-Modified-Since
$ENV{MOJO_MODE} = 'development';
$tx = Mojo::Transaction->new_get('/hello.txt');
$tx->req->headers->header('If-Modified-Since', $mtime);
$client->process_local('MojoliciousTest', $tx);
is($tx->res->code, 304, 'Setting If-Modified-Since triggers 304');
$ENV{MOJO_MODE} = $backup;

# Check 403 Forbidden
$ENV{MOJO_MODE} = 'development';
chmod 0000, $path;
$tx = Mojo::Transaction->new_get('/hello.txt');
$client->process_local('MojoliciousTest', $tx);
is($tx->res->code, 403, 'Unreadable file triggers 403 Forbidden');
chmod 0755, $path;
$ENV{MOJO_MODE} = $backup;
