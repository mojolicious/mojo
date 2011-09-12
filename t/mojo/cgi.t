#!/usr/bin/env perl
use Mojo::Base -strict;

use Test::More tests => 16;

use Mojo::Message::Response;

# "My ears are burning.
#  I wasn't talking about you, Dad.
#  No, my ears are really burning. I wanted to see inside, so I lit a Q-tip."
use_ok 'Mojo::Server::CGI';
use_ok 'Mojolicious::Command::cgi';

# Simple
my $message = '';
{
  local *STDOUT;
  open STDOUT, '>', \$message;
  local %ENV = (
    PATH_INFO       => '/',
    REQUEST_METHOD  => 'GET',
    SCRIPT_NAME     => '/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
  );
  Mojolicious::Command::cgi->new->run;
}
my $res =
  Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$message");
is $res->code, 200, 'rigth status';
is $res->headers->content_type, 'text/html;charset=UTF-8',
  'right "Content-Type" value';
like $res->body, qr/Mojo/, 'right content';

# Non-parsed headers
$message = '';
{
  local *STDOUT;
  open STDOUT, '>', \$message;
  local %ENV = (
    PATH_INFO       => '/',
    REQUEST_METHOD  => 'GET',
    SCRIPT_NAME     => '/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
  );
  Mojolicious::Command::cgi->new->run('--nph');
}
$res = Mojo::Message::Response->new->parse($message);
is $res->code, 200, 'rigth status';
is $res->headers->content_type, 'text/html;charset=UTF-8',
  'right "Content-Type" value';
like $res->body, qr/Mojo/, 'right content';

# Chunked
my $content = 'test1=1&test2=2&test3=3&test4=4&test5=5&test6=6&test7=7';
$message = '';
{
  local *STDIN;
  open STDIN, '<', \$content;
  local *STDOUT;
  open STDOUT, '>', \$message;
  local %ENV = (
    PATH_INFO       => '/diag/chunked_params',
    CONTENT_LENGTH  => length($content),
    CONTENT_TYPE    => 'application/x-www-form-urlencoded',
    REQUEST_METHOD  => 'POST',
    SCRIPT_NAME     => '/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
  );
  Mojolicious::Command::cgi->new->run;
}
like $message, qr/chunked/, 'is chunked';
$res = Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$message");
is $res->code, 200,       'rigth status';
is $res->body, '1234567', 'right content';

# Parameters
$message = '';
{
  local *STDOUT;
  open STDOUT, '>', \$message;
  local %ENV = (
    PATH_INFO       => '/diag/dump_params',
    QUERY_STRING    => 'lalala=23&bar=baz',
    REQUEST_METHOD  => 'GET',
    SCRIPT_NAME     => '/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
  );
  Mojolicious::Command::cgi->new->run;
}
$res = Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$message");
is $res->code, 200, 'rigth status';
is $res->headers->content_type, 'application/json',
  'right "Content-Type" value';
is $res->headers->content_length, 27, 'right "Content-Length" value';
is $res->json->{lalala}, 23,    'right value';
is $res->json->{bar},    'baz', 'right value';
