#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 106;

use FindBin;
use lib "$FindBin::Bin/lib";

use File::stat;
use File::Spec;
use Mojo::Date;
use Mojo::Client;
use Mojo::Transaction::Single;

# Congratulations Fry, you've snagged the perfect girlfriend.
# Amy's rich, she's probably got other characteristics...
use_ok('MojoliciousTest');

my $client = Mojo::Client->new(app => 'MojoliciousTest');

# SyntaxError::foo (syntax error in controller)
$client->get(
    '/syntax_error/foo' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            500);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/Missing right curly/);
    }
)->process;

# Foo::syntaxerror (syntax error in template)
$client->get(
    '/foo/syntaxerror' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            500);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/^Missing right curly/);
    }
)->process;

# Foo::badtemplate (template missing)
$client->get(
    '/foo/badtemplate' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            '');
    }
)->process;

# Foo::test
$client->get(
    '/foo/test' => ('X-Test' => 'Hi there!') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                        200);
        is($tx->res->headers->header('X-Bender'), 'Kiss my shiny metal ass!');
        is($tx->res->headers->server,             'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/\/bar\/test/);
    }
)->process;

# Foo::index
$client->get(
    '/foo' => ('X-Test' => 'Hi there!') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->content_type,           'text/html');
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body,
            qr/<body>\n23Hello Mojo from the template \/foo! He/);
    }
)->process;

# Foo::Bar::index
$client->get(
    '/foo-bar' => ('X-Test' => 'Hi there!') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->content_type,           'text/html');
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body,
            qr/Hello Mojo from the other template \/foo-bar!/);
    }
)->process;

# Foo::something
$client->get(
    '/test4' => ('X-Test' => 'Hi there!') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            '/test4/42');
    }
)->process;

# Foo::templateless
$client->get(
    '/foo/templateless' => ('X-Test' => 'Hi there!') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/Hello Mojo from a templateless renderer!/);
    }
)->process;

# Foo::withlayout
$client->get(
    '/foo/withlayout' => ('X-Test' => 'Hi there!') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/Same old in green Seems to work!/);
    }
)->process;

# MojoliciousTest2::Foo::test
$client->get(
    '/test2' => ('X-Test' => 'Hi there!') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                        200);
        is($tx->res->headers->header('X-Bender'), 'Kiss my shiny metal ass!');
        is($tx->res->headers->server,             'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/\/test2/);
    }
)->process;

# MojoliciousTestController::index
$client->get(
    '/test3' => ('X-Test' => 'Hi there!') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                        200);
        is($tx->res->headers->header('X-Bender'), 'Kiss my shiny metal ass!');
        is($tx->res->headers->server,             'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/No class works!/);
    }
)->process;

# 404
$client->get(
    '/' => ('X-Test' => 'Hi there!') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            404);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/File Not Found/);
    }
)->process;

# Check Last-Modified header for static files
my $path  = File::Spec->catdir($FindBin::Bin, 'public_dev', 'hello.txt');
my $stat  = stat($path);
my $mtime = Mojo::Date->new(stat($path)->mtime)->to_string;

# Static file /hello.txt
$client->get(
    '/hello.txt' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                  200);
        is($tx->res->headers->content_type, 'text/plain');
        is($tx->res->headers->header('Last-Modified'),
            $mtime, 'Last-Modified header is set correctly');
        is($tx->res->headers->content_length,
            $stat->size, 'Content-Length is set correctly');
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->content->asset->slurp,
            qr/Hello Mojo from a development static file!/);
    }
)->process;

# Try to access a file which is not under the web root via path
# traversal
$client->get(
    '../../mojolicious/secret.txt' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code, 404);
        unlike($tx->res->content->asset->slurp, qr/Secret file/);
    }
)->process;

# Check If-Modified-Since
$client->get(
    '/hello.txt' => ('If-Modified-Since' => $mtime) => sub {
        my ($self, $tx) = @_;
        is($tx->res->code, 304, 'Setting If-Modified-Since triggers 304');
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
    }
)->process;

# Make sure we can override attributes with constructor arguments
my $app = MojoliciousTest->new({mode => 'test'});
is($app->mode, 'test');

# Persistent error
$app = MojoliciousTest->new;
my $tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo');
$app->handler($tx);
is($tx->res->code, 200);
like($tx->res->body, qr/Hello Mojo from the template \/foo! Hello World!/);
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo/willdie');
$app->handler($tx);
is($tx->res->code, 500);
like($tx->res->body, qr/Foo\.pm/);
$tx = Mojo::Transaction::Single->new;
$tx->req->method('GET');
$tx->req->url->parse('/foo');
$app->handler($tx);
is($tx->res->code, 200);
like($tx->res->body, qr/Hello Mojo from the template \/foo! Hello World!/);

$client = Mojo::Client->new(app => 'SingleFileTestApp');

# SingleFileTestApp::Foo::index
$client->get(
    '/foo' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/Same old in green Seems to work!/);
    }
)->process;

# SingleFileTestApp::Foo::data_template
$client->get(
    '/foo/data_template' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            "23 works!\n");
    }
)->process;

# SingleFileTestApp::Foo::data_template
$client->get(
    '/foo/data_template2' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body, "This one works too!\n");
    }
)->process;

# SingleFileTestApp::Foo::bar
$client->get(
    '/foo/bar' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                        200);
        is($tx->res->headers->header('X-Bender'), 'Kiss my shiny metal ass!');
        is($tx->res->headers->server,             'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            '/foo/bar');
    }
)->process;

# SingleFileTestApp::Baz::does_not_exist
$client->get(
    '/baz/does_not_exist' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            404);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/File Not Found/);
    }
)->process;

$client = Mojo::Client->new(app => 'MojoliciousTest');

# MojoliciousTestController::Foo::stage2
$client->get(
    '/staged' => ('X-Pass' => 1) => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            'Welcome aboard!');
    }
)->process;

# MojoliciousTestController::Foo::stage1
$client->get(
    '/staged' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            'Go away!');
    }
)->process;

# MojoliciousTest::Foo::config
$client->get(
    '/stash_config' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            '123');
    }
)->process;
