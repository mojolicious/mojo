#!/usr/bin/env perl
use Mojo::Base -strict;

use utf8;

use Test::More tests => 1148;

use File::Spec;
use File::Temp;
use Mojo::Headers;

# "When will I learn?
#  The answer to life's problems aren't at the bottom of a bottle,
#  they're on TV!"
use_ok 'Mojo::Asset::File';
use_ok 'Mojo::Content::Single';
use_ok 'Mojo::Content::MultiPart';
use_ok 'Mojo::Cookie::Request';
use_ok 'Mojo::Cookie::Response';
use_ok 'Mojo::Headers';
use_ok 'Mojo::Message';
use_ok 'Mojo::Message::Request';
use_ok 'Mojo::Message::Response';

# Pollution
123 =~ m/(\d+)/;

# Parse HTTP 1.1 message with huge "Cookie" header exceeding all limits
my $req = Mojo::Message::Request->new;
$req->parse("GET / HTTP/1.1\x0d\x0a");
$req->parse('Cookie: ' . ('a=b; ' x (1024 * 1024)) . "\x0d\x0a");
$req->parse("Content-Length: 0\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->error,   'Maximum message size exceeded.', 'right error';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.1'), 1,     'at least version 1.1';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/', 'right URL';
is $req->cookie('a'), undef, 'no value';

# Parse HTTP 1.1 message with huge "Cookie" header exceeding line limit
$req = Mojo::Message::Request->new;
$req->parse("GET / HTTP/1.1\x0d\x0a");
$req->parse('Cookie: ' . ('a=b; ' x (128 * 1024)) . "\x0d\x0a");
$req->parse("Content-Length: 0\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->error,   'Maximum line size exceeded.', 'right error';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.1'), 1,     'at least version 1.1';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/', 'right URL';
is $req->cookie('a'), undef, 'no value';
is $req->body, '', 'no content';

# Parse HTTP 1.1 message with huge "Cookie" header exceeding line limit
# (alternative)
$req = Mojo::Message::Request->new;
$req->parse("GET / HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 4\x0d\x0aCookie: "
    . ('a=b; ' x (128 * 1024))
    . "\x0d\x0aX-Test: 23\x0d\x0a\x0d\x0aabcd");
ok $req->is_done, 'request is done';
is $req->error,   'Maximum line size exceeded.', 'right error';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.1'), 1,     'at least version 1.1';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/', 'right URL';
is $req->cookie('a'), undef, 'no value';
is $req->body, '', 'no content';

# Parse HTTP 1.1 message with content exceeding line limit
$req = Mojo::Message::Request->new;
$req->parse("GET / HTTP/1.1\x0d\x0a");
$req->parse(
  "Content-Length: 655360\x0d\x0a\x0d\x0a" . ('a=b; ' x (128 * 1024)));
ok $req->is_done, 'request is done';
is $req->error,   undef, 'no error';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.1'), 1,     'at least version 1.1';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/', 'right URL';
is $req->body, 'a=b; ' x (128 * 1024), 'right content';

# Parse broken HTTP 1.1 message with header exceeding line limit
$req = Mojo::Message::Request->new;
$req->parse("GET / HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 0\x0d\x0aCookie: " . ('a=b; ' x (128 * 1024)));
ok $req->is_done, 'request is done';
is $req->error,   'Maximum line size exceeded.', 'right error';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.1'), 1,     'at least version 1.1';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/', 'right URL';
is $req->cookie('a'), undef, 'no value';
is $req->body, '', 'no content';

# Parse broken HTTP 1.1 message with start line exceeding line limit
$req = Mojo::Message::Request->new;
$req->parse('GET /' . ('abcd' x (128 * 1024)) . ' HTTP/1.1');
ok $req->is_done, 'request is done';
is $req->error,   'Maximum line size exceeded.', 'right error';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.1'), 1,     'at least version 1.1';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '', 'right URL';
is $req->cookie('a'), undef, 'no value';
is $req->body, '', 'no content';

# Parse broken HTTP 1.1 message with start line exceeding line limit
# (alternative)
$req = Mojo::Message::Request->new;
$req->parse('GET /');
$req->parse('abcd' x (128 * 1024));
ok $req->is_done, 'request is done';
is $req->error,   'Maximum line size exceeded.', 'right error';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.1'), 1,     'at least version 1.1';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '', 'right URL';
is $req->cookie('a'), undef, 'no value';
is $req->body, '', 'no content';

# Parse HTTP 1.1 start line, no headers and body
$req = Mojo::Message::Request->new;
$req->parse("GET / HTTP/1.1\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.1'), 1,     'at least version 1.1';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/', 'right URL';

# Parse pipelined HTTP 1.1 start line, no headers and body
$req = Mojo::Message::Request->new;
$req->parse("GET / HTTP/1.1\x0d\x0a\x0d\x0aGET / HTTP/1.1\x0d\x0a\x0d\x0a");
ok $req->is_done,   'request is done';
is $req->leftovers, "GET / HTTP/1.1\x0d\x0a\x0d\x0a",
  'second request in leftovers';

# Parse HTTP 1.1 start line, no headers and body with leading CRLFs
# (SHOULD be ignored, RFC 2616, Section 4.1)
$req = Mojo::Message::Request->new;
$req->parse("\x0d\x0aGET / HTTP/1.1\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.1'), 1,     'at least version 1.1';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/', 'right URL';

# Parse WebSocket handshake request
$req = Mojo::Message::Request->new;
$req->parse("GET /demo HTTP/1.1\x0d\x0a");
$req->parse("Host: example.com\x0d\x0a");
$req->parse("Connection: Upgrade\x0d\x0a");
$req->parse("Sec-WebSocket-Key: abcdef=\x0d\x0a");
$req->parse("Sec-WebSocket-Protocol: sample\x0d\x0a");
$req->parse("Upgrade: WebSocket\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.1'), 1,     'at least version 1.1';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/demo', 'right URL';
is $req->headers->host,       'example.com', 'right "Host" value';
is $req->headers->connection, 'Upgrade',     'right "Connection" value';
is $req->headers->sec_websocket_protocol, 'sample',
  'right "Sec-WebSocket-Protocol" value';
is $req->headers->upgrade, 'WebSocket', 'right "Upgrade" value';
is $req->headers->sec_websocket_key, 'abcdef=',
  'right "Sec-WebSocket-Key" value';
is $req->body, '', 'no content';

# Parse HTTP 1.0 start line and headers, no body
$req = Mojo::Message::Request->new;
$req->parse("GET /foo/bar/baz.html HTTP/1.0\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a");
$req->parse("Content-Length: 0\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.0', 'right version';
is $req->at_least_version('0.9'), 1,     'at least version 0.9';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html', 'right URL';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, 0, 'right "Content-Length" value';

# Parse HTTP 1.0 start line and headers, no body (missing Content-Length)
$req = Mojo::Message::Request->new;
$req->parse("GET /foo/bar/baz.html HTTP/1.0\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html', 'right URL';
is $req->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, undef,        'no "Content-Length" value';

# Parse full HTTP 1.0 request (file storage)
my $backup = $ENV{MOJO_MAX_MEMORY_SIZE} || '';
$ENV{MOJO_MAX_MEMORY_SIZE} = 12;
$req = Mojo::Message::Request->new;
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: text/');
$req->parse("plain\x0d\x0aContent-Length: 27\x0d\x0a\x0d\x0aHell");
$req->parse("o World!\n");
is $req->content->asset->isa('Mojo::Asset::Memory'), 1, 'stored in memory';
$req->parse("1234\nlalalala\n");
is $req->content->asset->isa('Mojo::Asset::File'), 1, 'stored in file';
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, 27, 'right "Content-Length" value';
$ENV{MOJO_MAX_MEMORY_SIZE} = $backup;

# Parse HTTP 1.0 start line and headers, no body (missing Content-Length)
$req = Mojo::Message::Request->new;
$req->parse("GET /foo/bar/baz.html HTTP/1.0\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a");
$req->parse("Connection: Close\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html', 'right URL';
is $req->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, undef,        'no "Content-Length" value';

# Parse HTTP 1.0 start line and headers, no body (with line size limit)
$req                     = Mojo::Message::Request->new;
$backup                  = $ENV{MOJO_MAX_LINE_SIZE} || '';
$ENV{MOJO_MAX_LINE_SIZE} = 5;
$req->parse('GET /foo/bar/baz.html HTTP/1');
ok $req->is_done, 'request is done';
is(($req->error)[0], 'Maximum line size exceeded.', 'right error');
is(($req->error)[1], 413, 'right status');
$ENV{MOJO_MAX_LINE_SIZE} = $backup;

# Parse HTTP 1.0 start line and headers, no body (with message size limit)
$req                        = Mojo::Message::Request->new;
$backup                     = $ENV{MOJO_MAX_MESSAGE_SIZE} || '';
$ENV{MOJO_MAX_MESSAGE_SIZE} = 5;
$req->parse('GET /foo/bar/baz.html HTTP/1');
ok $req->is_done, 'request is done';
is(($req->error)[1], 413, 'right status');
$ENV{MOJO_MAX_MESSAGE_SIZE} = $backup;

# Parse full HTTP 1.0 request
$req = Mojo::Message::Request->new;
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: text/');
$req->parse("plain\x0d\x0aContent-Length: 27\x0d\x0a\x0d\x0aHell");
$req->parse("o World!\n1234\nlalalala\n");
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, 27, 'right "Content-Length" value';

# Parse full HTTP 1.0 request (behind reverse proxy)
$req = Mojo::Message::Request->new;
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: text/');
$req->parse("plain\x0d\x0aContent-Length: 27\x0d\x0a");
$req->parse("Host: mojolicio.us\x0d\x0a");
$req->parse("X-Forwarded-For: 192.168.2.1, 127.0.0.1\x0d\x0a\x0d\x0a");
$req->parse("Hello World!\n1234\nlalalala\n");
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->url->to_abs, 'http://mojolicio.us/foo/bar/baz.html?foo=13#23',
  'right absolute URL';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, 27, 'right "Content-Length" value';

# Parse full HTTP 1.0 request with zero chunk
$req = Mojo::Message::Request->new;
my $finished;
$req->on_finish(sub { $finished = shift->is_done });
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: text/');
$req->parse("plain\x0d\x0aContent-Length: 27\x0d\x0a\x0d\x0aHell");
$req->parse("o World!\n123");
$req->parse('0');
$req->parse("\nlalalala\n");
ok $finished, 'finish callback was called';
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, 27, 'right "Content-Length" value';

# Parse full HTTP 1.0 request with utf8 form input
$req = Mojo::Message::Request->new;
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: application/');
$req->parse("x-www-form-urlencoded\x0d\x0aContent-Length: 53");
$req->parse("\x0d\x0a\x0d\x0a");
$req->parse('name=%D0%92%D1%8F%D1%87%D0%B5%D1%81%D0%BB%D0%B0%D0%B2');
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_type, 'application/x-www-form-urlencoded',
  'right "Content-Type" value';
is $req->headers->content_length, 53, 'right "Content-Length" value';
is $req->param('name'), 'Вячеслав', 'right value';

# Parse HTTP 0.9 request
$req = Mojo::Message::Request->new;
$req->parse("GET /\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '0.9', 'right version';
is $req->at_least_version('0.9'), 1,     'at least version 0.9';
is $req->at_least_version('1.0'), undef, 'not version 1.0';
is $req->url, '/', 'right URL';

# Parse HTTP 1.1 chunked request
$req = Mojo::Message::Request->new;
$req->parse("POST /foo/bar/baz.html?foo=13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a");
$req->parse("Transfer-Encoding: chunked\x0d\x0a\x0d\x0a");
$req->parse("4\x0d\x0a");
$req->parse("abcd\x0d\x0a");
$req->parse("9\x0d\x0a");
$req->parse("abcdefghi\x0d\x0a");
$req->parse("0\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'POST', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_length, 13, 'right "Content-Length" value';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $req->content->asset->size, 13, 'right size';
is $req->content->asset->slurp, 'abcdabcdefghi', 'right content';

# Parse HTTP 1.1 chunked request with callback
$req = Mojo::Message::Request->new;
my $buffer = '';
$req->body(sub { $buffer .= pop });
$req->parse("POST /foo/bar/baz.html?foo=13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a");
$req->parse("Transfer-Encoding: chunked\x0d\x0a\x0d\x0a");
$req->parse("4\x0d\x0a");
$req->parse("abcd\x0d\x0a");
$req->parse("9\x0d\x0a");
$req->parse("abcdefghi\x0d\x0a");
$req->parse("0\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'POST', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_length, 13, 'right "Content-Length" value';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $buffer, 'abcdabcdefghi', 'right content';

# Parse HTTP 1.1 "x-application-urlencoded"
$req = Mojo::Message::Request->new;
$req->parse("POST /foo/bar/baz.html?foo=13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 26\x0d\x0a");
$req->parse("Content-Type: x-application-urlencoded\x0d\x0a\x0d\x0a");
$req->parse('foo=bar& tset=23+;&foo=bar');
ok $req->is_done, 'request is done';
is $req->method,  'POST', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_type,
  'x-application-urlencoded', 'right "Content-Type" value';
is $req->content->asset->size, 26, 'right size';
is $req->content->asset->slurp, 'foo=bar& tset=23+;&foo=bar', 'right content';
is $req->body_params, 'foo=bar&+tset=23+&foo=bar', 'right parameters';
is_deeply $req->body_params->to_hash->{foo}, [qw/bar bar/], 'right values';
is_deeply $req->body_params->to_hash->{' tset'}, '23 ', 'right value';
is_deeply $req->params->to_hash->{foo}, [qw/bar bar 13/], 'right values';

# Parse HTTP 1.1 "application/x-www-form-urlencoded"
$req = Mojo::Message::Request->new;
$req->parse("POST /foo/bar/baz.html?foo=13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 26\x0d\x0a");
$req->parse("Content-Type: application/x-www-form-urlencoded\x0d\x0a");
$req->parse("\x0d\x0afoo=bar&+tset=23+;&foo=bar");
ok $req->is_done, 'request is done';
is $req->method,  'POST', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_type,
  'application/x-www-form-urlencoded',
  'right "Content-Type" value';
is $req->content->asset->size, 26, 'right size';
is $req->content->asset->slurp, 'foo=bar&+tset=23+;&foo=bar', 'right content';
is $req->body_params, 'foo=bar&+tset=23+&foo=bar', 'right parameters';
is_deeply $req->body_params->to_hash->{foo}, [qw/bar bar/], 'right values';
is_deeply $req->body_params->to_hash->{' tset'}, '23 ', 'right value';
is_deeply $req->params->to_hash->{foo}, [qw/bar bar 13/], 'right values';
is_deeply [$req->param('foo')], [qw/bar bar 13/], 'right values';
is_deeply $req->param(' tset'), '23 ', 'right value';
$req->param('set', 'single');
is_deeply $req->param('set'), 'single', 'setting single param works';
$req->param('multi', 1, 2, 3);
is_deeply [$req->param('multi')],
  [qw/1 2 3/], 'setting multiple value param works';
is $req->param('test23'), undef, 'no value';

# Parse HTTP 1.1 chunked request with trailing headers
$req = Mojo::Message::Request->new;
$req->parse("POST /foo/bar/baz.html?foo=13&bar=23#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a");
$req->parse("Transfer-Encoding: chunked\x0d\x0a");
$req->parse("Trailer: X-Trailer1; X-Trailer2\x0d\x0a\x0d\x0a");
$req->parse("4\x0d\x0a");
$req->parse("abcd\x0d\x0a");
$req->parse("9\x0d\x0a");
$req->parse("abcdefghi\x0d\x0a");
$req->parse("0\x0d\x0a");
$req->parse("X-Trailer1: test\x0d\x0a");
$req->parse("X-Trailer2: 123\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'POST', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13&bar=23#23', 'right URL';
is $req->query_params, 'foo=13&bar=23', 'right parameters';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $req->headers->header('X-Trailer1'), 'test', 'right "X-Trailer1" value';
is $req->headers->header('X-Trailer2'), '123',  'right "X-Trailer2" value';
is $req->headers->content_length, 13, 'right "Content-Length" value';
is $req->content->asset->size, 13, 'right size';
is $req->content->asset->slurp, 'abcdabcdefghi', 'right content';

# Parse HTTP 1.1 chunked request with trailing headers (different variation)
$req = Mojo::Message::Request->new;
$req->parse("POST /foo/bar/baz.html?foo=13&bar=23#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0aTransfer-Enc");
$req->parse("oding: chunked\x0d\x0a");
$req->parse("Trailer: X-Trailer\x0d\x0a\x0d\x0a");
$req->parse("4\x0d\x0a");
$req->parse("abcd\x0d\x0a");
$req->parse("9\x0d\x0a");
$req->parse("abcdefghi\x0d\x0a");
$req->parse("0\x0d\x0aX-Trailer: 777\x0d\x0a\x0d\x0aLEFTOVER");
ok $req->is_done, 'request is done';
is $req->method,  'POST', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13&bar=23#23', 'right URL';
is $req->query_params, 'foo=13&bar=23', 'right parameters';
ok !defined $req->headers->transfer_encoding, 'no "Transfer-Encoding" value';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $req->headers->header('X-Trailer'), '777', 'right "X-Trailer" value';
is $req->headers->content_length, 13, 'right "Content-Length" value';
is $req->content->asset->size, 13, 'right size';
is $req->content->asset->slurp, 'abcdabcdefghi', 'right content';

# Parse HTTP 1.1 chunked request with trailing headers (different variation)
$req = Mojo::Message::Request->new;
$req->parse("POST /foo/bar/baz.html?foo=13&bar=23#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a");
$req->parse("Transfer-Encoding: chunked\x0d\x0a");
$req->parse("Trailer: X-Trailer1; X-Trailer2\x0d\x0a\x0d\x0a");
$req->parse("4\x0d\x0a");
$req->parse("abcd\x0d\x0a");
$req->parse("9\x0d\x0a");
$req->parse("abcdefghi\x0d\x0a");
$req->parse(
  "0\x0d\x0aX-Trailer1: test\x0d\x0aX-Trailer2: 123\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'POST', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13&bar=23#23', 'right URL';
is $req->query_params, 'foo=13&bar=23', 'right parameters';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $req->headers->header('X-Trailer1'), 'test', 'right "X-Trailer1" value';
is $req->headers->header('X-Trailer2'), '123',  'right "X-Trailer2" value';
is $req->headers->content_length, 13, 'right "Content-Length" value';
is $req->content->asset->size, 13, 'right size';
is $req->content->asset->slurp, 'abcdabcdefghi', 'right content';

# Parse HTTP 1.1 chunked request with trailing headers (no Trailer header)
$req = Mojo::Message::Request->new;
$req->parse("POST /foo/bar/baz.html?foo=13&bar=23#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a");
$req->parse("Transfer-Encoding: chunked\x0d\x0a\x0d\x0a");
$req->parse("4\x0d\x0a");
$req->parse("abcd\x0d\x0a");
$req->parse("9\x0d\x0a");
$req->parse("abcdefghi\x0d\x0a");
$req->parse(
  "0\x0d\x0aX-Trailer1: test\x0d\x0aX-Trailer2: 123\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'POST', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13&bar=23#23', 'right URL';
is $req->query_params, 'foo=13&bar=23', 'right parameters';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $req->headers->header('X-Trailer1'), 'test', 'right "X-Trailer1" value';
is $req->headers->header('X-Trailer2'), '123',  'right "X-Trailer2" value';
is $req->headers->content_length, 13, 'right "Content-Length" value';
is $req->content->asset->size, 13, 'right size';
is $req->content->asset->slurp, 'abcdabcdefghi', 'right content';

# Parse HTTP 1.1 multipart request
$req = Mojo::Message::Request->new;
$req->parse("GET /foo/bar/baz.html?foo13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 420x0d\x0a");
$req->parse('Content-Type: multipart/form-data; bo');
$req->parse("undary=----------0xKhTmLbOuNdArY\x0d\x0a\x0d\x0a");
$req->parse("\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$req->parse("Content-Disposition: form-data; name=\"text1\"\x0d\x0a");
$req->parse("\x0d\x0ahallo welt test123\n");
$req->parse("\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$req->parse("Content-Disposition: form-data; name=\"text2\"\x0d\x0a");
$req->parse("\x0d\x0a\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$req->parse('Content-Disposition: form-data; name="upload"; file');
$req->parse("name=\"hello.pl\"\x0d\x0a");
$req->parse("Content-Type: application/octet-stream\x0d\x0a\x0d\x0a");
$req->parse("#!/usr/bin/perl\n\n");
$req->parse("use strict;\n");
$req->parse("use warnings;\n\n");
$req->parse("print \"Hello World :)\\n\"\n");
$req->parse("\x0d\x0a------------0xKhTmLbOuNdArY--");
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo13#23', 'right URL';
is $req->query_params, 'foo13', 'right parameters';
like $req->headers->content_type,
  qr/multipart\/form-data/, 'right "Content-Type" value';
isa_ok $req->content->parts->[0], 'Mojo::Content::Single', 'right part';
isa_ok $req->content->parts->[1], 'Mojo::Content::Single', 'right part';
isa_ok $req->content->parts->[2], 'Mojo::Content::Single', 'right part';
is $req->content->parts->[0]->asset->slurp, "hallo welt test123\n",
  'right content';
is_deeply $req->body_params->to_hash->{text1}, "hallo welt test123\n",
  'right value';
is_deeply $req->body_params->to_hash->{text2}, '', 'right value';
is $req->upload('upload')->filename,  'hello.pl',            'right filename';
isa_ok $req->upload('upload')->asset, 'Mojo::Asset::Memory', 'right file';
is $req->upload('upload')->asset->size, 69, 'right size';
my $file = File::Spec->catfile(File::Temp::tempdir(CLEANUP => 1),
  ("MOJO_TMP." . time . ".txt"));
ok $req->upload('upload')->move_to($file), 'moved file';
is unlink($file), 1, 'unlinked file';

# Parse full HTTP 1.1 proxy request with basic authorization
$req = Mojo::Message::Request->new;
$req->parse("GET http://127.0.0.1/foo/bar HTTP/1.1\x0d\x0a");
$req->parse("Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==\x0d\x0a");
$req->parse("Host: 127.0.0.1\x0d\x0a");
$req->parse(
  "Proxy-Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==\x0d\x0a");
$req->parse("Content-Length: 13\x0d\x0a\x0d\x0a");
$req->parse("Hello World!\n");
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url->base, 'http://Aladdin:open%20sesame@127.0.0.1',
  'right base URL';
is $req->url->base->userinfo, 'Aladdin:open sesame', 'right base userinfo';
is $req->url, 'http://127.0.0.1/foo/bar', 'right URL';
is $req->proxy->userinfo, 'Aladdin:open sesame', 'right proxy userinfo';

# Parse full HTTP 1.1 proxy connect request with basic authorization
$req = Mojo::Message::Request->new;
$req->parse("CONNECT 127.0.0.1:3000 HTTP/1.1\x0d\x0a");
$req->parse("Host: 127.0.0.1\x0d\x0a");
$req->parse(
  "Proxy-Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==\x0d\x0a");
$req->parse("Content-Length: 0\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'CONNECT', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '', 'no full URL';
is $req->url->host,       '127.0.0.1',           'right host';
is $req->url->port,       '3000',                'right port';
is $req->proxy->userinfo, 'Aladdin:open sesame', 'right proxy userinfo';

# Build minimal HTTP 1.1 request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/', 'right URL';
is $req->url->to_abs,   'http://127.0.0.1/', 'right absolute URL';
is $req->headers->host, '127.0.0.1',         'right "Host" value';

# Build HTTP 1.1 start line and header
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';

# Build HTTP 1.1 start line and header (with clone)
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
my $clone = $req->clone;
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';
$clone = Mojo::Message::Request->new->parse($clone->to_string);
ok $clone->is_done, 'request is done';
is $clone->method,  'GET', 'right method';
is $clone->version, '1.1', 'right version';
is $clone->at_least_version('1.0'), 1,     'at least version 1.0';
is $clone->at_least_version('1.2'), undef, 'not version 1.2';
is $clone->url, '/foo/bar', 'right URL';
is $clone->url->to_abs, 'http://127.0.0.1/foo/bar', 'right absolute URL';
is $clone->headers->expect, '100-continue', 'right "Expect" value';
is $clone->headers->host,   '127.0.0.1',    'right "Host" value';

# Build HTTP 1.1 start line and header (with clone and changes)
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$clone = $req->clone;
$clone->method('POST');
$clone->headers->expect('nothing');
$clone->version('1.2');
push @{$clone->url->path->parts}, 'baz';
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';
$clone = Mojo::Message::Request->new->parse($clone->to_string);
ok $clone->is_done, 'request is done';
is $clone->method,  'POST', 'right method';
is $clone->version, '1.2', 'right version';
is $clone->at_least_version('1.0'), 1, 'at least version 1.0';
is $clone->at_least_version('1.2'), 1, 'at least version 1.2';
is $clone->url, '/foo/bar/baz', 'right URL';
is $clone->url->to_abs, 'http://127.0.0.1/foo/bar/baz', 'right absolute URL';
is $clone->headers->expect, 'nothing',   'right "Expect" value';
is $clone->headers->host,   '127.0.0.1', 'right "Host" value';

# Build full HTTP 1.1 request
$req      = Mojo::Message::Request->new;
$finished = undef;
$req->on_finish(sub { $finished = shift->is_done });
$req->method('get');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';
is $req->headers->content_length, '13', 'right "Content-Length" value';
is $req->body, "Hello World!\n", 'right content';
ok $finished, 'finish callback was called';
ok $req->is_done, 'request is done';

# Build full HTTP 1.1 request (with clone)
$req      = Mojo::Message::Request->new;
$finished = undef;
$req->on_finish(sub { $finished = shift->is_done });
$req->method('get');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
$clone = $req->clone;
$req   = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';
is $req->headers->content_length, '13', 'right "Content-Length" value';
is $req->body, "Hello World!\n", 'right content';
ok $finished, 'finish callback was called';
ok $req->is_done, 'request is done';
$finished = undef;
$clone    = Mojo::Message::Request->new->parse($clone->to_string);
ok $clone->is_done, 'request is done';
is $clone->method,  'GET', 'right method';
is $clone->version, '1.1', 'right version';
is $clone->at_least_version('1.0'), 1,     'at least version 1.0';
is $clone->at_least_version('1.2'), undef, 'not version 1.2';
is $clone->url, '/foo/bar', 'right URL';
is $clone->url->to_abs, 'http://127.0.0.1/foo/bar', 'right absolute URL';
is $clone->headers->expect, '100-continue', 'right "Expect" value';
is $clone->headers->host,   '127.0.0.1',    'right "Host" value';
is $clone->headers->content_length, '13', 'right "Content-Length" value';
is $clone->body, "Hello World!\n", 'right content';
ok $finished, 'finish callback was called';
ok $clone->is_done, 'request is done';

# Build HTTP 1.1 request body
$req      = Mojo::Message::Request->new;
$finished = undef;
$req->on_finish(sub { $finished = shift->is_done });
$req->method('get');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
my $i = 0;
while (my $chunk = $req->get_body_chunk($i)) { $i += length $chunk }
ok $finished, 'finish callback was called';
ok $req->is_done, 'request is done';

# Build WebSocket handshake request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://example.com/demo');
$req->headers->host('example.com');
$req->headers->connection('Upgrade');
$req->headers->sec_websocket_accept('abcdef=');
$req->headers->sec_websocket_protocol('sample');
$req->headers->upgrade('WebSocket');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/demo', 'right URL';
is $req->url->to_abs, 'http://example.com/demo', 'right absolute URL';
is $req->headers->connection, 'Upgrade',     'right "Connection" value';
is $req->headers->upgrade,    'WebSocket',   'right "Upgrade" value';
is $req->headers->host,       'example.com', 'right "Host" value';
is $req->headers->content_length, 0, 'right "Content-Length" value';
is $req->headers->sec_websocket_accept, 'abcdef=',
  'right "Sec-WebSocket-Key" value';
is $req->headers->sec_websocket_protocol, 'sample',
  'right "Sec-WebSocket-Protocol" value';
is $req->body, '', 'no content';
ok $finished, 'finish callback was called';
ok $req->is_done, 'request is done';

# Build WebSocket handshake request (with clone)
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://example.com/demo');
$req->headers->host('example.com');
$req->headers->connection('Upgrade');
$req->headers->sec_websocket_accept('abcdef=');
$req->headers->sec_websocket_protocol('sample');
$req->headers->upgrade('WebSocket');
$clone = $req->clone;
$req   = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/demo', 'right URL';
is $req->url->to_abs, 'http://example.com/demo', 'right absolute URL';
is $req->headers->connection, 'Upgrade',     'right "Connection" value';
is $req->headers->upgrade,    'WebSocket',   'right "Upgrade" value';
is $req->headers->host,       'example.com', 'right "Host" value';
is $req->headers->content_length, 0, 'right "Content-Length" value';
is $req->headers->sec_websocket_accept, 'abcdef=',
  'right "Sec-WebSocket-Key" value';
is $req->headers->sec_websocket_protocol, 'sample',
  'right "Sec-WebSocket-Protocol" value';
is $req->body, '', 'no content';
ok $req->is_done, 'request is done';
$clone = Mojo::Message::Request->new->parse($clone->to_string);
ok $clone->is_done, 'request is done';
is $clone->method,  'GET', 'right method';
is $clone->version, '1.1', 'right version';
is $clone->at_least_version('1.0'), 1,     'at least version 1.0';
is $clone->at_least_version('1.2'), undef, 'not version 1.2';
is $clone->url, '/demo', 'right URL';
is $clone->url->to_abs, 'http://example.com/demo', 'right absolute URL';
is $clone->headers->connection, 'Upgrade',     'right "Connection" value';
is $clone->headers->upgrade,    'WebSocket',   'right "Upgrade" value';
is $clone->headers->host,       'example.com', 'right "Host" value';
is $clone->headers->content_length, 0, 'right "Content-Length" value';
is $clone->headers->sec_websocket_accept, 'abcdef=',
  'right "Sec-WebSocket-Key" value';
is $clone->headers->sec_websocket_protocol, 'sample',
  'right "Sec-WebSocket-Protocol" value';
is $clone->body, '', 'no content';
ok $clone->is_done, 'request is done';

# Build full HTTP 1.1 proxy request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
$req->proxy('http://127.0.0.2:8080');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, 'http://127.0.0.1/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';
is $req->headers->content_length, '13', 'right "Content-Length" value';
is $req->body, "Hello World!\n", 'right content';

# Build full HTTP 1.1 proxy request with basic authorization
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://Aladdin:open%20sesame@127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
$req->proxy('http://Aladdin:open%20sesame@127.0.0.2:8080');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, 'http://127.0.0.1/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->proxy->userinfo, 'Aladdin:open sesame',      'right proxy userinfo';
is $req->headers->authorization, 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  'right "Authorization" value';
is $req->headers->expect, '100-continue', 'right "Expect" value';
is $req->headers->host,   '127.0.0.1',    'right "Host" value';
is $req->headers->proxy_authorization, 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  'right "Proxy-Authorization" value';
is $req->headers->content_length, '13', 'right "Content-Length" value';
is $req->body, "Hello World!\n", 'right content';

# Build full HTTP 1.1 proxy request with basic authorization (and clone)
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://Aladdin:open%20sesame@127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
$req->proxy('http://Aladdin:open%20sesame@127.0.0.2:8080');
$clone = $req->clone;
$req   = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, 'http://127.0.0.1/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->proxy->userinfo, 'Aladdin:open sesame',      'right proxy userinfo';
is $req->headers->authorization, 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  'right "Authorization" value';
is $req->headers->expect, '100-continue', 'right "Expect" value';
is $req->headers->host,   '127.0.0.1',    'right "Host" value';
is $req->headers->proxy_authorization, 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  'right "Proxy-Authorization" value';
is $req->headers->content_length, '13', 'right "Content-Length" value';
is $req->body, "Hello World!\n", 'right content';
$clone = Mojo::Message::Request->new->parse($clone->to_string);
ok $clone->is_done, 'request is done';
is $clone->method,  'GET', 'right method';
is $clone->version, '1.1', 'right version';
is $clone->at_least_version('1.0'), 1,     'at least version 1.0';
is $clone->at_least_version('1.2'), undef, 'not version 1.2';
is $clone->url, 'http://127.0.0.1/foo/bar', 'right URL';
is $clone->url->to_abs, 'http://127.0.0.1/foo/bar', 'right absolute URL';
is $clone->proxy->userinfo, 'Aladdin:open sesame', 'right proxy userinfo';
is $clone->headers->authorization, 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  'right "Authorization" value';
is $clone->headers->expect, '100-continue', 'right "Expect" value';
is $clone->headers->host,   '127.0.0.1',    'right "Host" value';
is $clone->headers->proxy_authorization, 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  'right "Proxy-Authorization" value';
is $clone->headers->content_length, '13', 'right "Content-Length" value';
is $clone->body, "Hello World!\n", 'right content';

# Build full HTTP 1.1 proxy connect request with basic authorization
$req = Mojo::Message::Request->new;
$req->method('CONNECT');
$req->url->parse('http://Aladdin:open%20sesame@127.0.0.1:3000/foo/bar');
$req->proxy('http://Aladdin:open%20sesame@127.0.0.2:8080');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'CONNECT', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '', 'no full URL';
is $req->url->host, '127.0.0.1', 'right host';
is $req->url->port, '3000',      'right port';
is $req->url->to_abs, 'http://Aladdin:open%20sesame@127.0.0.1:3000/',
  'right absolute URL';
is $req->proxy->userinfo, 'Aladdin:open sesame', 'right proxy userinfo';
is $req->headers->authorization, 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  'right "Authorization" value';
is $req->headers->host, '127.0.0.1:3000', 'right "Host" value';
is $req->headers->proxy_authorization, 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  'right "Proxy-Authorization" value';

# Build HTTP 1.1 multipart request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->content(Mojo::Content::MultiPart->new);
$req->headers->content_type('multipart/mixed; boundary=7am1X');
push @{$req->content->parts}, Mojo::Content::Single->new;
$req->content->parts->[-1]->asset->add_chunk('Hallo Welt lalalala!');
my $content = Mojo::Content::Single->new;
$content->asset->add_chunk("lala\nfoobar\nperl rocks\n");
$content->headers->content_type('text/plain');
push @{$req->content->parts}, $content;
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar', 'right URL';
is $req->url->to_abs, 'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->host, '127.0.0.1', 'right "Host" value';
is $req->headers->content_length, '104', 'right "Content-Length" value';
is $req->headers->content_type, 'multipart/mixed; boundary=7am1X',
  'right "Content-Type" value';
is $req->content->parts->[0]->asset->slurp, 'Hallo Welt lalalala!',
  'right content';
is $req->content->parts->[1]->headers->content_type, 'text/plain',
  'right "Content-Type" value';
is $req->content->parts->[1]->asset->slurp, "lala\nfoobar\nperl rocks\n",
  'right content';

# Build HTTP 1.1 multipart request (with clone)
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->content(Mojo::Content::MultiPart->new);
$req->headers->content_type('multipart/mixed; boundary=7am1X');
push @{$req->content->parts}, Mojo::Content::Single->new;
$req->content->parts->[-1]->asset->add_chunk('Hallo Welt lalalala!');
$content = Mojo::Content::Single->new;
$content->asset->add_chunk("lala\nfoobar\nperl rocks\n");
$content->headers->content_type('text/plain');
push @{$req->content->parts}, $content;
$clone = $req->clone;
$req   = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar', 'right URL';
is $req->url->to_abs, 'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->host, '127.0.0.1', 'right "Host" value';
is $req->headers->content_length, '104', 'right "Content-Length" value';
is $req->headers->content_type, 'multipart/mixed; boundary=7am1X',
  'right "Content-Type" value';
is $req->content->parts->[0]->asset->slurp, 'Hallo Welt lalalala!',
  'right content';
is $req->content->parts->[1]->headers->content_type, 'text/plain',
  'right "Content-Type" value';
is $req->content->parts->[1]->asset->slurp, "lala\nfoobar\nperl rocks\n",
  'right content';
$clone = Mojo::Message::Request->new->parse($clone->to_string);
ok $clone->is_done, 'request is done';
is $clone->method,  'GET', 'right method';
is $clone->version, '1.1', 'right version';
is $clone->at_least_version('1.0'), 1,     'at least version 1.0';
is $clone->at_least_version('1.2'), undef, 'not version 1.2';
is $clone->url, '/foo/bar', 'right URL';
is $clone->url->to_abs, 'http://127.0.0.1/foo/bar', 'right absolute URL';
is $clone->headers->host, '127.0.0.1', 'right "Host" value';
is $clone->headers->content_length, '104', 'right "Content-Length" value';
is $clone->headers->content_type, 'multipart/mixed; boundary=7am1X',
  'right "Content-Type" value';
is $clone->content->parts->[0]->asset->slurp, 'Hallo Welt lalalala!',
  'right content';
is $clone->content->parts->[1]->headers->content_type, 'text/plain',
  'right "Content-Type" value';
is $clone->content->parts->[1]->asset->slurp, "lala\nfoobar\nperl rocks\n",
  'right content';

# Build HTTP 1.1 chunked request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1:8080/foo/bar');
$req->headers->transfer_encoding('chunked');
my $counter2 = 0;
$req->on_progress(sub { $counter2++ });
$req->write_chunk(
  'hello world!' => sub {
    shift->write_chunk(
      "hello world2!\n\n" => sub {
        my $self = shift;
        $self->write_chunk('');
      }
    );
  }
);
is $req->clone, undef, 'dynamic requests cannot be cloned';
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar', 'right URL';
is $req->url->to_abs, 'http://127.0.0.1:8080/foo/bar', 'right absolute URL';
is $req->headers->host, '127.0.0.1:8080', 'right "Host" value';
is $req->headers->transfer_encoding, undef, 'no "Transfer-Encoding" value';
is $req->body, "hello world!hello world2!\n\n", 'right content';
ok $counter2, 'right counter';

# Build HTTP 1.1 chunked request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->write_chunk('hello world!');
$req->write_chunk("hello world2!\n\n");
$req->write_chunk('');
is $req->clone, undef, 'dynamic requests cannot be cloned';
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar', 'right URL';
is $req->url->to_abs, 'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->host, '127.0.0.1', 'right "Host" value';
is $req->headers->transfer_encoding, undef, 'no "Transfer-Encoding" value';
is $req->body, "hello world!hello world2!\n\n", 'right content';

# Status code and message
my $res = Mojo::Message::Response->new;
is $res->code,            undef,       'no status';
is $res->default_message, 'Not Found', 'right default message';
is $res->message,         undef,       'no message';
$res->message('Test');
is $res->message, 'Test', 'right message';
$res->code(500);
is $res->code,            500,                     'right status';
is $res->message,         'Test',                  'right message';
is $res->default_message, 'Internal Server Error', 'right default message';
$res = Mojo::Message::Response->new;
is $res->code(400)->default_message, 'Bad Request', 'right default message';
$res = Mojo::Message::Response->new;
is $res->code(1)->default_message, '', 'empty default message';

# Parse HTTP 1.1 response start line, no headers and body
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.1 200 OK\x0d\x0a\x0d\x0a");
ok $res->is_done, 'response is done';
is $res->code,    200, 'right status';
is $res->message, 'OK', 'right message';
is $res->version, '1.1', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';

# Parse HTTP 1.1 response start line, no headers and body (no message)
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.1 200\x0d\x0a\x0d\x0a");
ok $res->is_done, 'response is done';
is $res->code,    200, 'right status';
is $res->message, undef, 'no message';
is $res->version, '1.1', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';

# Parse HTTP 0.9 response
$res = Mojo::Message::Response->new;
$res->parse("HTT... this is just a document and valid HTTP 0.9\n\n");
ok $res->is_done, 'response is done';
is $res->version, '0.9', 'right version';
is $res->at_least_version('0.9'), 1,     'at least version 0.9';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->body, "HTT... this is just a document and valid HTTP 0.9\n\n",
  'right content';

# Parse HTTP 1.0 response start line and headers but no body
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.0 404 Damn it\x0d\x0a");
$res->parse("Content-Type: text/plain\x0d\x0a");
$res->parse("Content-Length: 0\x0d\x0a\x0d\x0a");
ok $res->is_done, 'response is done';
is $res->code,    404, 'right status';
is $res->message, 'Damn it', 'right message';
is $res->version, '1.0', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $res->headers->content_length, 0, 'right "Content-Length" value';

# Parse full HTTP 1.0 response
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.0 500 Internal Server Error\x0d\x0a");
$res->parse("Content-Type: text/plain\x0d\x0a");
$res->parse("Content-Length: 27\x0d\x0a\x0d\x0a");
$res->parse("Hello World!\n1234\nlalalala\n");
ok $res->is_done, 'response is done';
is $res->code,    500, 'right status';
is $res->message, 'Internal Server Error', 'right message';
is $res->version, '1.0', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $res->headers->content_length, 27, 'right "Content-Length" value';

# Parse full HTTP 1.0 response (missing Content-Length)
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.0 500 Internal Server Error\x0d\x0a");
$res->parse("Content-Type: text/plain\x0d\x0a");
$res->parse("Connection: close\x0d\x0a\x0d\x0a");
$res->parse("Hello World!\n1234\nlalalala\n");
ok !$res->is_done, 'response is not done';
is $res->code,    500,                     'right status';
is $res->message, 'Internal Server Error', 'right message';
is $res->version, '1.0',                   'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $res->headers->content_length, undef,        'no "Content-Length" value';
is $res->body, "Hello World!\n1234\nlalalala\n", 'right content';

# Parse full HTTP 1.0 response (missing Content-Length and Connection)
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.0 500 Internal Server Error\x0d\x0a");
$res->parse("Content-Type: text/plain\x0d\x0a\x0d\x0a");
$res->parse("Hello World!\n1234\nlalalala\n");
ok !$res->is_done, 'response is not done';
is $res->code,    500,                     'right status';
is $res->message, 'Internal Server Error', 'right message';
is $res->version, '1.0',                   'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $res->headers->content_length, undef,        'no "Content-Length" value';
is $res->body, "Hello World!\n1234\nlalalala\n", 'right content';

# Parse full HTTP 1.1 response (missing Content-Length)
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.1 500 Internal Server Error\x0d\x0a");
$res->parse("Content-Type: text/plain\x0d\x0a");
$res->parse("Connection: close\x0d\x0a\x0d\x0a");
$res->parse("Hello World!\n1234\nlalalala\n");
ok !$res->is_done, 'response is not done';
is $res->code,    500,                     'right status';
is $res->message, 'Internal Server Error', 'right message';
is $res->version, '1.1',                   'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $res->headers->content_length, undef,        'no "Content-Length" value';
is $res->body, "Hello World!\n1234\nlalalala\n", 'right content';

# Parse HTTP 1.1 response (413 error in one big chunk)
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.1 413 Request Entity Too Large\x0d\x0a"
    . "Connection: Close\x0d\x0a"
    . "Date: Tue, 09 Feb 2010 16:34:51 GMT\x0d\x0a"
    . "Server: Mojolicious (Perl)\x0d\x0a"
    . "X-Powered-By: Mojolicious (Perl)\x0d\x0a\x0d\x0a");
ok !$res->is_done, 'response is not done';
is $res->code,    413,                        'right status';
is $res->message, 'Request Entity Too Large', 'right message';
is $res->version, '1.1',                      'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->content_length, undef, 'right "Content-Length" value';

# Parse HTTP 1.1 chunked response
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.1 500 Internal Server Error\x0d\x0a");
$res->parse("Content-Type: text/plain\x0d\x0a");
$res->parse("Transfer-Encoding: chunked\x0d\x0a\x0d\x0a");
$res->parse("4\x0d\x0a");
$res->parse("abcd\x0d\x0a");
$res->parse("9\x0d\x0a");
$res->parse("abcdefghi\x0d\x0a");
$res->parse("0\x0d\x0a\x0d\x0a");
ok $res->is_done, 'response is done';
is $res->code,    500, 'right status';
is $res->message, 'Internal Server Error', 'right message';
is $res->version, '1.1', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $res->headers->content_length, 13, 'right "Content-Length" value';
is $res->content->body_size,      13, 'right size';

# Parse HTTP 1.1 multipart response
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.1 200 OK\x0d\x0a");
$res->parse("Content-Length: 420\x0d\x0a");
$res->parse('Content-Type: multipart/form-data; bo');
$res->parse("undary=----------0xKhTmLbOuNdArY\x0d\x0a\x0d\x0a");
$res->parse("\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$res->parse("Content-Disposition: form-data; name=\"text1\"\x0d\x0a");
$res->parse("\x0d\x0ahallo welt test123\n");
$res->parse("\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$res->parse("Content-Disposition: form-data; name=\"text2\"\x0d\x0a");
$res->parse("\x0d\x0a\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$res->parse('Content-Disposition: form-data; name="upload"; file');
$res->parse("name=\"hello.pl\"\x0d\x0a\x0d\x0a");
$res->parse("Content-Type: application/octet-stream\x0d\x0a\x0d\x0a");
$res->parse("#!/usr/bin/perl\n\n");
$res->parse("use strict;\n");
$res->parse("use warnings;\n\n");
$res->parse("print \"Hello World :)\\n\"\n");
$res->parse("\x0d\x0a------------0xKhTmLbOuNdArY--");
ok $res->is_done, 'response is done';
is $res->code,    200, 'right status';
is $res->message, 'OK', 'right message';
is $res->version, '1.1', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
ok $res->headers->content_type =~ /multipart\/form-data/,
  'right "Content-Type" value';
isa_ok $res->content->parts->[0], 'Mojo::Content::Single', 'right part';
isa_ok $res->content->parts->[1], 'Mojo::Content::Single', 'right part';
isa_ok $res->content->parts->[2], 'Mojo::Content::Single', 'right part';
is $res->content->parts->[0]->asset->slurp, "hallo welt test123\n",
  'right content';

# Parse HTTP 1.1 multipart response with missing boundary
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.1 200 OK\x0d\x0a");
$res->parse("Content-Length: 420\x0d\x0a");
$res->parse("Content-Type: multipart/form-data; bo\x0d\x0a\x0d\x0a");
$res->parse("\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$res->parse("Content-Disposition: form-data; name=\"text1\"\x0d\x0a");
$res->parse("\x0d\x0ahallo welt test123\n");
$res->parse("\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$res->parse("Content-Disposition: form-data; name=\"text2\"\x0d\x0a");
$res->parse("\x0d\x0a\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$res->parse('Content-Disposition: form-data; name="upload"; file');
$res->parse("name=\"hello.pl\"\x0d\x0a\x0d\x0a");
$res->parse("Content-Type: application/octet-stream\x0d\x0a\x0d\x0a");
$res->parse("#!/usr/bin/perl\n\n");
$res->parse("use strict;\n");
$res->parse("use warnings;\n\n");
$res->parse("print \"Hello World :)\\n\"\n");
$res->parse("\x0d\x0a------------0xKhTmLbOuNdArY--");
ok $res->is_done, 'response is done';
is $res->code,    200, 'right status';
is $res->message, 'OK', 'right message';
is $res->version, '1.1', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
ok $res->headers->content_type =~ /multipart\/form-data/,
  'right "Content-Type" value';
isa_ok $res->content, 'Mojo::Content::Single', 'right content';
like $res->content->asset->slurp, qr/hallo\ welt/, 'right content';

# Build HTTP 1.1 response start line with minimal headers
$res = Mojo::Message::Response->new;
$res->code(404);
$res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
$res = Mojo::Message::Response->new->parse($res->to_string);
ok $res->is_done, 'response is done';
is $res->code,    '404', 'right status';
is $res->message, 'Not Found', 'right message';
is $res->version, '1.1', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->date, 'Sun, 17 Aug 2008 16:27:35 GMT', 'right "Date" value';
is $res->headers->content_length, 0, 'right "Content-Length" value';

# Build HTTP 1.1 response start line and header
$res = Mojo::Message::Response->new;
$res->code(200);
$res->headers->connection('keep-alive');
$res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
$res = Mojo::Message::Response->new->parse($res->to_string);
ok $res->is_done, 'response is done';
is $res->code,    '200', 'right status';
is $res->message, 'OK', 'right message';
is $res->version, '1.1', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->connection, 'keep-alive', 'right "Connection" value';
is $res->headers->date, 'Sun, 17 Aug 2008 16:27:35 GMT', 'right "Date" value';
is $res->headers->content_length, 0, 'right "Content-Length" value';

# Build full HTTP 1.1 response
$res = Mojo::Message::Response->new;
$res->code(200);
$res->headers->connection('keep-alive');
$res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
$res->body("Hello World!\n");
$res = Mojo::Message::Response->new->parse($res->to_string);
ok $res->is_done, 'response is done';
is $res->code,    '200', 'right status';
is $res->message, 'OK', 'right message';
is $res->version, '1.1', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->connection, 'keep-alive', 'right "Connection" value';
is $res->headers->date, 'Sun, 17 Aug 2008 16:27:35 GMT', 'right "Date" value';
is $res->headers->content_length, '13', 'right "Content-Length" value';
is $res->body, "Hello World!\n", 'right content';

# Build HTTP 0.9 response
$res = Mojo::Message::Response->new;
$res->version('0.9');
$res->body("this is just a document and valid HTTP 0.9\nlalala\n");
is $res->to_string, "this is just a document and valid HTTP 0.9\nlalala\n",
  'right message';
$res = Mojo::Message::Response->new->parse($res->to_string);
ok $res->is_done, 'response is done';
is $res->code,    undef, 'no status';
is $res->message, undef, 'no message';
is $res->version, '0.9', 'right version';
is $res->at_least_version('0.9'), 1,     'at least version 0.9';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->body, "this is just a document and valid HTTP 0.9\nlalala\n",
  'right content';

# Build HTTP 1.1 multipart response
$res = Mojo::Message::Response->new;
$res->content(Mojo::Content::MultiPart->new);
$res->code(200);
$res->headers->content_type('multipart/mixed; boundary=7am1X');
$res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
push @{$res->content->parts},
  Mojo::Content::Single->new(asset => Mojo::Asset::File->new);
$res->content->parts->[-1]->asset->add_chunk('Hallo Welt lalalalalala!');
$content = Mojo::Content::Single->new;
$content->asset->add_chunk("lala\nfoobar\nperl rocks\n");
$content->headers->content_type('text/plain');
push @{$res->content->parts}, $content;
$res = Mojo::Message::Response->new->parse($res->to_string);
ok $res->is_done, 'response is done';
is $res->code,    200, 'right status';
is $res->message, 'OK', 'right message';
is $res->version, '1.1', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->date, 'Sun, 17 Aug 2008 16:27:35 GMT', 'right "Date" value';
is $res->headers->content_length, '108', 'right "Content-Length" value';
is $res->headers->content_type, 'multipart/mixed; boundary=7am1X',
  'right "Content-Type" value';
is $res->content->parts->[0]->asset->slurp, 'Hallo Welt lalalalalala!',
  'right content';
is $res->content->parts->[1]->headers->content_type, 'text/plain',
  'right "Content-Type" value';
is $res->content->parts->[1]->asset->slurp, "lala\nfoobar\nperl rocks\n",
  'right content';

# Parse Lighttpd like CGI environment variables and a body
$req = Mojo::Message::Request->new;
$req->parse(
  HTTP_CONTENT_LENGTH => 11,
  HTTP_EXPECT         => '100-continue',
  PATH_INFO           => '/test/index.cgi/foo/bar',
  QUERY_STRING        => 'lalala=23&bar=baz',
  REQUEST_METHOD      => 'POST',
  SCRIPT_NAME         => '/test/index.cgi',
  HTTP_HOST           => 'localhost:8080',
  SERVER_PROTOCOL     => 'HTTP/1.0'
);
$req->parse('Hello World');
ok $req->is_done, 'request is done';
is $req->method, 'POST', 'right method';
is $req->headers->expect, '100-continue', 'right "Expect" value';
is $req->url->path,       'foo/bar',      'right path';
is $req->url->base->path, '/test/index.cgi/', 'right base path';
is $req->url->base->host, 'localhost',        'right base host';
is $req->url->base->port, 8080,               'right base port';
is $req->url->query, 'lalala=23&bar=baz', 'right query';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->body, 'Hello World', 'right content';
is $req->url->to_abs->to_string,
  'http://localhost:8080/test/index.cgi/foo/bar?lalala=23&bar=baz',
  'right absolute URL';

# Parse Lighttpd like CGI environment variables and a body
# (behind reverse proxy)
$req = Mojo::Message::Request->new;
$req->parse(
  HTTP_CONTENT_LENGTH  => 11,
  HTTP_EXPECT          => '100-continue',
  HTTP_X_FORWARDED_FOR => '127.0.0.1',
  PATH_INFO            => '/test/index.cgi/foo/bar',
  QUERY_STRING         => 'lalala=23&bar=baz',
  REQUEST_METHOD       => 'POST',
  SCRIPT_NAME          => '/test/index.cgi',
  HTTP_HOST            => 'mojolicio.us',
  SERVER_PROTOCOL      => 'HTTP/1.0'
);
$req->parse('Hello World');
ok $req->is_done, 'request is done';
is $req->method, 'POST', 'right method';
is $req->headers->expect, '100-continue', 'right "Expect" value';
is $req->url->path,       'foo/bar',      'right path';
is $req->url->base->path, '/test/index.cgi/', 'right base path';
is $req->url->base->host, 'mojolicio.us',     'right base host';
is $req->url->base->port, '',                 'right base port';
is $req->url->query, 'lalala=23&bar=baz', 'right query';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->body, 'Hello World', 'right content';
is $req->url->to_abs->to_string,
  'http://mojolicio.us/test/index.cgi/foo/bar?lalala=23&bar=baz',
  'right absolute URL';

# Parse Apache like CGI environment variables and a body
$req = Mojo::Message::Request->new;
$req->parse(
  CONTENT_LENGTH  => 11,
  CONTENT_TYPE    => 'application/x-www-form-urlencoded',
  HTTP_EXPECT     => '100-continue',
  PATH_INFO       => '/test/index.cgi/foo/bar',
  QUERY_STRING    => 'lalala=23&bar=baz',
  REQUEST_METHOD  => 'POST',
  SCRIPT_NAME     => '/test/index.cgi',
  HTTP_HOST       => 'localhost:8080',
  SERVER_PROTOCOL => 'HTTP/1.0'
);
$req->parse('hello=world');
ok $req->is_done, 'request is done';
is $req->method, 'POST', 'right method';
is $req->headers->expect, '100-continue', 'right "Expect" value';
is $req->url->path,       'foo/bar',      'right path';
is $req->url->base->path, '/test/index.cgi/', 'right base path';
is $req->url->base->host, 'localhost',        'right base host';
is $req->url->base->port, 8080,               'right base port';
is $req->url->query, 'lalala=23&bar=baz', 'right query';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->body, 'hello=world', 'right content';
is_deeply $req->param('hello'), 'world', 'right value';
is $req->url->to_abs->to_string,
  'http://localhost:8080/test/index.cgi/foo/bar?lalala=23&bar=baz',
  'right absolute URL';

# Parse Apache like CGI environment variables with basic authorization
$req = Mojo::Message::Request->new;
$req->parse(
  CONTENT_LENGTH           => 11,
  HTTP_Authorization       => 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  HTTP_Proxy_Authorization => 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  CONTENT_TYPE             => 'application/x-www-form-urlencoded',
  HTTP_EXPECT              => '100-continue',
  PATH_INFO                => '/test/index.cgi/foo/bar',
  QUERY_STRING             => 'lalala=23&bar=baz',
  REQUEST_METHOD           => 'POST',
  SCRIPT_NAME              => '/test/index.cgi',
  HTTP_HOST                => 'localhost:8080',
  SERVER_PROTOCOL          => 'HTTP/1.0'
);
$req->parse('hello=world');
ok $req->is_done, 'request is done';
is $req->method, 'POST', 'right method';
is $req->headers->expect, '100-continue', 'right "Expect" value';
is $req->url->path,       'foo/bar',      'right path';
is $req->url->base->path, '/test/index.cgi/', 'right base path';
is $req->url->base->host, 'localhost',        'right base host';
is $req->url->base->port, 8080,               'right base port';
is $req->url->query, 'lalala=23&bar=baz', 'right query';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->body, 'hello=world', 'right content';
is_deeply $req->param('hello'), 'world', 'right value';
is $req->url->to_abs->to_string, 'http://Aladdin:open%20sesame@localhost:8080'
  . '/test/index.cgi/foo/bar?lalala=23&bar=baz', 'right absolute URL';
is $req->url->base,
  'http://Aladdin:open%20sesame@localhost:8080/test/index.cgi/',
  'right base URL';
is $req->url->base->userinfo, 'Aladdin:open sesame', 'right userinfo';
is $req->url, 'foo/bar?lalala=23&bar=baz', 'right URL';
is $req->proxy->userinfo, 'Aladdin:open sesame', 'right proxy userinfo';

# Parse Apache 2.2 (win32) like CGI environment variables and a body
$req = Mojo::Message::Request->new;
$req->parse(
  CONTENT_LENGTH  => 87,
  CONTENT_TYPE    => 'application/x-www-form-urlencoded; charset=UTF-8',
  PATH_INFO       => '',
  QUERY_STRING    => '',
  REQUEST_METHOD  => 'POST',
  SCRIPT_NAME     => '/index.pl',
  HTTP_HOST       => 'test1',
  SERVER_PROTOCOL => 'HTTP/1.1'
);
$req->parse('request=&ajax=true&login=test&password=111&');
$req->parse('edition=db6d8b30-16df-4ecd-be2f-c8194f94e1f4');
ok $req->is_done, 'request is done';
is $req->method, 'POST', 'right method';
is $req->url->path, '', 'right path';
is $req->url->base->path, '/index.pl/', 'right base path';
is $req->url->base->host, 'test1',      'right base host';
is $req->url->base->port, '',           'right base port';
ok !$req->url->query->to_string, 'no query';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->body, 'request=&ajax=true&login=test&password=111&'
  . 'edition=db6d8b30-16df-4ecd-be2f-c8194f94e1f4', 'right content';
is $req->param('ajax'),     'true', 'right value';
is $req->param('login'),    'test', 'right value';
is $req->param('password'), '111',  'right value';
is $req->param('edition'), 'db6d8b30-16df-4ecd-be2f-c8194f94e1f4',
  'right value';
is $req->url->to_abs->to_string, 'http://test1/index.pl',
  'right absolute URL';

# Parse Apache 2.2 (win32) like CGI environment variables and a body
$req = Mojo::Message::Request->new;
$req->parse(
  CONTENT_LENGTH  => 87,
  CONTENT_TYPE    => 'application/x-www-form-urlencoded; charset=UTF-8',
  PATH_INFO       => '',
  QUERY_STRING    => '',
  REQUEST_METHOD  => 'POST',
  SCRIPT_NAME     => '/index.pl',
  HTTP_HOST       => 'test1',
  SERVER_PROTOCOL => 'HTTP/1.1'
);
$req->parse('request=&ajax=true&login=test&password=111&');
$req->parse('edition=db6d8b30-16df-4ecd-be2f-c8194f94e1f4');
ok $req->is_done, 'request is done';
is $req->method, 'POST', 'right method';
is $req->url->path, '', 'right path';
is $req->url->base->path, '/index.pl/', 'right base path';
is $req->url->base->host, 'test1',      'right base host';
is $req->url->base->port, '',           'right base port';
ok !$req->url->query->to_string, 'no query';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->body, 'request=&ajax=true&login=test&password=111&'
  . 'edition=db6d8b30-16df-4ecd-be2f-c8194f94e1f4', 'right content';
is $req->param('ajax'),     'true', 'right value';
is $req->param('login'),    'test', 'right value';
is $req->param('password'), '111',  'right value';
is $req->param('edition'), 'db6d8b30-16df-4ecd-be2f-c8194f94e1f4',
  'right value';
is $req->url->to_abs->to_string, 'http://test1/index.pl',
  'right absolute URL';

# Parse Apache 2.2.14 like CGI environment variables and a body (root)
$req = Mojo::Message::Request->new;
$req->parse(
  SCRIPT_NAME       => '/diag/upload',
  SERVER_NAME       => '127.0.0.1',
  SERVER_ADMIN      => '[no address given]',
  PATH_INFO         => '/diag/upload',
  HTTP_CONNECTION   => 'Keep-Alive',
  REQUEST_METHOD    => 'POST',
  CONTENT_LENGTH    => '11',
  SCRIPT_FILENAME   => '/tmp/SnLu1cQ3t2/test.fcgi',
  SERVER_SOFTWARE   => 'Apache/2.2.14 (Unix) mod_fastcgi/2.4.2',
  QUERY_STRING      => '',
  REMOTE_PORT       => '58232',
  HTTP_USER_AGENT   => 'Mojolicious (Perl)',
  SERVER_PORT       => '13028',
  SERVER_SIGNATURE  => '',
  REMOTE_ADDR       => '127.0.0.1',
  CONTENT_TYPE      => 'application/x-www-form-urlencoded; charset=UTF-8',
  SERVER_PROTOCOL   => 'HTTP/1.1',
  REQUEST_URI       => '/diag/upload',
  GATEWAY_INTERFACE => 'CGI/1.1',
  SERVER_ADDR       => '127.0.0.1',
  DOCUMENT_ROOT     => '/tmp/SnLu1cQ3t2',
  PATH_TRANSLATED   => '/tmp/test.fcgi/diag/upload',
  HTTP_HOST         => '127.0.0.1:13028'
);
$req->parse('hello=world');
ok $req->is_done, 'request is done';
is $req->method, 'POST', 'right method';
is $req->url->base->host, '127.0.0.1', 'right base host';
is $req->url->base->port, 13028,       'right base port';
is $req->url->path, '', 'right path';
is $req->url->base->path, '/diag/upload/', 'right base path';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->is_secure, undef,         'not secure';
is $req->body,      'hello=world', 'right content';
is_deeply $req->param('hello'), 'world', 'right parameters';
is $req->url->to_abs->to_string, 'http://127.0.0.1:13028/diag/upload',
  'right absolute URL';

# Parse Apache 2.2.11 like CGI environment variables and a body (HTTPS)
$req = Mojo::Message::Request->new;
$req->parse(
  CONTENT_LENGTH  => 11,
  CONTENT_TYPE    => 'application/x-www-form-urlencoded',
  PATH_INFO       => '/foo/bar',
  QUERY_STRING    => '',
  REQUEST_METHOD  => 'GET',
  SCRIPT_NAME     => '/test/index.cgi',
  HTTP_HOST       => 'localhost',
  HTTPS           => 'on',
  SERVER_PROTOCOL => 'HTTP/1.0'
);
$req->parse('hello=world');
ok $req->is_done, 'request is done';
is $req->method, 'GET', 'right method';
is $req->url->base->host, 'localhost', 'right base host';
is $req->url->path, 'foo/bar', 'right path';
is $req->url->base->path, '/test/index.cgi/', 'right base path';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->is_secure, 1,             'is secure';
is $req->body,      'hello=world', 'right content';
is_deeply $req->param('hello'), 'world', 'right parameters';
is $req->url->to_abs->to_string, 'https://localhost/test/index.cgi/foo/bar',
  'right absolute URL';

# Parse Apache 2.2.11 like CGI environment variables and a body
# (trailing slash)
$req = Mojo::Message::Request->new;
$req->parse(
  CONTENT_LENGTH  => 11,
  CONTENT_TYPE    => 'application/x-www-form-urlencoded',
  PATH_INFO       => '/foo/bar/',
  QUERY_STRING    => '',
  REQUEST_METHOD  => 'GET',
  SCRIPT_NAME     => '/test/index.cgi',
  HTTP_HOST       => 'localhost',
  SERVER_PROTOCOL => 'HTTP/1.0'
);
$req->parse('hello=world');
ok $req->is_done, 'request is done';
is $req->method, 'GET', 'right method';
is $req->url->base->host, 'localhost', 'right base host';
is $req->url->path, 'foo/bar/', 'right path';
is $req->url->base->path, '/test/index.cgi/', 'right base path';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->body, 'hello=world', 'right content';
is_deeply $req->param('hello'), 'world', 'right parameters';
is $req->url->to_abs->to_string, 'http://localhost/test/index.cgi/foo/bar/',
  'right absolute URL';

# Parse Apache 2.2.11 like CGI environment variables and a body
# (no SCRIPT_NAME)
$req = Mojo::Message::Request->new;
$req->parse(
  CONTENT_LENGTH  => 11,
  CONTENT_TYPE    => 'application/x-www-form-urlencoded',
  PATH_INFO       => '/foo/bar',
  QUERY_STRING    => '',
  REQUEST_METHOD  => 'GET',
  HTTP_HOST       => 'localhost',
  SERVER_PROTOCOL => 'HTTP/1.0'
);
$req->parse('hello=world');
ok $req->is_done, 'request is done';
is $req->method, 'GET', 'right method';
is $req->url->base->host, 'localhost', 'right base host';
is $req->url->path, '/foo/bar', 'right path';
is $req->url->base->path, '', 'right base path';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->body, 'hello=world', 'right content';
is_deeply $req->param('hello'), 'world', 'right parameters';
is $req->url->to_abs->to_string, 'http://localhost/foo/bar',
  'right absolute URL';

# Parse Apache 2.2.11 like CGI environment variables and a body
# (no PATH_INFO)
$req = Mojo::Message::Request->new;
$req->parse(
  CONTENT_LENGTH  => 11,
  CONTENT_TYPE    => 'application/x-www-form-urlencoded',
  QUERY_STRING    => '',
  REQUEST_METHOD  => 'GET',
  SCRIPT_NAME     => '/test/index.cgi',
  HTTP_HOST       => 'localhost',
  SERVER_PROTOCOL => 'HTTP/1.0'
);
$req->parse('hello=world');
ok $req->is_done, 'request is done';
is $req->method, 'GET', 'right method';
is $req->url->base->host, 'localhost', 'right base host';
is $req->url->path, '', 'right path';
is $req->url->base->path, '/test/index.cgi/', 'right base path';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->body, 'hello=world', 'right content';
is_deeply $req->param('hello'), 'world', 'right parameters';
is $req->url->to_abs->to_string, 'http://localhost/test/index.cgi',
  'right absolute URL';

# Parse Apache 2.2.9 like CGI environment variables (root without PATH_INFO)
$req = Mojo::Message::Request->new;
$req->parse(
  SCRIPT_NAME     => '/cgi-bin/bootylicious/bootylicious.pl',
  HTTP_CONNECTION => 'keep-alive',
  HTTP_HOST       => 'getbootylicious.org',
  REQUEST_METHOD  => 'GET',
  QUERY_STRING    => '',
  REQUEST_URI     => '/cgi-bin/bootylicious/bootylicious.pl',
  SERVER_PROTOCOL => 'HTTP/1.1',
);
ok $req->is_done, 'request is done';
is $req->method, 'GET', 'right method';
is $req->url->base->host, 'getbootylicious.org', 'right base host';
is $req->url->path, '', 'right path';
is $req->url->base->path, '/cgi-bin/bootylicious/bootylicious.pl/',
  'right base path';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url->to_abs->to_string,
  'http://getbootylicious.org/cgi-bin/bootylicious/bootylicious.pl',
  'right absolute URL';

# Parse Apache mod_fastcgi like CGI environment variables
# (multipart file upload)
$req = Mojo::Message::Request->new;
$req->parse(
  SCRIPT_NAME      => '',
  SERVER_NAME      => '127.0.0.1',
  SERVER_ADMIN     => '[no address given]',
  PATH_INFO        => '/diag/upload',
  HTTP_CONNECTION  => 'Keep-Alive',
  REQUEST_METHOD   => 'POST',
  CONTENT_LENGTH   => '135',
  SCRIPT_FILENAME  => '/tmp/SnLu1cQ3t2/test.fcgi',
  SERVER_SOFTWARE  => 'Apache/2.2.14 (Unix) mod_fastcgi/2.4.2',
  QUERY_STRING     => '',
  REMOTE_PORT      => '58232',
  HTTP_USER_AGENT  => 'Mojolicious (Perl)',
  SERVER_PORT      => '13028',
  SERVER_SIGNATURE => '',
  REMOTE_ADDR      => '127.0.0.1',
  CONTENT_TYPE     => 'multipart/form-data; boundary=8jXGX',
  SERVER_PROTOCOL  => 'HTTP/1.1',
  PATH => '/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin',
  REQUEST_URI       => '/diag/upload',
  GATEWAY_INTERFACE => 'CGI/1.1',
  SERVER_ADDR       => '127.0.0.1',
  DOCUMENT_ROOT     => '/tmp/SnLu1cQ3t2',
  PATH_TRANSLATED   => '/tmp/test.fcgi/diag/upload',
  HTTP_HOST         => '127.0.0.1:13028'
);
$req->parse("--8jXGX\x0d\x0a");
$req->parse(
  "Content-Disposition: form-data; name=\"file\"; filename=\"file\"\x0d\x0a"
    . "Content-Type: application/octet-stream\x0d\x0a\x0d\x0a");
$req->parse('11023456789');
$req->parse("\x0d\x0a--8jXGX--");
ok $req->is_done, 'request is done';
is $req->method, 'POST', 'right method';
is $req->url->base->host, '127.0.0.1', 'right base host';
is $req->url->path, '/diag/upload', 'right path';
is $req->url->base->path, '', 'no base path';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url->to_abs->to_string,
  'http://127.0.0.1:13028/diag/upload',
  'right absolute URL';
$file = $req->upload('file');
is $file->slurp, '11023456789', 'right uploaded content';

# Parse Apache 2.2.9 like CGI environment variables with mod_rewrite
# (random file and "RewriteRule ^(.*)$ monkey.cgi/$1 [L]")
$req = Mojo::Message::Request->new;
$req->parse(
  HTTP_CONNECTION => 'keep-alive',
  HTTP_HOST       => 'kraih.com',
  QUERY_STRING    => '',
  REQUEST_METHOD  => 'GET',
  REQUEST_URI     => '/sandbox-myapp/feed/bannana',
  SCRIPT_NAME     => '/sandbox-myapp/monkey.cgi',
  PATH_INFO       => '/feed/bannana',
  SERVER_PROTOCOL => 'HTTP/1.1',
);
ok $req->is_done, 'request is done';
is $req->method, 'GET', 'right method';
is $req->url->base->host, 'kraih.com', 'right base host';
is $req->url->path, 'feed/bannana', 'right path';
is $req->url->base->path, '/sandbox-myapp/monkey.cgi/', 'right base path';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url->to_abs->to_string,
  'http://kraih.com/sandbox-myapp/monkey.cgi/feed/bannana',
  'right absolute URL';
ok $req->url->base->parse('http://kraih.com/sandbox-myapp/'), 'rewritten';
is $req->url, 'feed/bannana', 'right relative URL';
is $req->url->to_abs->to_string,
  'http://kraih.com/sandbox-myapp/feed/bannana',
  'right absolute URL';

# Parse Apache 2.2.9 like CGI environment variables with mod_rewrite
# (root and "RewriteRule ^(.*)$ monkey.cgi/$1 [L]")
$req = Mojo::Message::Request->new;
$req->parse(
  HTTP_CONNECTION => 'keep-alive',
  HTTP_HOST       => 'kraih.com',
  QUERY_STRING    => '',
  REQUEST_METHOD  => 'GET',
  REQUEST_URI     => '/sandbox-myapp/',
  SCRIPT_NAME     => '/sandbox-myapp/monkey.cgi',
  SERVER_PROTOCOL => 'HTTP/1.1',
);
ok $req->is_done, 'request is done';
is $req->method, 'GET', 'right method';
is $req->url->base->host, 'kraih.com', 'right base host';
is $req->url->path, '', 'right path';
is $req->url->base->path, '/sandbox-myapp/monkey.cgi/', 'right base path';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url->to_abs->to_string,
  'http://kraih.com/sandbox-myapp/monkey.cgi',
  'right absolute URL';
ok $req->url->base->parse('http://kraih.com/sandbox-myapp/'), 'rewritten';
is $req->url->base->path, '/sandbox-myapp/', 'right base path';
is $req->url->to_abs->to_string, 'http://kraih.com/sandbox-myapp',
  'right absolute URL';

# Parse response with cookie
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.0 200 OK\x0d\x0a");
$res->parse("Content-Type: text/plain\x0d\x0a");
$res->parse("Content-Length: 27\x0d\x0a");
$res->parse("Set-Cookie: foo=bar; Version=1; Path=/test\x0d\x0a\x0d\x0a");
$res->parse("Hello World!\n1234\nlalalala\n");
ok $res->is_done, 'response is done';
is $res->code,    200, 'right status';
is $res->message, 'OK', 'right message';
is $res->version, '1.0', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $res->headers->content_length, 27, 'right "Content-Length" value';
is $res->headers->set_cookie, 'foo=bar; Version=1; Path=/test',
  'right "Set-Cookie" value';
my $cookies = $res->cookies;
is $cookies->[0]->name,    'foo',   'right name';
is $cookies->[0]->value,   'bar',   'right value';
is $cookies->[0]->version, 1,       'right version';
is $cookies->[0]->path,    '/test', 'right path';
is $res->cookie('foo')->value, 'bar',   'right value';
is $res->cookie('foo')->path,  '/test', 'right path';

# Parse WebSocket handshake response
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.1 101 Switching Protocols\x0d\x0a");
$res->parse("Upgrade: WebSocket\x0d\x0a");
$res->parse("Connection: Upgrade\x0d\x0a");
$res->parse("Sec-WebSocket-Accept: abcdef=\x0d\x0a");
$res->parse("Sec-WebSocket-Protocol: sample\x0d\x0a\x0d\x0a");
ok $res->is_done, 'response is done';
is $res->code,    101, 'right status';
is $res->message, 'Switching Protocols', 'right message';
is $res->version, '1.1', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->upgrade,    'WebSocket', 'right "Upgrade" value';
is $res->headers->connection, 'Upgrade',   'right "Connection" value';
is $res->headers->sec_websocket_accept, 'abcdef=',
  'right "Sec-WebSocket-Accept" value';
is $res->headers->sec_websocket_protocol, 'sample',
  'right "Sec-WebSocket-Protocol" value';
is $res->body, '', 'no content';

# Build WebSocket handshake response
$res = Mojo::Message::Response->new;
$res->code(101);
$res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
$res->headers->upgrade('WebSocket');
$res->headers->connection('Upgrade');
$res->headers->sec_websocket_accept('abcdef=');
$res->headers->sec_websocket_protocol('sample');
$res = Mojo::Message::Response->new->parse($res->to_string);
ok $res->is_done, 'response is done';
is $res->code,    '101', 'right status';
is $res->message, 'Switching Protocols', 'right message';
is $res->version, '1.1', 'right version';
is $res->at_least_version('1.0'), 1,     'at least version 1.0';
is $res->at_least_version('1.2'), undef, 'not version 1.2';
is $res->headers->connection, 'Upgrade', 'right "Connection" value';
is $res->headers->date, 'Sun, 17 Aug 2008 16:27:35 GMT', 'right "Date" value';
is $res->headers->upgrade,        'WebSocket', 'right "Upgrade" value';
is $res->headers->content_length, 0,           'right "Content-Length" value';
is $res->headers->sec_websocket_accept, 'abcdef=',
  'right "Sec-WebSocket-Accept" value';
is $res->headers->sec_websocket_protocol,
  'sample', 'right "Sec-WebSocket-Protocol" value';
is $res->body, '', 'no content';

# Build and parse HTTP 1.1 response with 3 cookies
$res = Mojo::Message::Response->new;
$res->code(404);
$res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
$res->cookies(
  {name => 'foo', value => 'bar', path => '/foobar'},
  {name => 'bar', value => 'baz', path => '/test/23'}
);
$res->headers->set_cookie2(
  Mojo::Cookie::Response->new(
    name  => 'baz',
    value => 'yada',
    path  => '/foobar'
  )
);
ok !!$res->to_string, 'message built';
my $res2 = Mojo::Message::Response->new;
$res2->parse($res->to_string);
ok $res2->is_done, 'response is done';
is $res2->code,    404, 'right status';
is $res2->version, '1.1', 'right version';
is $res2->at_least_version('1.0'), 1,     'at least version 1.0';
is $res2->at_least_version('1.2'), undef, 'not version 1.2';
is $res2->headers->content_length, 0, 'right "Content-Length" value';
is defined $res2->cookie('foo'), 1, 'right value';
is defined $res2->cookie('baz'), 1, 'right value';
is defined $res2->cookie('bar'), 1, 'right value';
is $res2->cookie('foo')->path,  '/foobar',  'right path';
is $res2->cookie('foo')->value, 'bar',      'right value';
is $res2->cookie('baz')->path,  '/foobar',  'right path';
is $res2->cookie('baz')->value, 'yada',     'right value';
is $res2->cookie('bar')->path,  '/test/23', 'right path';
is $res2->cookie('bar')->value, 'baz',      'right value';

# Build response with callback (make sure it's called)
$res = Mojo::Message::Response->new;
$res->code(200);
$res->headers->content_length(10);
$res->write('lala', sub { die "Body coderef was called properly\n" });
$res->get_body_chunk(0);
eval { $res->get_body_chunk(3) };
is $@, "Body coderef was called properly\n", 'right error';

# Build response with callback (consistency calls)
$res = Mojo::Message::Response->new;
my $body = 'I is here';
$res->headers->content_length(length($body));
my $cb;
$cb = sub { shift->write(substr($body, pop, 1), $cb) };
$res->write('', $cb);
my $full   = '';
my $count  = 0;
my $offset = 0;
while (1) {
  my $chunk = $res->get_body_chunk($offset);
  last unless $chunk;
  $full .= $chunk;
  $offset = length($full);
  $count++;
}
$res->fix_headers;
is $res->headers->connection, undef, 'no "Connection" value';
is $res->is_dynamic, undef, 'no dynamic content';
is $count, length($body), 'right length';
is $full, $body, 'right content';

# Build response with callback (no Content-Length header)
$res  = Mojo::Message::Response->new;
$body = 'I is here';
$cb   = sub { shift->write(substr($body, pop, 1), $cb) };
$res->write('', $cb);
$res->fix_headers;
$full   = '';
$count  = 0;
$offset = 0;
while (1) {
  my $chunk = $res->get_body_chunk($offset);
  last unless $chunk;
  $full .= $chunk;
  $offset = length($full);
  $count++;
}
is $res->headers->connection, 'close', 'right "Connection" value';
is $res->is_dynamic, 1, 'dynamic content';
is $count, length($body), 'right length';
is $full, $body, 'right content';

# Build full HTTP 1.1 request with cookies
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->cookies(
  Mojo::Cookie::Request->new(
    name  => 'foo',
    value => 'bar',
    path  => '/foobar'

  ),
  Mojo::Cookie::Request->new(
    name  => 'bar',
    value => 'baz',
    path  => '/test/23'

  )
);
$req->body("Hello World!\n");
ok !!$req->to_string, 'message built';
my $req2 = Mojo::Message::Request->new;
$req2->parse($req->to_string);
ok $req2->is_done, 'request is done';
is $req2->method,  'GET', 'right method';
is $req2->version, '1.1', 'right version';
is $req2->at_least_version('1.0'), 1,     'at least version 1.0';
is $req2->at_least_version('1.2'), undef, 'not version 1.2';
is $req2->headers->expect, '100-continue', 'right "Expect" value';
is $req2->headers->host,   '127.0.0.1',    'right "Host" value';
is $req2->headers->content_length, 13, 'right "Content-Length" value';
is $req2->headers->cookie,
  '$Version=1; foo=bar; $Path=/foobar; bar=baz; $Path=/test/23',
  'right "Cookie" value';
is $req2->url, '/foo/bar', 'right URL';
is $req2->url->to_abs, 'http://127.0.0.1/foo/bar', 'right absolute URL';
is defined $req2->cookie('foo'), 1,  'right value';
is defined $req2->cookie('baz'), '', 'no value';
is defined $req2->cookie('bar'), 1,  'right value';
is $req2->cookie('foo')->path,  '/foobar',  'right path';
is $req2->cookie('foo')->value, 'bar',      'right value';
is $req2->cookie('bar')->path,  '/test/23', 'right path';
is $req2->cookie('bar')->value, 'baz',      'right value';
is $req2->body, "Hello World!\n", 'right content';

# Parse full HTTP 1.0 request with cookies and progress callback
$req = Mojo::Message::Request->new;
my $counter = 0;
$req->on_progress(sub { $counter++ });
is $counter, 0, 'right count';
is $req->content->is_parsing_body, undef, 'is not parsing body';
is $req->is_done, undef, 'request is not done';
$req->parse('GET /foo/bar/baz.html?fo');
is $counter, 1, 'right count';
is $req->content->is_parsing_body, undef, 'is not parsing body';
is $req->is_done, undef, 'request is not done';
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
is $counter, 2, 'right count';
is $req->content->is_parsing_body, undef, 'is not parsing body';
is $req->is_done, undef, 'request is not done';
$req->parse('-Type: text/');
is $counter, 3, 'right count';
is $req->content->is_parsing_body, undef, 'is not parsing body';
is $req->is_done, undef, 'request is not done';
$req->parse("plain\x0d\x0a");
is $counter, 4, 'right count';
is $req->content->is_parsing_body, undef, 'is not parsing body';
is $req->is_done, undef, 'request is not done';
$req->parse('Cookie: $Version=1; foo=bar; $Path=/foobar; bar=baz; $Path=/t');
is $counter, 5, 'right count';
is $req->content->is_parsing_body, undef, 'is not parsing body';
is $req->is_done, undef, 'request is not done';
$req->parse("est/23\x0d\x0a");
is $counter, 6, 'right count';
is $req->content->is_parsing_body, undef, 'is not parsing body';
is $req->is_done, undef, 'request is not done';
$req->parse("Content-Length: 27\x0d\x0a\x0d\x0aHell");
is $counter, 7, 'right count';
is $req->content->is_parsing_body, 1, 'is parsing body';
is $req->is_done, undef, 'request is not done';
$req->parse("o World!\n1234\nlalalala\n");
is $counter, 8, 'right count';
is $req->content->is_parsing_body, undef, 'is not parsing body';
is $req->is_done, 1,     'request is done';
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, 27, 'right "Content-Length" value';
$cookies = $req->cookies;
is $cookies->[0]->name,    'foo',      'right name';
is $cookies->[0]->value,   'bar',      'right value';
is $cookies->[0]->version, 1,          'right version';
is $cookies->[0]->path,    '/foobar',  'right path';
is $cookies->[1]->name,    'bar',      'right name';
is $cookies->[1]->value,   'baz',      'right value';
is $cookies->[1]->version, 1,          'right version';
is $cookies->[1]->path,    '/test/23', 'right path';

# WebKit multipart/form-data request
$req = Mojo::Message::Request->new;
$req->parse("POST /example/testform_handler HTTP/1.1\x0d\x0a"
    . "User-Agent: Mozilla/5.0\x0d\x0a"
    . 'Content-Type: multipart/form-data; '
    . "boundary=----WebKitFormBoundaryi5BnD9J9zoTMiSuP\x0d\x0a"
    . "Content-Length: 323\x0d\x0aConnection: keep-alive\x0d\x0a"
    . "Host: 127.0.0.1:3000\x0d\x0a\x0d\x0a"
    . "------WebKitFormBoundaryi5BnD9J9zoTMiSuP\x0d\x0a"
    . "Content-Disposition: form-data; name=\"Vorname\"\x0d\x0a"
    . "\x0d\x0aT\x0d\x0a------WebKitFormBoundaryi5BnD9J9zoTMiSuP\x0d"
    . "\x0aContent-Disposition: form-data; name=\"Zuname\"\x0d\x0a"
    . "\x0d\x0a\x0d\x0a------WebKitFormBoundaryi5BnD9J9zoTMiSuP\x0d"
    . "\x0aContent-Disposition: form-data; name=\"Text\"\x0d\x0a"
    . "\x0d\x0a\x0d\x0a------WebKitFormBoundaryi5BnD9J9zoTMiSuP--"
    . "\x0d\x0a");
ok $req->is_done, 'request is done';
is_deeply $req->param('Vorname'), 'T', 'right value';

# Google Chrome multipart/form-data request
$req = Mojo::Message::Request->new;
$req->parse("POST / HTTP/1.0\x0d\x0a"
    . "Host: 127.0.0.1:10002\x0d\x0a"
    . "Connection: close\x0d\x0a"
    . "User-Agent: Mozilla/5.0 (X11; U; Linux x86_64; en-US) AppleWebKit/5"
    . "32.9 (KHTML, like Gecko) Chrome/5.0.307.11 Safari/532.9\x0d\x0a"
    . "Referer: http://example.org/\x0d\x0a"
    . "Content-Length: 819\x0d\x0a"
    . "Cache-Control: max-age=0\x0d\x0a"
    . "Origin: http://example.org\x0d\x0a"
    . "Content-Type: multipart/form-data; boundary=----WebKitFormBoundaryY"
    . "GjwdkpB6ZLCZQbX\x0d\x0a"
    . "Accept: application/xml,application/xhtml+xml,text/html;q=0.9,text/"
    . "plain;q=0.8,image/png,*/*;q=0.5\x0d\x0a"
    . "Accept-Encoding: gzip,deflate,sdch\x0d\x0a"
    . "Cookie: mojolicious=BAcIMTIzNDU2NzgECAgIAwIAAAAXDGFsZXgudm9yb25vdgQ"
    . "AAAB1c2VyBp6FjksAAAAABwAAAGV4cGlyZXM=--1641adddfe885276cda0deb7475f"
    . "153a\x0d\x0a"
    . "Accept-Language: ru-RU,ru;q=0.8,en-US;q=0.6,en;q=0.4\x0d\x0a"
    . "Accept-Charset: windows-1251,utf-8;q=0.7,*;q=0.3\x0d\x0a\x0d\x0a"
    . "------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
    . "Content-Disposition: form-data; name=\"fname\"\x0d\x0a\x0d\x0a"
    . "Иван"
    . "\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
    . "Content-Disposition: form-data; name=\"sname\"\x0d\x0a\x0d\x0a"
    . "Иванов"
    . "\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
    . "Content-Disposition: form-data; name=\"sex\"\x0d\x0a\x0d\x0a"
    . "мужской"
    . "\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
    . "Content-Disposition: form-data; name=\"bdate\"\x0d\x0a\x0d\x0a"
    . "16.02.1987"
    . "\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
    . "Content-Disposition: form-data; name=\"phone\"\x0d\x0a\x0d\x0a"
    . "1234567890"
    . "\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
    . "Content-Disposition: form-data; name=\"avatar\"; filename=\"аватар."
    . "jpg\"\x0d\x0a"
    . "Content-Type: image/jpeg\x0d\x0a\x0d\x0a" . "1234"
    . "\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
    . "Content-Disposition: form-data; name=\"submit\"\x0d\x0a\x0d\x0a"
    . "Сохранить"
    . "\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX--\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'POST', 'right method';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/', 'right URL';
is $req->cookie('mojolicious')->value,
  'BAcIMTIzNDU2NzgECAgIAwIAAAAXDGFsZXgudm9yb25vdgQAAAB1c2VyBp6FjksAAAAABwA'
  . 'AAGV4cGlyZXM=--1641adddfe885276cda0deb7475f153a', 'right value';
like $req->headers->content_type, qr/multipart\/form-data/,
  'right "Content-Type" value';
is $req->param('fname'), 'Иван',       'right value';
is $req->param('sname'), 'Иванов',   'right value';
is $req->param('sex'),   'мужской', 'right value';
is $req->param('bdate'), '16.02.1987',     'right value';
is $req->param('phone'), '1234567890',     'right value';
my $upload = $req->upload('avatar');
is $upload->isa('Mojo::Upload'), 1, 'right upload';
is $upload->headers->content_type, 'image/jpeg', 'right "Content-Type" value';
is $upload->filename, 'аватар.jpg', 'right filename';
is $upload->size,     4,                  'right size';
is $upload->slurp,    '1234',             'right content';

# Firefox multipart/form-data request
$req = Mojo::Message::Request->new;
$req->parse("POST / HTTP/1.0\x0d\x0a"
    . "Host: 127.0.0.1:10002\x0d\x0a"
    . "Connection: close\x0d\x0a"
    . "User-Agent: Mozilla/5.0 (X11; U; Linux x86_64; ru; rv:1.9.1.8) Geck"
    . "o/20100214 Ubuntu/9.10 (karmic) Firefox/3.5.8\x0d\x0a"
    . "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q"
    . "=0.8\x0d\x0a"
    . "Accept-Language: ru,en-us;q=0.7,en;q=0.3\x0d\x0a"
    . "Accept-Encoding: gzip,deflate\x0d\x0a"
    . "Accept-Charset: windows-1251,utf-8;q=0.7,*;q=0.7\x0d\x0a"
    . "Referer: http://example.org/\x0d\x0a"
    . "Cookie: mojolicious=BAcIMTIzNDU2NzgECAgIAwIAAAAXDGFsZXgudm9yb25vdgQ"
    . "AAAB1c2VyBiWFjksAAAAABwAAAGV4cGlyZXM=--cd933a37999e0fa8d7804205e891"
    . "93a7\x0d\x0a"
    . "Content-Type: multipart/form-data; boundary=-----------------------"
    . "----213090722714721300002030499922\x0d\x0a"
    . "Content-Length: 971\x0d\x0a\x0d\x0a"
    . "-----------------------------213090722714721300002030499922\x0d\x0a"
    . "Content-Disposition: form-data; name=\"fname\"\x0d\x0a\x0d\x0a"
    . "Иван"
    . "\x0d\x0a-----------------------------213090722714721300002030499922"
    . "\x0d\x0a"
    . "Content-Disposition: form-data; name=\"sname\"\x0d\x0a\x0d\x0a"
    . "Иванов"
    . "\x0d\x0a-----------------------------213090722714721300002030499922"
    . "\x0d\x0a"
    . "Content-Disposition: form-data; name=\"sex\"\x0d\x0a\x0d\x0a"
    . "мужской"
    . "\x0d\x0a-----------------------------213090722714721300002030499922"
    . "\x0d\x0a"
    . "Content-Disposition: form-data; name=\"bdate\"\x0d\x0a\x0d\x0a"
    . "16.02.1987"
    . "\x0d\x0a-----------------------------213090722714721300002030499922"
    . "\x0d\x0a"
    . "Content-Disposition: form-data; name=\"phone\"\x0d\x0a\x0d\x0a"
    . "1234567890"
    . "\x0d\x0a-----------------------------213090722714721300002030499922"
    . "\x0d\x0a"
    . "Content-Disposition: form-data; name=\"avatar\"; filename=\"аватар."
    . "jpg\"\x0d\x0a"
    . "Content-Type: image/jpeg\x0d\x0a\x0d\x0a" . "1234"
    . "\x0d\x0a-----------------------------213090722714721300002030499922"
    . "\x0d\x0a"
    . "Content-Disposition: form-data; name=\"submit\"\x0d\x0a\x0d\x0a"
    . "Сохранить"
    . "\x0d\x0a-----------------------------2130907227147213000020304999"
    . "22--");
ok $req->is_done, 'request is done';
is $req->method,  'POST', 'right method';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/', 'right URL';
is $req->cookie('mojolicious')->value,
  'BAcIMTIzNDU2NzgECAgIAwIAAAAXDGFsZXgudm9yb25vdgQAAAB1c2VyBiWFjksAAAAABwA'
  . 'AAGV4cGlyZXM=--cd933a37999e0fa8d7804205e89193a7', 'right value';
like $req->headers->content_type, qr/multipart\/form-data/,
  'right "Content-Type" value';
is $req->param('fname'), 'Иван',       'right value';
is $req->param('sname'), 'Иванов',   'right value';
is $req->param('sex'),   'мужской', 'right value';
is $req->param('bdate'), '16.02.1987',     'right value';
is $req->param('phone'), '1234567890',     'right value';
$upload = $req->upload('avatar');
is $upload->isa('Mojo::Upload'), 1, 'right upload';
is $upload->headers->content_type, 'image/jpeg', 'right "Content-Type" value';
is $upload->filename, 'аватар.jpg', 'right filename';
is $upload->size,     4,                  'right size';
is $upload->slurp,    '1234',             'right content';

# Opera multipart/form-data request
$req = Mojo::Message::Request->new;
$req->parse("POST / HTTP/1.0\x0d\x0a"
    . "Host: 127.0.0.1:10002\x0d\x0a"
    . "Connection: close\x0d\x0a"
    . "User-Agent: Opera/9.80 (X11; Linux x86_64; U; ru) Presto/2.2.15 Ver"
    . "sion/10.10\x0d\x0a"
    . "Accept: text/html, application/xml;q=0.9, application/xhtml+xml, im"
    . "age/png, image/jpeg, image/gif, image/x-xbitmap, */*;q=0.1\x0d\x0a"
    . "Accept-Language: ru-RU,ru;q=0.9,en;q=0.8\x0d\x0a"
    . "Accept-Charset: iso-8859-1, utf-8, utf-16, *;q=0.1\x0d\x0a"
    . "Accept-Encoding: deflate, gzip, x-gzip, identity, *;q=0\x0d\x0a"
    . "Referer: http://example.org/\x0d\x0a"
    . "Cookie: mojolicious=BAcIMTIzNDU2NzgECAgIAwIAAAAXDGFsZXgudm9yb25vdgQ"
    . "AAAB1c2VyBhaIjksAAAAABwAAAGV4cGlyZXM=--78a58a94f98ae5b75a489be1189f"
    . "2672\x0d\x0a"
    . "Cookie2: \$Version=1\x0d\x0a"
    . "TE: deflate, gzip, chunked, identity, trailers\x0d\x0a"
    . "Content-Length: 771\x0d\x0a"
    . "Content-Type: multipart/form-data; boundary=----------IWq9cR9mYYG66"
    . "8xwSn56f0\x0d\x0a\x0d\x0a"
    . "------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
    . "Content-Disposition: form-data; name=\"fname\"\x0d\x0a\x0d\x0a"
    . "Иван"
    . "\x0d\x0a------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
    . "Content-Disposition: form-data; name=\"sname\"\x0d\x0a\x0d\x0a"
    . "Иванов"
    . "\x0d\x0a------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
    . "Content-Disposition: form-data; name=\"sex\"\x0d\x0a\x0d\x0a"
    . "мужской"
    . "\x0d\x0a------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
    . "Content-Disposition: form-data; name=\"bdate\"\x0d\x0a\x0d\x0a"
    . "16.02.1987"
    . "\x0d\x0a------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
    . "Content-Disposition: form-data; name=\"phone\"\x0d\x0a\x0d\x0a"
    . "1234567890"
    . "\x0d\x0a------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
    . "Content-Disposition: form-data; name=\"avatar\"; filename=\"аватар."
    . "jpg\"\x0d\x0a"
    . "Content-Type: image/jpeg\x0d\x0a\x0d\x0a" . "1234"
    . "\x0d\x0a------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
    . "Content-Disposition: form-data; name=\"submit\"\x0d\x0a\x0d\x0a"
    . "Сохранить"
    . "\x0d\x0a------------IWq9cR9mYYG668xwSn56f0--");
ok $req->is_done, 'request is done';
is $req->method,  'POST', 'right method';
is $req->version, '1.0', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/', 'right URL';
is $req->cookie('mojolicious')->value,
  'BAcIMTIzNDU2NzgECAgIAwIAAAAXDGFsZXgudm9yb25vdgQAAAB1c2VyBhaIjksAAAAABwA'
  . 'AAGV4cGlyZXM=--78a58a94f98ae5b75a489be1189f2672', 'right value';
like $req->headers->content_type, qr/multipart\/form-data/,
  'right "Content-Type" value';
is $req->param('fname'), 'Иван',       'right value';
is $req->param('sname'), 'Иванов',   'right value';
is $req->param('sex'),   'мужской', 'right value';
is $req->param('bdate'), '16.02.1987',     'right value';
is $req->param('phone'), '1234567890',     'right value';
$upload = $req->upload('avatar');
is $upload->isa('Mojo::Upload'), 1, 'right upload';
is $upload->headers->content_type, 'image/jpeg', 'right "Content-Type" value';
is $upload->filename, 'аватар.jpg', 'right filename';
is $upload->size,     4,                  'right size';
is $upload->slurp,    '1234',             'right content';

# Parse ~ in URL
$req = Mojo::Message::Request->new;
$req->parse("GET /~foobar/ HTTP/1.1\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/~foobar/', 'right URL';

# Parse : in URL
$req = Mojo::Message::Request->new;
$req->parse("GET /perldoc?Mojo::Message::Request HTTP/1.1\x0d\x0a\x0d\x0a");
ok $req->is_done, 'request is done';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
is $req->url, '/perldoc?Mojo%3A%3AMessage%3A%3ARequest', 'right URL';
is $req->url->query->params->[0], 'Mojo::Message::Request', 'right value';

# Body helper
$req = Mojo::Message::Request->new;
$req->body('hi there!');
is $req->body, 'hi there!', 'right content';
$req->body('');
is $req->body, '', 'right content';
$req->body('hi there!');
is $req->body, 'hi there!', 'right content';
$req->body(undef);
is $req->body, '', 'right content';
$req->body(sub { });
isa_ok $req->body, 'CODE', 'body is callback';
$req->body(undef);
is $req->body, '', 'right content';
$req->body(0);
is $req->body, 0, 'right content';
$req->body(sub { });
isa_ok $req->body, 'CODE', 'body is callback';
$req->body('hello!');
is $req->body, 'hello!', 'right content';
is $req->content->on_read, undef, 'no read callback';
$req->content(Mojo::Content::MultiPart->new);
$req->body('hi!');
is $req->body, 'hi!', 'right content';

# Version management
my $m = Mojo::Message->new;
is $req->version, '1.1', 'right version';
is $req->at_least_version('1.0'), 1,     'at least version 1.0';
is $req->at_least_version('1.2'), undef, 'not version 1.2';
ok $m->at_least_version('1.1'), 'at least version 1.1';
ok $m->at_least_version('1.0'), 'at least version 1.0';
$m = Mojo::Message->new(version => '1.0');
is $m->version, '1.0', 'right version';
ok !$m->at_least_version('1.1'), 'not version 1.1';
ok $m->at_least_version('1.0'), 'at least version 1.0';
$m = Mojo::Message->new(version => '0.9');
ok !$m->at_least_version('1.0'), 'not version 1.0';
ok $m->at_least_version('0.9'), 'at least version 0.9';

# "headers" chaining
$req = Mojo::Message::Request->new->headers(Mojo::Headers->new);
is $req->isa('Mojo::Message::Request'), 1, 'right request';

# Build dom from request with charset
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.1 200 OK\x0a");
$res->parse(
  "Content-Type: application/atom+xml; charset=UTF-8; type=feed\x0a");
$res->parse("\x0a");
$res->body('<p>foo <a href="/">bar</a><a href="/baz">baz</a></p>');
ok !$res->is_done, 'request is not done';
is $res->headers->content_type,
  'application/atom+xml; charset=UTF-8; type=feed',
  'right "Content-Type" value';
ok $res->dom, 'dom built';
$count = 0;
$res->dom('a')->each(sub { $count++ });
is $count, 2, 'all anchors found';
