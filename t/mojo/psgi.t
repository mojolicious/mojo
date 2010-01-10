#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 11;

use_ok('Mojo::Server::PSGI');

# We need some more secret sauce. Put the mayonnaise in the sun.
my $psgi = Mojo::Server::PSGI->new;
my $app = sub { $psgi->run(@_) };

# Request
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

# Process
my $res = $app->($env);

# Response
is($res->[0],      200);
is($res->[1]->[0], 'Date');
ok($res->[1]->[1]->[0]);
is($res->[1]->[2],      'Content-Length');
is($res->[1]->[3]->[0], 104);
is($res->[1]->[4],      'Content-Type');
is($res->[1]->[5]->[0], 'text/plain');
is($res->[1]->[6],      'X-Powered-By');
is($res->[1]->[7]->[0], 'Mojo (Perl)');
my $params = '';
while (defined(my $chunk = $res->[2]->getline)) { $params .= $chunk }
$params = eval "my $params";
is_deeply($params, {bar => 'baz', hello => 'world', lalala => 23});
