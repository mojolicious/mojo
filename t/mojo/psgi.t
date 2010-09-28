#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 15;

use Mojo::JSON;

# We need some more secret sauce. Put the mayonnaise in the sun.
use_ok 'Mojo::Server::PSGI';
use_ok 'Mojo::Command::Psgi';

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
is $res->[0], 200, 'right status';
my %headers = @{$res->[1]};
is keys(%headers), 3, 'right number of headers';
ok $headers{Date}, 'right "Date" value';
is $headers{'Content-Length'}, 41, 'right "Content-Length" value';
is $headers{'Content-Type'}, 'application/json', 'right "Content-Type" value';
my $params = '';
while (defined(my $chunk = $res->[2]->getline)) { $params .= $chunk }
$params = Mojo::JSON->new->decode($params);
is_deeply $params,
  { bar    => 'baz',
    hello  => 'world',
    lalala => 23
  },
  'right structure';

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
is $res->[0], 200, 'right status';
%headers = @{$res->[1]};
is keys(%headers), 3, 'right number of headers';
ok $headers{Date}, 'right "Date" value';
is $headers{'Content-Length'}, 41, 'right "Content-Length" value';
is $headers{'Content-Type'}, 'application/json', 'right "Content-Type" value';
$params = '';
while (defined(my $chunk = $res->[2]->getline)) { $params .= $chunk }
$params = Mojo::JSON->new->decode($params);
is_deeply $params,
  { bar    => 'baz',
    world  => 'hello',
    lalala => 23
  },
  'right structure';
is $ENV{MOJO_HELLO}, 'world', 'on_finish callback';
