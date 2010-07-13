#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 19;

# We need some more secret sauce. Put the mayonnaise in the sun.
use_ok('Mojo::Server::PSGI');
use_ok('Mojo::Command::Psgi');

# Binding
my $psgi    = Mojo::Server::PSGI->new;
my $app     = sub { $psgi->run(@_) };
my $content = 'hello=world';
open my $body, '<', \$content;
my $env = {
    CONTENT_LENGTH      => 11,
    CONTENT_TYPE        => 'application/x-www-form-urlencoded',
    PATH_INFO           => '/diag/dump_params',
    QUERY_STRING        => 'lalala=23&bar=baz',
    REQUEST_METHOD      => 'POST',
    SCRIPT_NAME         => '/',
    HTTP_HOST           => 'localhost:8080',
    SERVER_PROTOCOL     => 'HTTP/1.0',
    'psgi.version'      => [1, 0],
    'psgi.url_scheme'   => 'http',
    'psgi.input'        => $body,
    'psgi.errors'       => *STDERR,
    'psgi.multithread'  => 0,
    'psgi.multiprocess' => 1,
    'psgi.run_once'     => 0
};
my $res = $app->($env);
is($res->[0],      200,    'right status');
is($res->[1]->[0], 'Date', 'right header name');
ok($res->[1]->[1], 'right header value');
is($res->[1]->[2], 'Content-Length', 'right header name');
is($res->[1]->[3], 104,              'right header value');
is($res->[1]->[4], 'Content-Type',   'right header name');
is($res->[1]->[5], 'text/plain',     'right header value');
my $params = '';
while (defined(my $chunk = $res->[2]->getline)) { $params .= $chunk }
$params = eval "my $params";
is_deeply(
    $params,
    {bar => 'baz', hello => 'world', lalala => 23},
    'right structure'
);

# Command
$content = 'world=hello';
open $body, '<', \$content;
$env = {
    CONTENT_LENGTH      => 11,
    CONTENT_TYPE        => 'application/x-www-form-urlencoded',
    PATH_INFO           => '/diag/dump_params',
    QUERY_STRING        => 'lalala=23&bar=baz',
    REQUEST_METHOD      => 'POST',
    SCRIPT_NAME         => '/',
    HTTP_HOST           => 'localhost:8080',
    SERVER_PROTOCOL     => 'HTTP/1.0',
    'psgi.version'      => [1, 0],
    'psgi.url_scheme'   => 'http',
    'psgi.input'        => $body,
    'psgi.errors'       => *STDERR,
    'psgi.multithread'  => 0,
    'psgi.multiprocess' => 1,
    'psgi.run_once'     => 0
};
$app = Mojo::Command::Psgi->new->run;
$res = $app->($env);
is($res->[0],      200,    'right status');
is($res->[1]->[0], 'Date', 'right header name');
ok($res->[1]->[1], 'right header value');
is($res->[1]->[2], 'Content-Length', 'right header name');
is($res->[1]->[3], 104,              'right header value');
is($res->[1]->[4], 'Content-Type',   'right header name');
is($res->[1]->[5], 'text/plain',     'right header value');
$params = '';
while (defined(my $chunk = $res->[2]->getline)) { $params .= $chunk }
$params = eval "my $params";
is_deeply(
    $params,
    {bar => 'baz', world => 'hello', lalala => 23},
    'right structure'
);
is($ENV{MOJO_HELLO}, 'world', 'finished callback');
