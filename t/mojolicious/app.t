#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 76;

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

# I guess I could part with one doomsday device and still be feared.
my $client = Mojo::Client->new;

# SyntaxError::foo (syntax error in controller)
my $tx = Mojo::Transaction->new_get('/syntax_error/foo');
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                            500);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/Missing right curly/);

# Foo::syntaxerror (syntax error in template)
$tx = Mojo::Transaction->new_get('/foo/syntaxerror');
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                            500);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/^Missing right curly/);

# Foo::badtemplate (template missing)
$tx = Mojo::Transaction->new_get('/foo/badtemplate');
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            '');

# Foo::test
$tx = Mojo::Transaction->new_get('/foo/test', 'X-Test' => 'Hi there!');
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->header('X-Bender'),     'Kiss my shiny metal ass!');
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/\/bar\/test/);

# Foo::index
$tx = Mojo::Transaction->new_get('/foo', 'X-Test' => 'Hi there!');
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->content_type,           'text/html');
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/<body>\n23Hello Mojo from the template \/foo! He/);

# Foo::Bar::index
$tx = Mojo::Transaction->new_get('/foo-bar', 'X-Test' => 'Hi there!');
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->content_type,           'text/html');
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/Hello Mojo from the other template \/foo-bar!/);

# Foo::templateless
$tx =
  Mojo::Transaction->new_get('/foo/templateless', 'X-Test' => 'Hi there!');
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/Hello Mojo from a templateless renderer!/);

# MojoliciousTest2::Foo::test
$tx = Mojo::Transaction->new_get('/test2', 'X-Test' => 'Hi there!');
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->header('X-Bender'),     'Kiss my shiny metal ass!');
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/\/test2/);

# MojoliciousTestController::index
$tx = Mojo::Transaction->new_get('/test3', 'X-Test' => 'Hi there!');
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->header('X-Bender'),     'Kiss my shiny metal ass!');
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/No class works!/);

# 404
$tx = Mojo::Transaction->new_get('/', 'X-Test' => 'Hi there!');
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                            404);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/File Not Found/);

# SyntaxError::foo in production mode (syntax error in controller)
my $backup = $ENV{MOJO_MODE} || '';
$ENV{MOJO_MODE} = 'production';
$tx = Mojo::Transaction->new_get('/syntax_error/foo');
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                            500);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/Internal Server Error/);
$ENV{MOJO_MODE} = $backup;

# Foo::syntaxerror in production mode (syntax error in template)
$backup = $ENV{MOJO_MODE} || '';
$ENV{MOJO_MODE} = 'production';
$tx = Mojo::Transaction->new_get('/foo/syntaxerror');
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            '');
$ENV{MOJO_MODE} = $backup;

# Static file /hello.txt in a production mode
$backup = $ENV{MOJO_MODE} || '';
$ENV{MOJO_MODE} = 'production';
$tx = Mojo::Transaction->new_get('/hello.txt');
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->content_type,           'text/plain');
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
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
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code,                  200);
is($tx->res->headers->content_type, 'text/plain');
is($tx->res->headers->header('Last-Modified'),
    $mtime, 'Last-Modified header is set correctly');
is($tx->res->headers->content_length,
    $stat->size, 'Content-Length is set correctly');
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->content->file->slurp,
    qr/Hello Mojo from a development static file!/);
$ENV{MOJO_MODE} = $backup;

# Check If-Modified-Since
$ENV{MOJO_MODE} = 'development';
$tx = Mojo::Transaction->new_get('/hello.txt');
$tx->req->headers->header('If-Modified-Since', $mtime);
$client->process_app('MojoliciousTest', $tx);
is($tx->res->code, 304, 'Setting If-Modified-Since triggers 304');
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
$ENV{MOJO_MODE} = $backup;

# Make sure we can override attributes with constructor arguments
my $app = MojoliciousTest->new({mode => 'test'});
is($app->mode, 'test');

# Persistent error
$app = MojoliciousTest->new;
$tx  = Mojo::Transaction->new_get('/foo');
$app->handler($tx);
is($tx->res->code, 200);
like($tx->res->body, qr/Hello Mojo from the template \/foo! Hello World!/);
$tx = Mojo::Transaction->new_get('/foo/willdie');
$app->handler($tx);
is($tx->res->code, 500);
like($tx->res->body, qr/Foo\.pm/);
$tx = Mojo::Transaction->new_get('/foo');
$app->handler($tx);
is($tx->res->code, 200);
like($tx->res->body, qr/Hello Mojo from the template \/foo! Hello World!/);
