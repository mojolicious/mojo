#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 18;

use Mojo::JSON;

# "We need some more secret sauce. Put the mayonnaise in the sun."
use_ok 'Mojo::Server::PSGI';
use_ok 'Mojolicious::Command::Psgi';

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
is $headers{'Content-Length'}, 43, 'right "Content-Length" value';
is $headers{'Content-Type'}, 'application/json', 'right "Content-Type" value';
my $params = '';
while (defined(my $chunk = $res->[2]->getline)) { $params .= $chunk }
$params = Mojo::JSON->new->decode($params);
is_deeply $params,
  {
  bar    => 'baz',
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
$app = Mojolicious::Command::Psgi->new->run;
$res = $app->($env);
is $res->[0], 200, 'right status';
%headers = @{$res->[1]};
is keys(%headers), 3, 'right number of headers';
ok $headers{Date}, 'right "Date" value';
is $headers{'Content-Length'}, 43, 'right "Content-Length" value';
is $headers{'Content-Type'}, 'application/json', 'right "Content-Type" value';
$params = '';
while (defined(my $chunk = $res->[2]->getline)) { $params .= $chunk }
$params = Mojo::JSON->new->decode($params);
is_deeply $params,
  {
  bar    => 'baz',
  world  => 'hello',
  lalala => 23
  },
  'right structure';
is $ENV{MOJO_HELLO}, 'world', 'on_finish callback';

# Cookies
$env = {
  CONTENT_LENGTH      => 0,
  PATH_INFO           => '/diag/cookies',
  QUERY_STRING        => 'lalala=23&bar=baz',
  REQUEST_METHOD      => 'GET',
  SCRIPT_NAME         => '/',
  HTTP_HOST           => 'localhost:8080',
  SERVER_PROTOCOL     => 'HTTP/1.1',
  'psgi.version'      => [1, 0],
  'psgi.url_scheme'   => 'http',
  'psgi.input'        => *STDIN,
  'psgi.errors'       => *STDERR,
  'psgi.multithread'  => 0,
  'psgi.multiprocess' => 1,
  'psgi.run_once'     => 0
};
$app = Mojolicious::Command::Psgi->new->run;
$res = $app->($env);
is $res->[0], 200, 'right status';
is scalar @{$res->[1]}, 10, 'right number of values';
my $i = 0;
for my $header (@{$res->[1]}) { $i++ if $header eq 'Set-Cookie' }
is $i, 2, 'right number of "Set-Cookie" headers';
