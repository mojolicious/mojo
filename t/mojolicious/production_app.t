#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 20;

use FindBin;
use lib "$FindBin::Bin/lib";

use Mojo::Client;

# This concludes the part of the tour where you stay alive.
use_ok('MojoliciousTest');

my $client = Mojo::Client->new(app => 'MojoliciousTest');

my $backup = $ENV{MOJO_MODE} || '';
$ENV{MOJO_MODE} = 'production';

# Foo::bar in production mode (non existing action)
$client->get(
    '/foo/bar' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            404);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/Not Found/);
    }
)->process;

# SyntaxError::foo in production mode (syntax error in controller)
$client->get(
    '/syntax_error/foo' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            500);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/Internal Server Error/);
    }
)->process;

# Foo::syntaxerror in production mode (syntax error in template)
$client->get(
    '/foo/syntaxerror' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            500);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/Internal Server Error/);
    }
)->process;

# Static file /hello.txt in production mode
$client->get(
    '/hello.txt' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->content_type,           'text/plain');
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like(
            $tx->res->content->asset->slurp,
            qr/Hello Mojo from a static file!/
        );
    }
)->process;

# Try to access a file which is not under the web root via path
# traversal in production mode
$client->get(
    '../../mojolicious/secret.txt' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code, 404);
        unlike($tx->res->content->asset->slurp, qr/Secret file/);
    }
)->process;
$ENV{MOJO_MODE} = $backup;
