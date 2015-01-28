use Mojo::Base -strict;

use Test::More;
use File::Spec::Functions 'catfile';
use File::Temp 'tempdir';
use IO::Compress::Gzip 'gzip';
use Mojo::Content::Single;
use Mojo::Content::MultiPart;
use Mojo::Cookie::Request;
use Mojo::Message::Request;
use Mojo::Util 'encode';

# Parse HTTP 1.1 message with huge "Cookie" header exceeding all limits
my $req = Mojo::Message::Request->new;
my $finished;
$req->max_message_size($req->headers->max_line_size);
my $huge = 'a=b; ' x $req->max_message_size;
$req->on(finish => sub { $finished = shift->is_finished });
ok !$req->is_limit_exceeded, 'limit is not exceeded';
$req->parse("PUT /upload HTTP/1.1\x0d\x0aCookie: $huge\x0d\x0a");
ok $req->is_limit_exceeded, 'limit is exceeded';
$req->parse("Content-Length: 0\x0d\x0a\x0d\x0a");
ok $finished, 'finish event has been emitted';
ok $req->is_finished, 'request is finished';
is $req->content->leftovers, '', 'no leftovers';
is $req->error->{message}, 'Maximum message size exceeded', 'right error';
ok $req->is_limit_exceeded, 'limit is exceeded';
is $req->method,            'PUT', 'right method';
is $req->version,           '1.1', 'right version';
is $req->url,               '/upload', 'right URL';
is $req->cookie('a'), undef, 'no value';

# Parse HTTP 1.1 message with huge "Cookie" header exceeding line limit
$req = Mojo::Message::Request->new;
is $req->headers->max_line_size, 8192, 'right size';
is $req->headers->max_lines,     100,  'right number';
$req->parse("GET / HTTP/1.1\x0d\x0a");
$req->parse("Cookie: @{['a=b; ' x 131072]}\x0d\x0a");
$req->parse("Content-Length: 0\x0d\x0a\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->error->{message}, 'Maximum header size exceeded', 'right error';
ok $req->is_limit_exceeded, 'limit is exceeded';
is $req->method,            'GET', 'right method';
is $req->version,           '1.1', 'right version';
is $req->url,               '/', 'right URL';
is $req->cookie('a'), undef, 'no value';
is $req->body, '', 'no content';

# Parse HTTP 1.1 message with huge "Cookie" header exceeding line limit
# (alternative)
$req = Mojo::Message::Request->new;
$req->parse("GET / HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 4\x0d\x0aCookie: @{['a=b; ' x 131072]}\x0d\x0a"
    . "X-Test: 23\x0d\x0a\x0d\x0aabcd");
ok $req->is_finished, 'request is finished';
is $req->error->{message}, 'Maximum header size exceeded', 'right error';
ok $req->is_limit_exceeded, 'limit is exceeded';
is $req->method,            'GET', 'right method';
is $req->version,           '1.1', 'right version';
is $req->url,               '/', 'right URL';
is $req->cookie('a'), undef, 'no value';
is $req->body, '', 'no content';

# Parse HTTP 1.1 message with content exceeding line limit
$req = Mojo::Message::Request->new;
is $req->max_message_size, 16777216, 'right size';
$req->parse("GET / HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 655360\x0d\x0a\x0d\x0a@{['a=b; ' x 131072]}");
ok $req->is_finished, 'request is finished';
is $req->error,       undef, 'no error';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/', 'right URL';
is $req->body,        'a=b; ' x 131072, 'right content';

# Parse broken start-line
$req = Mojo::Message::Request->new;
$req->parse("12345\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->error->{message}, 'Bad request start-line', 'right error';
ok !$req->is_limit_exceeded, 'limit is not exceeded';

# Parse broken HTTP 1.1 message with header exceeding line limit
$req = Mojo::Message::Request->new;
$req->parse("GET / HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 0\x0d\x0a");
ok !$req->is_limit_exceeded, 'limit is not exceeded';
$req->parse("Foo: @{['a' x 8192]}");
ok $req->is_finished, 'request is finished';
is $req->error->{message}, 'Maximum header size exceeded', 'right error';
ok $req->is_limit_exceeded, 'limit is exceeded';
is $req->method,            'GET', 'right method';
is $req->version,           '1.1', 'right version';
is $req->url,               '/', 'right URL';
is $req->headers->header('Foo'), undef, 'no "Foo" value';
is $req->body, '', 'no content';

# Parse broken HTTP 1.1 message with start-line exceeding line limit
$req = Mojo::Message::Request->new;
is $req->max_line_size, 8192, 'right size';
is $req->headers->max_lines, 100, 'right number';
$req->parse("GET /@{['abcd' x 131072]} HTTP/1.1");
ok $req->is_finished, 'request is finished';
is $req->error->{message}, 'Maximum start-line size exceeded', 'right error';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->url,     '',    'no URL';
is $req->cookie('a'), undef, 'no value';
is $req->body, '', 'no content';

# Parse broken HTTP 1.1 message with start-line exceeding line limit
# (alternative)
$req = Mojo::Message::Request->new;
$req->parse('GET /');
$req->parse('abcd' x 131072);
ok $req->is_finished, 'request is finished';
is $req->error->{message}, 'Maximum start-line size exceeded', 'right error';
is $req->method,  'GET', 'right method';
is $req->version, '1.1', 'right version';
is $req->url,     '',    'no URL';
is $req->cookie('a'), undef, 'no value';
is $req->body, '', 'no content';

# Parse pipelined HTTP 1.1 messages exceeding leftover limit
$req = Mojo::Message::Request->new;
is $req->content->max_leftover_size, 262144, 'right size';
$req->parse("GET /one HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 120000\x0d\x0a\x0d\x0a@{['a' x 120000]}");
ok $req->is_finished, 'request is finished';
is $req->content->leftovers, '', 'no leftovers';
$req->parse("GET /two HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 120000\x0d\x0a\x0d\x0a@{['b' x 120000]}");
is length($req->content->leftovers), 120045, 'right size';
$req->parse("GET /three HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 120000\x0d\x0a\x0d\x0a@{['c' x 120000]}");
is length($req->content->leftovers), 240092, 'right size';
$req->parse("GET /four HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 120000\x0d\x0a\x0d\x0a@{['d' x 120000]}");
is length($req->content->leftovers), 360138, 'right size';
$req->parse("GET /five HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 120000\x0d\x0a\x0d\x0a@{['e' x 120000]}");
is length($req->content->leftovers), 360138, 'right size';
is $req->error,   undef,  'no error';
is $req->method,  'GET',  'right method';
is $req->version, '1.1',  'right version';
is $req->url,     '/one', 'right URL';
is $req->body, 'a' x 120000, 'right content';

# Parse pipelined HTTP 1.1 messages exceeding leftover limit (chunked)
$req = Mojo::Message::Request->new;
$req->parse("GET /one HTTP/1.1\x0d\x0a");
$req->parse("Transfer-Encoding: chunked\x0d\x0a\x0d\x0a");
$req->parse("ea60\x0d\x0a");
$req->parse('a' x 60000);
$req->parse("\x0d\x0aea60\x0d\x0a");
$req->parse('a' x 60000);
$req->parse("\x0d\x0a0\x0d\x0a\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->content->leftovers, '', 'no leftovers';
$req->parse("GET /two HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 120000\x0d\x0a\x0d\x0a@{['b' x 120000]}");
is length($req->content->leftovers), 120045, 'right size';
$req->parse("GET /three HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 120000\x0d\x0a\x0d\x0a@{['c' x 120000]}");
is length($req->content->leftovers), 240092, 'right size';
$req->parse("GET /four HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 120000\x0d\x0a\x0d\x0a@{['d' x 120000]}");
is length($req->content->leftovers), 360138, 'right size';
$req->parse("GET /five HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 120000\x0d\x0a\x0d\x0a@{['e' x 120000]}");
is length($req->content->leftovers), 360138, 'right size';
is $req->error,   undef,  'no error';
is $req->method,  'GET',  'right method';
is $req->version, '1.1',  'right version';
is $req->url,     '/one', 'right URL';
is $req->body, 'a' x 120000, 'right content';

# Parse HTTP 1.1 start-line, no headers and body
$req = Mojo::Message::Request->new;
$req->parse("GET / HTTP/1.1\x0d\x0a\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/', 'right URL';

# Parse HTTP 1.1 start-line, no headers and body (small chunks)
$req = Mojo::Message::Request->new;
$req->parse('G');
ok !$req->is_finished, 'request is not finished';
$req->parse('E');
ok !$req->is_finished, 'request is not finished';
$req->parse('T');
ok !$req->is_finished, 'request is not finished';
$req->parse(' ');
ok !$req->is_finished, 'request is not finished';
$req->parse('/');
ok !$req->is_finished, 'request is not finished';
$req->parse(' ');
ok !$req->is_finished, 'request is not finished';
$req->parse('H');
ok !$req->is_finished, 'request is not finished';
$req->parse('T');
ok !$req->is_finished, 'request is not finished';
$req->parse('T');
ok !$req->is_finished, 'request is not finished';
$req->parse('P');
ok !$req->is_finished, 'request is not finished';
$req->parse('/');
ok !$req->is_finished, 'request is not finished';
$req->parse('1');
ok !$req->is_finished, 'request is not finished';
$req->parse('.');
ok !$req->is_finished, 'request is not finished';
$req->parse('1');
ok !$req->is_finished, 'request is not finished';
$req->parse("\x0d");
ok !$req->is_finished, 'request is not finished';
$req->parse("\x0a");
ok !$req->is_finished, 'request is not finished';
$req->parse("\x0d");
ok !$req->is_finished, 'request is not finished';
$req->parse("\x0a");
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/', 'right URL';

# Parse pipelined HTTP 1.1 start-line, no headers and body
$req = Mojo::Message::Request->new;
$req->parse("GET / HTTP/1.1\x0d\x0a\x0d\x0aGET / HTTP/1.1\x0d\x0a\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->content->leftovers, "GET / HTTP/1.1\x0d\x0a\x0d\x0a",
  'second request in leftovers';

# Parse HTTP 1.1 start-line, no headers and body with leading CRLFs
$req = Mojo::Message::Request->new;
$req->parse("\x0d\x0a GET / HTTP/1.1\x0d\x0a\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/', 'right URL';

# Parse WebSocket handshake request
$req = Mojo::Message::Request->new;
$req->parse("GET /demo HTTP/1.1\x0d\x0a");
$req->parse("Host: example.com\x0d\x0a");
$req->parse("Connection: Upgrade\x0d\x0a");
$req->parse("Sec-WebSocket-Key: abcdef=\x0d\x0a");
$req->parse("Sec-WebSocket-Protocol: sample\x0d\x0a");
$req->parse("Upgrade: websocket\x0d\x0a\x0d\x0a");
ok $req->is_finished,  'request is finished';
ok $req->is_handshake, 'request is WebSocket handshake';
is $req->method,       'GET', 'right method';
is $req->version,      '1.1', 'right version';
is $req->url,          '/demo', 'right URL';
is $req->headers->host,       'example.com', 'right "Host" value';
is $req->headers->connection, 'Upgrade',     'right "Connection" value';
is $req->headers->sec_websocket_protocol, 'sample',
  'right "Sec-WebSocket-Protocol" value';
is $req->headers->upgrade, 'websocket', 'right "Upgrade" value';
is $req->headers->sec_websocket_key, 'abcdef=',
  'right "Sec-WebSocket-Key" value';
is $req->body, '', 'no content';

# Parse HTTP 1.0 start-line and headers, no body
$req = Mojo::Message::Request->new;
$req->parse("GET /foo/bar/baz.html HTTP/1.0\x0d\x0a");
$req->parse("Content-Type: text/plain;charset=UTF-8\x0d\x0a");
$req->parse("Content-Length: 0\x0d\x0a\x0d\x0a");
ok $req->is_finished, 'request is finished';
ok !$req->is_handshake, 'request is not a WebSocket handshake';
is $req->method,  'GET',               'right method';
is $req->version, '1.0',               'right version';
is $req->url,     '/foo/bar/baz.html', 'right URL';
is $req->headers->content_type, 'text/plain;charset=UTF-8',
  'right "Content-Type" value';
is $req->headers->content_length, 0,       'right "Content-Length" value';
is $req->content->charset,        'UTF-8', 'right charset';

# Parse HTTP 1.0 start-line and headers, no body (missing Content-Length)
$req = Mojo::Message::Request->new;
$req->parse("GET /foo/bar/baz.html HTTP/1.0\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.0', 'right version';
is $req->url,         '/foo/bar/baz.html', 'right URL';
is $req->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, undef,        'no "Content-Length" value';

# Parse full HTTP 1.0 request (file storage)
{
  local $ENV{MOJO_MAX_MEMORY_SIZE} = 12;
  $req = Mojo::Message::Request->new;
  my ($upgrade, $size);
  $req->content->asset->on(
    upgrade => sub {
      my ($mem, $file) = @_;
      $upgrade = $file->is_file;
      $size    = $file->size;
    }
  );
  is $req->content->asset->max_memory_size, 12, 'right size';
  is $req->content->progress, 0, 'right progress';
  $req->parse('GET /foo/bar/baz.html?fo');
  is $req->content->progress, 0, 'right progress';
  $req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
  $req->parse('-Type: text/');
  is $req->content->progress, 0, 'right progress';
  $req->parse("plain\x0d\x0aContent-Length: 27\x0d\x0a\x0d\x0aHell");
  is $req->content->progress, 4, 'right progress';
  ok !$req->content->asset->is_file, 'stored in memory';
  ok !$upgrade, 'upgrade event has not been emitted';
  $req->parse("o World!\n");
  ok $upgrade, 'upgrade event has been emitted';
  is $size, 0, 'file was empty when upgrade event got emitted';
  is $req->content->progress, 13, 'right progress';
  ok $req->content->asset->is_file, 'stored in file';
  $req->parse("1234\nlalalala\n");
  is $req->content->progress, 27, 'right progress';
  ok $req->content->asset->is_file, 'stored in file';
  ok $req->is_finished, 'request is finished';
  is $req->method,      'GET', 'right method';
  is $req->version,     '1.0', 'right version';
  is $req->url,         '/foo/bar/baz.html?foo=13#23', 'right URL';
  is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
  is $req->headers->content_length, 27, 'right "Content-Length" value';
}

# Parse HTTP 1.0 start-line and headers, no body (missing Content-Length)
$req = Mojo::Message::Request->new;
$req->parse("GET /foo/bar/baz.html HTTP/1.0\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a");
$req->parse("Connection: Close\x0d\x0a\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.0', 'right version';
is $req->url,         '/foo/bar/baz.html', 'right URL';
is $req->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, undef,        'no "Content-Length" value';

# Parse HTTP 1.0 start-line (with line size limit)
{
  local $ENV{MOJO_MAX_LINE_SIZE} = 5;
  $req = Mojo::Message::Request->new;
  my $limit;
  $req->on(finish => sub { $limit = shift->is_limit_exceeded });
  ok !$req->is_limit_exceeded, 'limit is not exceeded';
  is $req->headers->max_line_size, 5, 'right size';
  $req->parse('GET /foo/bar/baz.html HTTP/1');
  ok $req->is_finished, 'request is finished';
  is $req->error->{message}, 'Maximum start-line size exceeded', 'right error';
  ok $req->is_limit_exceeded, 'limit is exceeded';
  ok $limit, 'limit is exceeded';
  $req->error({message => 'Nothing important.'});
  is $req->error->{message}, 'Nothing important.', 'right error';
  ok $req->is_limit_exceeded, 'limit is still exceeded';
}

# Parse HTTP 1.0 start-line and headers (with line size limit)
{
  local $ENV{MOJO_MAX_LINE_SIZE} = 20;
  $req = Mojo::Message::Request->new;
  is $req->max_line_size, 20, 'right size';
  $req->parse("GET / HTTP/1.0\x0d\x0a");
  $req->parse("Content-Type: text/plain\x0d\x0a");
  ok $req->is_finished, 'request is finished';
  is $req->error->{message}, 'Maximum header size exceeded', 'right error';
  ok $req->is_limit_exceeded, 'limit is exceeded';
}

# Parse HTTP 1.0 start-line (with message size limit)
{
  local $ENV{MOJO_MAX_MESSAGE_SIZE} = 5;
  $req = Mojo::Message::Request->new;
  my $limit;
  $req->on(finish => sub { $limit = shift->is_limit_exceeded });
  is $req->max_message_size, 5, 'right size';
  $req->parse('GET /foo/bar/baz.html HTTP/1');
  ok $req->is_finished, 'request is finished';
  is $req->error->{message}, 'Maximum message size exceeded', 'right error';
  ok $req->is_limit_exceeded, 'limit is exceeded';
  ok $limit, 'limit is exceeded';
}

# Parse HTTP 1.0 start-line and headers (with message size limit)
{
  local $ENV{MOJO_MAX_MESSAGE_SIZE} = 20;
  $req = Mojo::Message::Request->new;
  $req->parse("GET / HTTP/1.0\x0d\x0a");
  $req->parse("Content-Type: text/plain\x0d\x0a");
  ok $req->is_finished, 'request is finished';
  is $req->error->{message}, 'Maximum message size exceeded', 'right error';
  ok $req->is_limit_exceeded, 'limit is exceeded';
}

# Parse HTTP 1.0 start-line, headers and body (with message size limit)
{
  local $ENV{MOJO_MAX_MESSAGE_SIZE} = 50;
  $req = Mojo::Message::Request->new;
  $req->parse("GET / HTTP/1.0\x0d\x0a");
  $req->parse("Content-Length: 24\x0d\x0a\x0d\x0a");
  $req->parse('Hello World!');
  $req->parse('Hello World!');
  ok $req->is_finished, 'request is finished';
  is $req->error->{message}, 'Maximum message size exceeded', 'right error';
  ok $req->is_limit_exceeded, 'limit is exceeded';
}

# Parse HTTP 1.1 message with headers exceeding line limit
{
  local $ENV{MOJO_MAX_LINES} = 5;
  $req = Mojo::Message::Request->new;
  is $req->headers->max_lines, 5, 'right number';
  $req->parse("GET / HTTP/1.1\x0d\x0a");
  $req->parse("A: a\x0d\x0aB: b\x0d\x0aC: c\x0d\x0aD: d\x0d\x0a");
  ok !$req->is_limit_exceeded, 'limit is not exceeded';
  $req->parse("D: d\x0d\x0a\x0d\x0a");
  ok $req->is_finished, 'request is finished';
  is $req->error->{message}, 'Maximum header size exceeded', 'right error';
  ok $req->is_limit_exceeded, 'limit is exceeded';
  is $req->method,            'GET', 'right method';
  is $req->version,           '1.1', 'right version';
  is $req->url,               '/', 'right URL';
}

# Parse full HTTP 1.0 request (solitary LF)
$req = Mojo::Message::Request->new;
my $body = '';
$req->content->on(read => sub { $body .= pop });
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0aContent");
$req->parse('-Type: text/');
$req->parse("plain\x0aContent-Length: 27\x0a\x0aH");
$req->parse("ello World!\n1234\nlalalala\n");
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.0', 'right version';
is $req->url,         '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, 27,           'right "Content-Length" value';
is $req->body, "Hello World!\n1234\nlalalala\n", 'right content';
is $body, "Hello World!\n1234\nlalalala\n", 'right content';

# Parse full HTTP 1.0 request (no scheme and empty elements in path)
$req = Mojo::Message::Request->new;
$req->parse('GET //foo/bar//baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: text/');
$req->parse("plain\x0d\x0aContent-Length: 27\x0d\x0a\x0d\x0aHell");
$req->parse("o World!\n1234\nlalalala\n");
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.0', 'right version';
is $req->url->host, 'foo',            'no host';
is $req->url->path, '/bar//baz.html', 'right path';
is $req->url, '//foo/bar//baz.html?foo=13#23', 'right URL';
is $req->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, 27,           'right "Content-Length" value';

# Parse full HTTP 1.0 request (behind reverse proxy)
$req = Mojo::Message::Request->new;
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: text/');
$req->parse("plain\x0d\x0aContent-Length: 27\x0d\x0a");
$req->parse("Host: mojolicio.us\x0d\x0a");
$req->parse("X-Forwarded-For: 192.168.2.1, 127.0.0.1\x0d\x0a\x0d\x0a");
$req->parse("Hello World!\n1234\nlalalala\n");
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.0', 'right version';
is $req->url,         '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->url->to_abs, 'http://mojolicio.us/foo/bar/baz.html?foo=13#23',
  'right absolute URL';
is $req->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, 27,           'right "Content-Length" value';

# Parse full HTTP 1.0 request with zero chunk
$req      = Mojo::Message::Request->new;
$finished = undef;
$req->on(finish => sub { $finished = shift->is_finished });
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: text/');
$req->parse("plain\x0d\x0aContent-Length: 27\x0d\x0a\x0d\x0aHell");
$req->parse("o World!\n123");
$req->parse('0');
$req->parse("\nlalalala\n");
ok $finished, 'finish event has been emitted';
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.0', 'right version';
is $req->url,         '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, 27,           'right "Content-Length" value';

# Parse full HTTP 1.0 request with UTF-8 form input
$req = Mojo::Message::Request->new;
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: application/');
$req->parse("x-www-form-urlencoded\x0d\x0aContent-Length: 14");
$req->parse("\x0d\x0a\x0d\x0a");
$req->parse('name=%E2%98%83');
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.0', 'right version';
is $req->url,         '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_type, 'application/x-www-form-urlencoded',
  'right "Content-Type" value';
is $req->headers->content_length, 14, 'right "Content-Length" value';
is $req->param('name'), '☃', 'right value';

# Parse HTTP 1.1 gzip compressed request (no decompression)
gzip \(my $uncompressed = 'abc' x 1000), \my $compressed;
$req = Mojo::Message::Request->new;
$req->parse("POST /foo HTTP/1.1\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a");
$req->parse("Content-Length: @{[length $compressed]}\x0d\x0a");
$req->parse("Content-Encoding: GZip\x0d\x0a\x0d\x0a");
ok $req->content->is_compressed, 'content is compressed';
$req->parse($compressed);
ok $req->content->is_compressed, 'content is still compressed';
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo', 'right URL';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, length($compressed),
  'right "Content-Length" value';
is $req->body, $compressed, 'right content';

# Parse HTTP 1.1 chunked request
$req = Mojo::Message::Request->new;
is $req->content->progress, 0, 'right progress';
$req->parse("POST /foo/bar/baz.html?foo=13#23 HTTP/1.1\x0d\x0a");
is $req->content->progress, 0, 'right progress';
$req->parse("Content-Type: text/plain\x0d\x0a");
$req->parse("Transfer-Encoding: chunked\x0d\x0a\x0d\x0a");
is $req->content->progress, 0, 'right progress';
$req->parse("4\x0d\x0a");
is $req->content->progress, 3, 'right progress';
$req->parse("abcd\x0d\x0a");
is $req->content->progress, 9, 'right progress';
$req->parse("9\x0d\x0a");
is $req->content->progress, 12, 'right progress';
$req->parse("abcdefghi\x0d\x0a");
is $req->content->progress, 23, 'right progress';
$req->parse("0\x0d\x0a\x0d\x0a");
is $req->content->progress, 28, 'right progress';
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_length, 13,           'right "Content-Length" value';
is $req->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $req->content->asset->size, 13, 'right size';
is $req->content->asset->slurp, 'abcdabcdefghi', 'right content';

# Parse HTTP 1.1 chunked request with callbacks
$req = Mojo::Message::Request->new;
my $progress = my $buffer = my $finish = '';
$req->on(
  progress => sub {
    my $self = shift;
    $progress ||= $self->url->path if $self->content->is_parsing_body;
  }
);
$req->content->unsubscribe('read')->on(read => sub { $buffer .= pop });
$req->on(finish => sub { $finish .= shift->url->fragment });
$req->parse("POST /foo/bar/baz.html?foo=13#23 HTTP/1.1\x0d\x0a");
is $progress, '', 'no progress';
$req->parse("Content-Type: text/plain\x0d\x0a");
is $progress, '', 'no progress';
$req->parse("Transfer-Encoding: chunked\x0d\x0a\x0d\x0a");
is $progress, '/foo/bar/baz.html', 'made progress';
$req->parse("4\x0d\x0a");
$req->parse("abcd\x0d\x0a");
$req->parse("9\x0d\x0a");
$req->parse("abcdefghi\x0d\x0a");
is $finish, '', 'not finished yet';
$req->parse("0\x0d\x0a\x0d\x0a");
is $finish, '23', 'finished';
is $progress, '/foo/bar/baz.html', 'made progress';
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_length, 13,           'right "Content-Length" value';
is $req->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $buffer, 'abcdabcdefghi', 'right content';

# Parse HTTP 1.1 "application/x-www-form-urlencoded"
$req = Mojo::Message::Request->new;
$req->parse("POST /foo/bar/baz.html?foo=13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 25\x0d\x0a");
$req->parse("Content-Type: application/x-www-form-urlencoded\x0d\x0a");
$req->parse("\x0d\x0afoo=bar&+tset=23+&foo=bar");
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_type, 'application/x-www-form-urlencoded',
  'right "Content-Type" value';
is $req->content->asset->size, 25, 'right size';
is $req->content->asset->slurp, 'foo=bar&+tset=23+&foo=bar', 'right content';
is_deeply $req->body_params->to_hash->{foo}, [qw(bar bar)], 'right values';
is $req->body_params->to_hash->{' tset'}, '23 ', 'right value';
is $req->body_params, 'foo=bar&+tset=23+&foo=bar', 'right parameters';
is_deeply $req->params->to_hash->{foo}, [qw(bar bar 13)], 'right values';
is_deeply $req->every_param('foo'),     [qw(bar bar 13)], 'right values';
is $req->param(' tset'), '23 ', 'right value';
$req->param('set', 'single');
is $req->param('set'), 'single', 'setting single param works';
$req->param('multi', 1, 2, 3);
is_deeply $req->every_param('multi'), [qw(1 2 3)],
  'setting multiple value param works';
is $req->param('test23'), undef, 'no value';

# Parse HTTP 1.1 chunked request with trailing headers
$req = Mojo::Message::Request->new;
$req->parse("POST /foo/bar/baz.html?foo=13&bar=23#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a");
$req->parse("Transfer-Encoding: whatever\x0d\x0a");
$req->parse("Trailer: X-Trailer1; X-Trailer2\x0d\x0a\x0d\x0a");
$req->parse("4\x0d\x0a");
$req->parse("abcd\x0d\x0a");
$req->parse("9\x0d\x0a");
$req->parse("abcdefghi\x0d\x0a");
$req->parse("0\x0d\x0a");
$req->parse("X-Trailer1: test\x0d\x0a");
$req->parse("X-Trailer2: 123\x0d\x0a\x0d\x0a");
ok $req->is_finished,  'request is finished';
is $req->method,       'POST', 'right method';
is $req->version,      '1.1', 'right version';
is $req->url,          '/foo/bar/baz.html?foo=13&bar=23#23', 'right URL';
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
ok $req->is_finished,  'request is finished';
is $req->method,       'POST', 'right method';
is $req->version,      '1.1', 'right version';
is $req->url,          '/foo/bar/baz.html?foo=13&bar=23#23', 'right URL';
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
ok $req->is_finished,  'request is finished';
is $req->method,       'POST', 'right method';
is $req->version,      '1.1', 'right version';
is $req->url,          '/foo/bar/baz.html?foo=13&bar=23#23', 'right URL';
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
ok $req->is_finished,  'request is finished';
is $req->method,       'POST', 'right method';
is $req->version,      '1.1', 'right version';
is $req->url,          '/foo/bar/baz.html?foo=13&bar=23#23', 'right URL';
is $req->query_params, 'foo=13&bar=23', 'right parameters';
is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $req->headers->header('X-Trailer1'), 'test', 'right "X-Trailer1" value';
is $req->headers->header('X-Trailer2'), '123',  'right "X-Trailer2" value';
is $req->headers->content_length, 13, 'right "Content-Length" value';
is $req->content->asset->size, 13, 'right size';
is $req->content->asset->slurp, 'abcdabcdefghi', 'right content';

# Parse HTTP 1.1 multipart request
$req = Mojo::Message::Request->new;
is $req->content->progress, 0, 'right progress';
$req->parse("GET /foo/bar/baz.html?foo13#23 HTTP/1.1\x0d\x0a");
is $req->content->progress, 0, 'right progress';
$req->parse("Content-Length: 416\x0d\x0a");
$req->parse('Content-Type: multipart/form-data; bo');
is $req->content->progress, 0, 'right progress';
$req->parse("undary=----------0xKhTmLbOuNdArY\x0d\x0a\x0d\x0a");
is $req->content->progress, 0, 'right progress';
$req->parse("\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
is $req->content->progress, 31, 'right progress';
$req->parse("Content-Disposition: form-data; name=\"text1\"\x0d\x0a");
$req->parse("\x0d\x0ahallo welt test123\n");
$req->parse("\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$req->parse("Content-Disposition: form-data; name=\"text2\"\x0d\x0a");
$req->parse("\x0d\x0a\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$req->parse('Content-Disposition: form-data;name="upload";file');
$req->parse("name=\"hello.pl\"\x0d\x0a");
$req->parse("Content-Type: application/octet-stream\x0d\x0a\x0d\x0a");
$req->parse("#!/usr/bin/perl\n\n");
$req->parse("use strict;\n");
$req->parse("use warnings;\n\n");
$req->parse("print \"Hello World :)\\n\"\n");
$req->parse("\x0d\x0a------------0xKhTmLbOuNdArY--");
is $req->content->progress, 416, 'right progress';
ok $req->is_finished, 'request is finished';
ok $req->content->is_multipart, 'multipart content';
is $req->method,       'GET',                        'right method';
is $req->version,      '1.1',                        'right version';
is $req->url,          '/foo/bar/baz.html?foo13#23', 'right URL';
is $req->query_params, 'foo13',                      'right parameters';
is $req->headers->content_type,
  'multipart/form-data; boundary=----------0xKhTmLbOuNdArY',
  'right "Content-Type" value';
is $req->headers->content_length, 416, 'right "Content-Length" value';
isa_ok $req->content->parts->[0], 'Mojo::Content::Single', 'right part';
isa_ok $req->content->parts->[1], 'Mojo::Content::Single', 'right part';
isa_ok $req->content->parts->[2], 'Mojo::Content::Single', 'right part';
ok !$req->content->parts->[0]->asset->is_file, 'stored in memory';
is $req->content->parts->[0]->asset->slurp, "hallo welt test123\n",
  'right content';
is $req->body_params->to_hash->{text1}, "hallo welt test123\n", 'right value';
is $req->body_params->to_hash->{text2}, '', 'right value';
is $req->upload('upload')->filename,  'hello.pl',            'right filename';
isa_ok $req->upload('upload')->asset, 'Mojo::Asset::Memory', 'right file';
is $req->upload('upload')->asset->size, 69, 'right size';
my $file = catfile(tempdir(CLEANUP => 1), ("MOJO_TMP." . time . ".txt"));
isa_ok $req->upload('upload')->move_to($file), 'Mojo::Upload', 'moved file';
ok unlink($file), 'unlinked file';
is $req->content->boundary, '----------0xKhTmLbOuNdArY', 'right boundary';

# Parse HTTP 1.1 multipart request (too big for memory)
$req = Mojo::Message::Request->new;
$req->content->on(
  body => sub {
    my $single = shift;
    $single->on(
      upgrade => sub {
        my ($single, $multi) = @_;
        $multi->on(
          part => sub {
            my ($multi, $part) = @_;
            $part->asset->max_memory_size(5);
          }
        );
      }
    );
  }
);
$req->parse("GET /foo/bar/baz.html?foo13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 418\x0d\x0a");
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
ok $req->is_finished, 'request is finished';
ok $req->content->is_multipart, 'multipart content';
is $req->method,       'GET',                        'right method';
is $req->version,      '1.1',                        'right version';
is $req->url,          '/foo/bar/baz.html?foo13#23', 'right URL';
is $req->query_params, 'foo13',                      'right parameters';
is $req->headers->content_type,
  'multipart/form-data; boundary=----------0xKhTmLbOuNdArY',
  'right "Content-Type" value';
is $req->headers->content_length, 418, 'right "Content-Length" value';
isa_ok $req->content->parts->[0], 'Mojo::Content::Single', 'right part';
isa_ok $req->content->parts->[1], 'Mojo::Content::Single', 'right part';
isa_ok $req->content->parts->[2], 'Mojo::Content::Single', 'right part';
ok $req->content->parts->[0]->asset->is_file, 'stored in file';
is $req->content->parts->[0]->asset->slurp,   "hallo welt test123\n",
  'right content';
is $req->body_params->to_hash->{text1}, "hallo welt test123\n", 'right value';
is $req->body_params->to_hash->{text2}, '', 'right value';
is $req->upload('upload')->filename,  'hello.pl',          'right filename';
isa_ok $req->upload('upload')->asset, 'Mojo::Asset::File', 'right file';
is $req->upload('upload')->asset->size, 69, 'right size';

# Parse HTTP 1.1 multipart request (with callbacks and stream)
$req = Mojo::Message::Request->new;
my $stream = '';
$req->content->on(
  body => sub {
    my $single = shift;
    $single->on(
      upgrade => sub {
        my ($single, $multi) = @_;
        $multi->on(
          part => sub {
            my ($multi, $part) = @_;
            $part->on(
              body => sub {
                my $part = shift;
                return
                  unless $part->headers->content_disposition =~ /hello\.pl/;
                $part->on(
                  read => sub {
                    my ($part, $chunk) = @_;
                    $stream .= $chunk;
                  }
                );
              }
            );
          }
        );
      }
    );
  }
);
$req->parse("GET /foo/bar/baz.html?foo13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 418\x0d\x0a");
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
is $stream, '', 'no content';
$req->parse("#!/usr/bin/perl\n\n");
is $stream, '', 'no content';
$req->parse("use strict;\n");
is $stream, '', 'no content';
$req->parse("use warnings;\n\n");
is $stream, '#!/usr/bin/', 'right content';
$req->parse("print \"Hello World :)\\n\"\n");
is $stream, "#!/usr/bin/perl\n\nuse strict;\nuse war", 'right content';
$req->parse("\x0d\x0a------------0xKhTmLbOuNdArY--");
ok $req->is_finished, 'request is finished';
ok $req->content->is_multipart, 'multipart content';
is $req->method,       'GET',                        'right method';
is $req->version,      '1.1',                        'right version';
is $req->url,          '/foo/bar/baz.html?foo13#23', 'right URL';
is $req->query_params, 'foo13',                      'right parameters';
is $req->headers->content_type,
  'multipart/form-data; boundary=----------0xKhTmLbOuNdArY',
  'right "Content-Type" value';
is $req->headers->content_length, 418, 'right "Content-Length" value';
isa_ok $req->content->parts->[0], 'Mojo::Content::Single', 'right part';
isa_ok $req->content->parts->[1], 'Mojo::Content::Single', 'right part';
isa_ok $req->content->parts->[2], 'Mojo::Content::Single', 'right part';
is $req->content->parts->[0]->asset->slurp, "hallo welt test123\n",
  'right content';
is $req->body_params->to_hash->{text1}, "hallo welt test123\n", 'right value';
is $req->body_params->to_hash->{text2}, '', 'right value';
is $stream,
    "#!/usr/bin/perl\n\n"
  . "use strict;\n"
  . "use warnings;\n\n"
  . "print \"Hello World :)\\n\"\n", 'right content';

# Parse HTTP 1.1 multipart request (without upgrade)
$req = Mojo::Message::Request->new;
$req->content->auto_upgrade(0);
$req->parse("GET /foo/bar/baz.html?foo13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 418\x0d\x0a");
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
ok $req->is_finished, 'request is finished';
ok !$req->content->is_multipart, 'no multipart content';
is $req->method,       'GET',                        'right method';
is $req->version,      '1.1',                        'right version';
is $req->url,          '/foo/bar/baz.html?foo13#23', 'right URL';
is $req->query_params, 'foo13',                      'right parameters';
is $req->headers->content_type,
  'multipart/form-data; boundary=----------0xKhTmLbOuNdArY',
  'right "Content-Type" value';
is $req->headers->content_length, 418, 'right "Content-Length" value';
isa_ok $req->content, 'Mojo::Content::Single', 'right content';
like $req->content->asset->slurp, qr/------------0xKhTmLbOuNdArY--$/,
  'right content';

# Parse HTTP 1.1 multipart request with "0" filename
$req = Mojo::Message::Request->new;
$req->parse("GET /foo/bar/baz.html?foo13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 410\x0d\x0a");
$req->parse('Content-Type: multipart/form-data; bo');
$req->parse("undary=----------0xKhTmLbOuNdArY\x0d\x0a\x0d\x0a");
$req->parse("\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$req->parse("Content-Disposition: form-data; name=\"text1\"\x0d\x0a");
$req->parse("\x0d\x0ahallo welt test123\n");
$req->parse("\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$req->parse("Content-Disposition: form-data; name=\"text2\"\x0d\x0a");
$req->parse("\x0d\x0a\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a");
$req->parse('Content-Disposition: form-data; name="upload"; file');
$req->parse("name=\"0\"\x0d\x0a");
$req->parse("Content-Type: application/octet-stream\x0d\x0a\x0d\x0a");
$req->parse("#!/usr/bin/perl\n\n");
$req->parse("use strict;\n");
$req->parse("use warnings;\n\n");
$req->parse("print \"Hello World :)\\n\"\n");
$req->parse("\x0d\x0a------------0xKhTmLbOuNdArY--");
ok $req->is_finished, 'request is finished';
ok $req->content->is_multipart, 'no multipart content';
is $req->method,       'GET',                        'right method';
is $req->version,      '1.1',                        'right version';
is $req->url,          '/foo/bar/baz.html?foo13#23', 'right URL';
is $req->query_params, 'foo13',                      'right parameters';
is $req->headers->content_type,
  'multipart/form-data; boundary=----------0xKhTmLbOuNdArY',
  'right "Content-Type" value';
is $req->headers->content_length, 410, 'right "Content-Length" value';
isa_ok $req->content->parts->[0], 'Mojo::Content::Single', 'right part';
isa_ok $req->content->parts->[1], 'Mojo::Content::Single', 'right part';
isa_ok $req->content->parts->[2], 'Mojo::Content::Single', 'right part';
is $req->content->parts->[0]->asset->slurp, "hallo welt test123\n",
  'right content';
is $req->body_params->to_hash->{text1}, "hallo welt test123\n", 'right value';
is $req->body_params->to_hash->{text2}, '', 'right value';
is $req->body_params->to_hash->{upload}, undef, 'not a body parameter';
is $req->upload('upload')->filename, '0', 'right filename';
isa_ok $req->upload('upload')->asset, 'Mojo::Asset::Memory', 'right file';
is $req->upload('upload')->asset->size, 69, 'right size';

# Parse full HTTP 1.1 proxy request with basic authentication
$req = Mojo::Message::Request->new;
$req->parse("GET http://127.0.0.1/foo/bar HTTP/1.1\x0d\x0a");
$req->parse("Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==\x0d\x0a");
$req->parse("Host: 127.0.0.1\x0d\x0a");
$req->parse("Proxy-Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==\x0d\x0a");
$req->parse("Content-Length: 13\x0d\x0a\x0d\x0a");
$req->parse("Hello World!\n");
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url->base, 'http://Aladdin:open%20sesame@127.0.0.1', 'right base URL';
is $req->url->base->userinfo, 'Aladdin:open sesame', 'right base userinfo';
is $req->url, 'http://127.0.0.1/foo/bar', 'right URL';
is $req->proxy->userinfo, 'Aladdin:open sesame', 'right proxy userinfo';

# Parse full HTTP 1.1 proxy connect request with basic authentication
$req = Mojo::Message::Request->new;
$req->parse("CONNECT 127.0.0.1:3000 HTTP/1.1\x0d\x0a");
$req->parse("Host: 127.0.0.1:3000\x0d\x0a");
$req->parse("Proxy-Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==\x0d\x0a");
$req->parse("Content-Length: 0\x0d\x0a\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->method,      'CONNECT', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '//127.0.0.1:3000', 'right URL';
is $req->url->host,       '127.0.0.1',           'right host';
is $req->url->port,       '3000',                'right port';
is $req->proxy->userinfo, 'Aladdin:open sesame', 'right proxy userinfo';

# Build minimal HTTP 1.1 request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/', 'right URL';
is $req->url->to_abs,   'http://127.0.0.1/', 'right absolute URL';
is $req->headers->host, '127.0.0.1',         'right "Host" value';

# Build HTTP 1.1 start-line and header
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';

# Build HTTP 1.1 start-line and header (with clone)
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
my $clone = $req->clone;
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';
$clone = Mojo::Message::Request->new->parse($clone->to_string);
ok $clone->is_finished, 'request is finished';
is $clone->method,      'GET', 'right method';
is $clone->version,     '1.1', 'right version';
is $clone->url,         '/foo/bar', 'right URL';
is $clone->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $clone->headers->expect, '100-continue',             'right "Expect" value';
is $clone->headers->host,   '127.0.0.1',                'right "Host" value';

# Build HTTP 1.1 start-line and header (with clone and changes)
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
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';
$clone = Mojo::Message::Request->new->parse($clone->to_string);
ok $clone->is_finished, 'request is finished';
is $clone->method,      'POST', 'right method';
is $clone->version,     '1.2', 'right version';
is $clone->url,         '/foo/bar/baz', 'right URL';
is $clone->url->to_abs, 'http://127.0.0.1/foo/bar/baz', 'right absolute URL';
is $clone->headers->expect, 'nothing',   'right "Expect" value';
is $clone->headers->host,   '127.0.0.1', 'right "Host" value';

# Build full HTTP 1.1 request
$req      = Mojo::Message::Request->new;
$finished = undef;
$req->on(finish => sub { $finished = shift->is_finished });
$req->method('get');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';
is $req->headers->content_length, '13', 'right "Content-Length" value';
is $req->body, "Hello World!\n", 'right content';
ok $finished, 'finish event has been emitted';
ok $req->is_finished, 'request is finished';

# Build HTTP 1.1 request parts with progress
$req = Mojo::Message::Request->new;
my $state;
$finished = undef;
$progress = 0;
$req->on(finish => sub { $finished = shift->is_finished });
$req->on(
  progress => sub {
    my ($req, $part, $offset) = @_;
    $state = $part;
    $progress += $offset;
  }
);
$req->method('get');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
ok !$state,    'no state';
ok !$progress, 'no progress';
ok !$finished, 'not finished';
ok $req->build_start_line, 'built start-line';
is $state, 'start_line', 'made progress on start_line';
ok $progress, 'made progress';
$progress = 0;
ok !$finished, 'not finished';
ok $req->build_headers, 'built headers';
is $state, 'headers', 'made progress on headers';
ok $progress, 'made progress';
$progress = 0;
ok !$finished, 'not finished';
ok $req->build_body, 'built body';
is $state, 'body', 'made progress on headers';
ok $progress, 'made progress';
ok $finished, 'finished';
is $req->build_headers, $req->content->build_headers, 'headers are equal';
is $req->build_body,    $req->content->build_body,    'body is equal';

# Build full HTTP 1.1 request (with clone)
$req      = Mojo::Message::Request->new;
$finished = undef;
$req->on(finish => sub { $finished = shift->is_finished });
$req->method('get');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
$clone = $req->clone;
$req   = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';
is $req->headers->content_length, '13', 'right "Content-Length" value';
is $req->body, "Hello World!\n", 'right content';
ok $finished, 'finish event has been emitted';
ok $req->is_finished, 'request is finished';
$finished = undef;
$clone    = Mojo::Message::Request->new->parse($clone->to_string);
ok $clone->is_finished, 'request is finished';
is $clone->method,      'GET', 'right method';
is $clone->version,     '1.1', 'right version';
is $clone->url,         '/foo/bar', 'right URL';
is $clone->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $clone->headers->expect, '100-continue',             'right "Expect" value';
is $clone->headers->host,   '127.0.0.1',                'right "Host" value';
is $clone->headers->content_length, '13', 'right "Content-Length" value';
is $clone->body, "Hello World!\n", 'right content';
ok !$finished, 'finish event has been emitted';
ok $clone->is_finished, 'request is finished';

# Build full HTTP 1.1 request (roundtrip)
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';
is $req->headers->content_length, '13', 'right "Content-Length" value';
is $req->body, "Hello World!\n", 'right content';
my $req2 = Mojo::Message::Request->new->parse($req->to_string);
is $req->content->leftovers, '', 'no leftovers';
is $req->error, undef, 'no error';
is $req2->content->leftovers, '', 'no leftovers';
is $req2->error, undef, 'no error';
ok $req2->is_finished, 'request is finished';
is $req2->method,      'GET', 'right method';
is $req2->version,     '1.1', 'right version';
is $req2->url,         '/foo/bar', 'right URL';
is $req2->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req2->headers->expect, '100-continue',             'right "Expect" value';
is $req2->headers->host,   '127.0.0.1',                'right "Host" value';
is $req->headers->content_length, '13', 'right "Content-Length" value';
is $req->body, "Hello World!\n", 'right content';

# Build HTTP 1.1 request body
$req      = Mojo::Message::Request->new;
$finished = undef;
$req->on(finish => sub { $finished = shift->is_finished });
$req->method('get');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
my $i = 0;
while (my $chunk = $req->get_body_chunk($i)) { $i += length $chunk }
ok $finished, 'finish event has been emitted';
ok $req->is_finished, 'request is finished';

# Build WebSocket handshake request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://example.com/demo');
$req->headers->host('example.com');
$req->headers->connection('Upgrade');
$req->headers->sec_websocket_accept('abcdef=');
$req->headers->sec_websocket_protocol('sample');
$req->headers->upgrade('websocket');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/demo', 'right URL';
is $req->url->to_abs, 'http://example.com/demo', 'right absolute URL';
is $req->headers->connection, 'Upgrade',     'right "Connection" value';
is $req->headers->upgrade,    'websocket',   'right "Upgrade" value';
is $req->headers->host,       'example.com', 'right "Host" value';
is $req->headers->content_length, 0, 'right "Content-Length" value';
is $req->headers->sec_websocket_accept, 'abcdef=',
  'right "Sec-WebSocket-Key" value';
is $req->headers->sec_websocket_protocol, 'sample',
  'right "Sec-WebSocket-Protocol" value';
is $req->body, '', 'no content';
ok $finished, 'finish event has been emitted';
ok $req->is_finished, 'request is finished';

# Build WebSocket handshake request (with clone)
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://example.com/demo');
$req->headers->host('example.com');
$req->headers->connection('Upgrade');
$req->headers->sec_websocket_accept('abcdef=');
$req->headers->sec_websocket_protocol('sample');
$req->headers->upgrade('websocket');
$clone = $req->clone;
$req   = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/demo', 'right URL';
is $req->url->to_abs, 'http://example.com/demo', 'right absolute URL';
is $req->headers->connection, 'Upgrade',     'right "Connection" value';
is $req->headers->upgrade,    'websocket',   'right "Upgrade" value';
is $req->headers->host,       'example.com', 'right "Host" value';
is $req->headers->content_length, 0, 'right "Content-Length" value';
is $req->headers->sec_websocket_accept, 'abcdef=',
  'right "Sec-WebSocket-Key" value';
is $req->headers->sec_websocket_protocol, 'sample',
  'right "Sec-WebSocket-Protocol" value';
is $req->body, '', 'no content';
ok $req->is_finished, 'request is finished';
$clone = Mojo::Message::Request->new->parse($clone->to_string);
ok $clone->is_finished, 'request is finished';
is $clone->method,      'GET', 'right method';
is $clone->version,     '1.1', 'right version';
is $clone->url,         '/demo', 'right URL';
is $clone->url->to_abs, 'http://example.com/demo', 'right absolute URL';
is $clone->headers->connection, 'Upgrade',     'right "Connection" value';
is $clone->headers->upgrade,    'websocket',   'right "Upgrade" value';
is $clone->headers->host,       'example.com', 'right "Host" value';
is $clone->headers->content_length, 0, 'right "Content-Length" value';
is $clone->headers->sec_websocket_accept, 'abcdef=',
  'right "Sec-WebSocket-Key" value';
is $clone->headers->sec_websocket_protocol, 'sample',
  'right "Sec-WebSocket-Protocol" value';
is $clone->body, '', 'no content';
ok $clone->is_finished, 'request is finished';

# Build WebSocket handshake proxy request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://example.com/demo');
$req->headers->host('example.com');
$req->headers->connection('Upgrade');
$req->headers->sec_websocket_accept('abcdef=');
$req->headers->sec_websocket_protocol('sample');
$req->headers->upgrade('websocket');
$req->proxy('http://127.0.0.2:8080');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/demo', 'right URL';
is $req->url->to_abs, 'http://example.com/demo', 'right absolute URL';
is $req->headers->connection, 'Upgrade',     'right "Connection" value';
is $req->headers->upgrade,    'websocket',   'right "Upgrade" value';
is $req->headers->host,       'example.com', 'right "Host" value';
is $req->headers->content_length, 0, 'right "Content-Length" value';
is $req->headers->sec_websocket_accept, 'abcdef=',
  'right "Sec-WebSocket-Key" value';
is $req->headers->sec_websocket_protocol, 'sample',
  'right "Sec-WebSocket-Protocol" value';
is $req->body, '', 'no content';
ok $finished, 'finish event has been emitted';
ok $req->is_finished, 'request is finished';

# Build full HTTP 1.1 proxy request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
$req->proxy('http://127.0.0.2:8080');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         'http://127.0.0.1/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';
is $req->headers->content_length, '13', 'right "Content-Length" value';
is $req->body, "Hello World!\n", 'right content';

# Build full HTTP 1.1 proxy request (HTTPS)
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('https://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
$req->proxy('http://127.0.0.2:8080');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo/bar', 'right URL';
is $req->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->expect, '100-continue',             'right "Expect" value';
is $req->headers->host,   '127.0.0.1',                'right "Host" value';
is $req->headers->content_length, '13', 'right "Content-Length" value';
is $req->body, "Hello World!\n", 'right content';

# Build full HTTP 1.1 proxy request with basic authentication
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://Aladdin:open%20sesame@127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
$req->proxy('http://Aladdin:open%20sesame@127.0.0.2:8080');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         'http://127.0.0.1/foo/bar', 'right URL';
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

# Build full HTTP 1.1 proxy request with basic authentication (and clone)
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://Aladdin:open%20sesame@127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
$req->proxy('http://Aladdin:open%20sesame@127.0.0.2:8080');
$clone = $req->clone;
$req   = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         'http://127.0.0.1/foo/bar', 'right URL';
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
ok $clone->is_finished, 'request is finished';
is $clone->method,      'GET', 'right method';
is $clone->version,     '1.1', 'right version';
is $clone->url,         'http://127.0.0.1/foo/bar', 'right URL';
is $clone->url->to_abs,     'http://127.0.0.1/foo/bar', 'right absolute URL';
is $clone->proxy->userinfo, 'Aladdin:open sesame',      'right proxy userinfo';
is $clone->headers->authorization, 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  'right "Authorization" value';
is $clone->headers->expect, '100-continue', 'right "Expect" value';
is $clone->headers->host,   '127.0.0.1',    'right "Host" value';
is $clone->headers->proxy_authorization, 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  'right "Proxy-Authorization" value';
is $clone->headers->content_length, '13', 'right "Content-Length" value';
is $clone->body, "Hello World!\n", 'right content';

# Build full HTTP 1.1 proxy connect request with basic authentication
$req = Mojo::Message::Request->new;
$req->method('CONNECT');
$req->url->parse('http://Aladdin:open%20sesame@bücher.ch:3000/foo/bar');
$req->proxy('http://Aladdin:open%20sesame@127.0.0.2:8080');
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'CONNECT', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '//xn--bcher-kva.ch:3000', 'right URL';
is $req->url->host,   'xn--bcher-kva.ch',             'right host';
is $req->url->port,   '3000',                         'right port';
is $req->url->to_abs, 'http://xn--bcher-kva.ch:3000', 'right absolute URL';
is $req->proxy->userinfo, 'Aladdin:open sesame', 'right proxy userinfo';
is $req->headers->authorization, 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  'right "Authorization" value';
is $req->headers->host, 'xn--bcher-kva.ch:3000', 'right "Host" value';
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
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo/bar', 'right URL';
is $req->url->to_abs, 'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->host, '127.0.0.1', 'right "Host" value';
is $req->headers->content_length, '106', 'right "Content-Length" value';
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
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo/bar', 'right URL';
is $req->url->to_abs, 'http://127.0.0.1/foo/bar', 'right absolute URL';
is $req->headers->host, '127.0.0.1', 'right "Host" value';
is $req->headers->content_length, '106', 'right "Content-Length" value';
is $req->headers->content_type, 'multipart/mixed; boundary=7am1X',
  'right "Content-Type" value';
is $req->content->parts->[0]->asset->slurp, 'Hallo Welt lalalala!',
  'right content';
is $req->content->parts->[1]->headers->content_type, 'text/plain',
  'right "Content-Type" value';
is $req->content->parts->[1]->asset->slurp, "lala\nfoobar\nperl rocks\n",
  'right content';
$clone = Mojo::Message::Request->new->parse($clone->to_string);
ok $clone->is_finished, 'request is finished';
is $clone->method,      'GET', 'right method';
is $clone->version,     '1.1', 'right version';
is $clone->url,         '/foo/bar', 'right URL';
is $clone->url->to_abs, 'http://127.0.0.1/foo/bar', 'right absolute URL';
is $clone->headers->host, '127.0.0.1', 'right "Host" value';
is $clone->headers->content_length, '106', 'right "Content-Length" value';
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
my $counter;
$req->on(progress => sub { $counter++ });
$req->content->write_chunk(
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
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo/bar', 'right URL';
is $req->url->to_abs, 'http://127.0.0.1:8080/foo/bar', 'right absolute URL';
is $req->headers->host, '127.0.0.1:8080', 'right "Host" value';
is $req->headers->transfer_encoding, undef, 'no "Transfer-Encoding" value';
is $req->body, "hello world!hello world2!\n\n", 'right content';
ok $counter, 'right counter';

# Build HTTP 1.1 chunked request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1');
$req->content->write_chunk('hello world!');
$req->content->write_chunk("hello world2!\n\n");
$req->content->write_chunk('');
is $req->clone, undef, 'dynamic requests cannot be cloned';
$req = Mojo::Message::Request->new->parse($req->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/', 'right URL';
is $req->url->to_abs, 'http://127.0.0.1/', 'right absolute URL';
is $req->headers->host, '127.0.0.1', 'right "Host" value';
is $req->headers->transfer_encoding, undef, 'no "Transfer-Encoding" value';
is $req->body, "hello world!hello world2!\n\n", 'right content';

# Build full HTTP 1.1 request with cookies
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar?0');
$req->headers->expect('100-continue');
$req->cookies({name => 'foo', value => 'bar'},
  {name => 'bar', value => 'baz'});
$req->cookies(Mojo::Cookie::Request->new(name => 'baz', value => 'yada'));
$req->body("Hello World!\n");
ok !!$req->to_string, 'message built';
$req2 = Mojo::Message::Request->new;
$req2->parse($req->to_string);
ok $req2->is_finished, 'request is finished';
is $req2->method,      'GET', 'right method';
is $req2->version,     '1.1', 'right version';
is $req2->headers->expect, '100-continue', 'right "Expect" value';
is $req2->headers->host,   '127.0.0.1',    'right "Host" value';
is $req2->headers->content_length, 13, 'right "Content-Length" value';
is $req2->headers->cookie, 'foo=bar; bar=baz; baz=yada',
  'right "Cookie" value';
is $req2->url, '/foo/bar?0', 'right URL';
is $req2->url->to_abs, 'http://127.0.0.1/foo/bar?0', 'right absolute URL';
ok defined $req2->cookie('foo'),   'cookie "foo" exists';
ok defined $req2->cookie('bar'),   'cookie "bar" exists';
ok defined $req2->cookie('baz'),   'cookie "baz" exists';
ok !defined $req2->cookie('yada'), 'cookie "yada" does not exist';
is $req2->cookie('foo')->value, 'bar',  'right value';
is $req2->cookie('bar')->value, 'baz',  'right value';
is $req2->cookie('baz')->value, 'yada', 'right value';
is $req2->body, "Hello World!\n", 'right content';

# Build HTTP 1.1 request with cookies sharing the same name
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->cookies(
  {name => 'foo', value => 'bar'},
  {name => 'foo', value => 'baz'},
  {name => 'foo', value => 'yada'},
  {name => 'bar', value => 'foo'}
);
$req2 = Mojo::Message::Request->new;
$req2->parse($req->to_string);
ok $req2->is_finished, 'request is finished';
is $req2->method,      'GET', 'right method';
is $req2->version,     '1.1', 'right version';
is $req2->headers->host, '127.0.0.1', 'right "Host" value';
is $req2->headers->cookie, 'foo=bar; foo=baz; foo=yada; bar=foo',
  'right "Cookie" value';
is $req2->url, '/foo/bar', 'right URL';
is $req2->url->to_abs, 'http://127.0.0.1/foo/bar', 'right absolute URL';
is_deeply [map { $_->value } @{$req2->every_cookie('foo')}],
  [qw(bar baz yada)], 'right values';
is_deeply [map { $_->value } @{$req2->every_cookie('bar')}], ['foo'],
  'right values';
is_deeply [map { $_->value } $req2->cookie([qw(foo bar)])], [qw(yada foo)],
  'right values';

# Parse full HTTP 1.0 request with cookies and progress callback
$req     = Mojo::Message::Request->new;
$counter = 0;
$req->on(progress => sub { $counter++ });
is $counter, 0, 'right count';
ok !$req->content->is_parsing_body, 'is not parsing body';
ok !$req->is_finished, 'request is not finished';
$req->parse('GET /foo/bar/baz.html?fo');
is $counter, 1, 'right count';
ok !$req->content->is_parsing_body, 'is not parsing body';
ok !$req->is_finished, 'request is not finished';
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
is $counter, 2, 'right count';
ok !$req->content->is_parsing_body, 'is not parsing body';
ok !$req->is_finished, 'request is not finished';
$req->parse('-Type: text/');
is $counter, 3, 'right count';
ok !$req->content->is_parsing_body, 'is not parsing body';
ok !$req->is_finished, 'request is not finished';
$req->parse("plain\x0d\x0a");
is $counter, 4, 'right count';
ok !$req->content->is_parsing_body, 'is not parsing body';
ok !$req->is_finished, 'request is not finished';
$req->parse('Cookie: foo=bar; bar=baz');
is $counter, 5, 'right count';
ok !$req->content->is_parsing_body, 'is not parsing body';
ok !$req->is_finished, 'request is not finished';
$req->parse("\x0d\x0a");
is $counter, 6, 'right count';
ok !$req->content->is_parsing_body, 'is not parsing body';
ok !$req->is_finished, 'request is not finished';
$req->parse("Content-Length: 27\x0d\x0a\x0d\x0aHell");
is $counter, 7, 'right count';
ok $req->content->is_parsing_body, 'is parsing body';
ok !$req->is_finished, 'request is not finished';
$req->parse("o World!\n1234\nlalalala\n");
is $counter, 8, 'right count';
ok !$req->content->is_parsing_body, 'is not parsing body';
ok $req->is_finished, 'request is finished';
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.0', 'right version';
is $req->url,         '/foo/bar/baz.html?foo=13#23', 'right URL';
is $req->headers->content_type,   'text/plain', 'right "Content-Type" value';
is $req->headers->content_length, 27,           'right "Content-Length" value';
my $cookies = $req->cookies;
is $cookies->[0]->name,  'foo', 'right name';
is $cookies->[0]->value, 'bar', 'right value';
is $cookies->[1]->name,  'bar', 'right name';
is $cookies->[1]->value, 'baz', 'right value';

# Parse and clone multipart/form-data request (changing size)
$req = Mojo::Message::Request->new;
$req->parse("POST /example/testform_handler HTTP/1.1\x0d\x0a");
$req->parse("User-Agent: Mozilla/5.0\x0d\x0a");
$req->parse('Content-Type: multipart/form-data; ');
$req->parse("boundary=----WebKitFormBoundaryi5BnD9J9zoTMiSuP\x0d\x0a");
$req->parse("Content-Length: 318\x0d\x0aConnection: keep-alive\x0d\x0a");
$req->parse("Host: 127.0.0.1:3000\x0d\x0a\x0d\x0a");
$req->parse("------WebKitFormBoundaryi5BnD9J9zoTMiSuP\x0d\x0a");
$req->parse("Content-Disposition: form-data; name=\"Vorname\"\x0a");
$req->parse("\x0d\x0aT\x0d\x0a------WebKitFormBoundaryi5BnD9J9zoTMiSuP\x0d");
$req->parse("\x0aContent-Disposition: form-data; name=\"Zuname\"\x0a");
$req->parse("\x0d\x0a\x0d\x0a------WebKitFormBoundaryi5BnD9J9zoTMiSuP\x0d");
$req->parse("\x0aContent-Disposition: form-data; name=\"Text\"\x0a");
$req->parse("\x0d\x0a\x0d\x0a------WebKitFormBoundaryi5BnD9J9zoTMiSuP--");
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/example/testform_handler', 'right URL';
is $req->headers->content_length, 318, 'right "Content-Length" value';
is $req->param('Vorname'), 'T', 'right value';
is $req->param('Zuname'),  '',  'right value';
is $req->param('Text'),    '',  'right value';
is $req->content->parts->[0]->asset->slurp, 'T', 'right content';
is $req->content->leftovers, '', 'no leftovers';
$req = Mojo::Message::Request->new->parse($req->clone->to_string);
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/example/testform_handler', 'right URL';
is $req->headers->content_length, 323, 'right "Content-Length" value';
is $req->param('Vorname'), 'T', 'right value';
is $req->param('Zuname'),  '',  'right value';
is $req->param('Text'),    '',  'right value';
is $req->content->parts->[0]->asset->slurp, 'T', 'right content';
is $req->content->leftovers, '', 'no leftovers';
is $req->content->get_body_chunk(322), "\x0a",      'right chunk';
is $req->content->get_body_chunk(321), "\x0d\x0a",  'right chunk';
is $req->content->get_body_chunk(320), "-\x0d\x0a", 'right chunk';

# Parse multipart/form-data request with charset
$req = Mojo::Message::Request->new;
is $req->default_charset, 'UTF-8', 'default charset is UTF-8';
my $yatta = 'やった';
my $yatta_sjis = encode 'Shift_JIS', $yatta;
my $multipart
  = "------1234567890\x0d\x0a"
  . "Content-Disposition: form-data; name=\"$yatta_sjis\"\x0d\x0a\x0d\x0a"
  . "$yatta_sjis\x0d\x0a------1234567890--";
$req->parse("POST /example/yatta HTTP/1.1\x0d\x0a"
    . "User-Agent: Mozilla/5.0\x0d\x0a"
    . 'Content-Type: multipart/form-data; charset=Shift_JIS; '
    . "boundary=----1234567890\x0d\x0a"
    . "Content-Length: @{[length $multipart]}\x0d\x0a"
    . "Connection: keep-alive\x0d\x0a"
    . "Host: 127.0.0.1:3000\x0d\x0a\x0d\x0a"
    . $multipart);
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/example/yatta', 'right URL';
is $req->param($yatta), $yatta, 'right value';
is $req->content->parts->[0]->asset->slurp, $yatta_sjis, 'right content';

# WebKit multipart/form-data request
$req = Mojo::Message::Request->new;
$req->parse("POST /example/testform_handler HTTP/1.1\x0d\x0a");
$req->parse("User-Agent: Mozilla/5.0\x0d\x0a");
$req->parse('Content-Type: multipart/form-data; ');
$req->parse("boundary=----WebKitFormBoundaryi5BnD9J9zoTMiSuP\x0d\x0a");
$req->parse("Content-Length: 323\x0d\x0aConnection: keep-alive\x0d\x0a");
$req->parse("Host: 127.0.0.1:3000\x0d\x0a\x0d\x0a");
$req->parse("------WebKitFormBoundaryi5BnD9J9zoTMiSuP\x0d\x0a");
$req->parse("Content-Disposition: form-data; name=\"Vorname\"\x0d\x0a");
$req->parse("\x0d\x0aT\x0d\x0a------WebKitFormBoundaryi5BnD9J9zoTMiSuP\x0d");
$req->parse("\x0aContent-Disposition: form-data; name=\"Zuname\"\x0d\x0a");
$req->parse("\x0d\x0a\x0d\x0a------WebKitFormBoundaryi5BnD9J9zoTMiSuP\x0d");
$req->parse("\x0aContent-Disposition: form-data; name=\"Text\"\x0d\x0a");
$req->parse("\x0d\x0a\x0d\x0a------WebKitFormBoundaryi5BnD9J9zoTMiSuP-");
ok !$req->is_finished, 'request is not finished';
$req->parse('-');
ok !$req->is_finished, 'request is not finished';
$req->parse("\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/example/testform_handler', 'right URL';
is $req->param('Vorname'), 'T', 'right value';
is $req->param('Zuname'),  '',  'right value';
is $req->param('Text'),    '',  'right value';
is $req->content->parts->[0]->asset->slurp, 'T', 'right content';

# Chrome 35 multipart/form-data request (with quotation marks)
$req = Mojo::Message::Request->new;
$req->parse("POST / HTTP/1.1\x0d\x0a");
$req->parse("Host: 127.0.0.1:3000\x0d\x0a");
$req->parse("Connection: keep-alive\x0d\x0a");
$req->parse("Content-Length: 180\x0d\x0a");
$req->parse('Accept: text/html,application/xhtml+xml,application/xml;q=');
$req->parse("0.9,image/webp,*/*;q=0.8\x0d\x0a");
$req->parse("Origin: http://127.0.0.1:3000\x0d\x0a");
$req->parse('User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_0) App');
$req->parse('leWebKit/537.36 (KHTML, like Gecko) Chrome/30.0.1599.101 Safari');
$req->parse("/537.36\x0d\x0a");
$req->parse('Content-Type: multipart/form-data; boundary=----WebKitFormBoun');
$req->parse("daryMTelhBLWA9N3KXAR\x0d\x0a");
$req->parse("Referer: http://127.0.0.1:3000/\x0d\x0a");
$req->parse("Accept-Encoding: gzip,deflate,sdch\x0d\x0a");
$req->parse("Accept-Language: en-US,en;q=0.8\x0d\x0a\x0d\x0a");
$req->parse("------WebKitFormBoundaryMTelhBLWA9N3KXAR\x0d\x0a");
$req->parse('Content-Disposition: form-data; na');
$req->parse('me="foo \\%22bar%22 baz\"; filename="fo\\%22o%22.txt\"');
$req->parse("\x0d\x0a\x0d\x0atest\x0d\x0a");
$req->parse("------WebKitFormBoundaryMTelhBLWA9N3KXAR--\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/', 'right URL';
is $req->upload('foo \\%22bar%22 baz\\')->filename, 'fo\\%22o%22.txt\\',
  'right filename';
is $req->upload('foo \\%22bar%22 baz\\')->slurp, 'test', 'right content';

# Firefox 24 multipart/form-data request (with quotation marks)
$req = Mojo::Message::Request->new;
$req->parse("POST / HTTP/1.1\x0d\x0a");
$req->parse("Host: 127.0.0.1:3000\x0d\x0a");
$req->parse('User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10.9; rv:24.');
$req->parse("0) Gecko/20100101 Firefox/24.0\x0d\x0a");
$req->parse('Accept: text/html,application/xhtml+xml,application/xml;q=0.9');
$req->parse(",*/*;q=0.8\x0d\x0a");
$req->parse("Accept-Language: de-de,de;q=0.8,en-us;q=0.5,en;q=0.3\x0d\x0a");
$req->parse("Accept-Encoding: gzip, deflate\x0d\x0a");
$req->parse("Referer: http://127.0.0.1:3000/\x0d\x0a");
$req->parse("Connection: keep-alive\x0d\x0a");
$req->parse('Content-Type: multipart/form-data; boundary=-----------------');
$req->parse("----------20773201241877674789807986058\x0d\x0a");
$req->parse("Content-Length: 212\x0d\x0a\x0d\x0a");
$req->parse('-----------------------------2077320124187767478980');
$req->parse("7986058\x0d\x0aContent-Disposition: form-data; na");
$req->parse('me="foo \\\\"bar\\" baz"; filename="fo\\\\"o\\".txt"');
$req->parse("\x0d\x0a\x0d\x0atest\x0d\x0a");
$req->parse('-----------------------------2077320124187767');
$req->parse("4789807986058--\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/', 'right URL';
is $req->upload('foo \\\"bar\" baz')->filename, 'fo\\\\"o\\".txt',
  'right filename';
is $req->upload('foo \\\"bar\" baz')->slurp, 'test', 'right content';

# Chrome 5 multipart/form-data request (UTF-8)
$req = Mojo::Message::Request->new;
my ($fname, $sname, $sex, $avatar, $submit)
  = map { encode 'UTF-8', $_ } 'Иван', 'Иванов', 'мужской',
  'аватар.jpg', 'Сохранить';
my $chrome
  = "------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
  . "Content-Disposition: form-data; name=\"fname\"\x0d\x0a\x0d\x0a"
  . "$fname\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
  . "Content-Disposition: form-data; name=\"sname\"\x0d\x0a\x0d\x0a"
  . "$sname\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
  . "Content-Disposition: form-data; name=\"sex\"\x0d\x0a\x0d\x0a"
  . "$sex\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
  . "Content-Disposition: form-data; name=\"bdate\"\x0d\x0a\x0d\x0a"
  . "16.02.1987\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
  . "Content-Disposition: form-data; name=\"phone\"\x0d\x0a\x0d\x0a"
  . "1234567890\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
  . "Content-Disposition: form-data; name=\"avatar\"; filename=\"$avatar\""
  . "\x0d\x0aContent-Type: image/jpeg\x0d\x0a\x0d\x0a1234"
  . "\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX\x0d\x0a"
  . "Content-Disposition: form-data; name=\"submit\"\x0d\x0a\x0d\x0a"
  . "$submit\x0d\x0a------WebKitFormBoundaryYGjwdkpB6ZLCZQbX--";
$req->parse("POST / HTTP/1.0\x0d\x0a"
    . "Host: 127.0.0.1:10002\x0d\x0a"
    . "Connection: close\x0d\x0a"
    . 'User-Agent: Mozilla/5.0 (X11; U; Linux x86_64; en-US) AppleWebKit/5'
    . "32.9 (KHTML, like Gecko) Chrome/5.0.307.11 Safari/532.9\x0d\x0a"
    . "Referer: http://example.org/\x0d\x0a"
    . "Content-Length: @{[length $chrome]}\x0d\x0a"
    . "Cache-Control: max-age=0\x0d\x0a"
    . "Origin: http://example.org\x0d\x0a"
    . 'Content-Type: multipart/form-data; boundary=----WebKitFormBoundaryY'
    . "GjwdkpB6ZLCZQbX\x0d\x0a"
    . 'Accept: application/xml,application/xhtml+xml,text/html;q=0.9,text/'
    . "plain;q=0.8,image/png,*/*;q=0.5\x0d\x0a"
    . "Accept-Encoding: gzip,deflate,sdch\x0d\x0a"
    . 'Cookie: mojolicious=BAcIMTIzNDU2NzgECAgIAwIAAAAXDGFsZXgudm9yb25vdgQ'
    . 'AAAB1c2VyBp6FjksAAAAABwAAAGV4cGlyZXM=--1641adddfe885276cda0deb7475f'
    . "153a\x0d\x0a"
    . "Accept-Language: ru-RU,ru;q=0.8,en-US;q=0.6,en;q=0.4\x0d\x0a"
    . "Accept-Charset: windows-1251,utf-8;q=0.7,*;q=0.3\x0d\x0a\x0d\x0a"
    . $chrome);
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.0', 'right version';
is $req->url,         '/', 'right URL';
is $req->cookie('mojolicious')->value,
  'BAcIMTIzNDU2NzgECAgIAwIAAAAXDGFsZXgudm9yb25vdgQAAAB1c2VyBp6FjksAAAAABwA'
  . 'AAGV4cGlyZXM=--1641adddfe885276cda0deb7475f153a', 'right value';
like $req->headers->content_type, qr!multipart/form-data!,
  'right "Content-Type" value';
is $req->param('fname'),  'Иван',           'right value';
is $req->param('sname'),  'Иванов',       'right value';
is $req->param('sex'),    'мужской',     'right value';
is $req->param('bdate'),  '16.02.1987',         'right value';
is $req->param('phone'),  '1234567890',         'right value';
is $req->param('submit'), 'Сохранить', 'right value';
my $upload = $req->upload('avatar');
is $upload->isa('Mojo::Upload'), 1, 'right upload';
is $upload->headers->content_type, 'image/jpeg', 'right "Content-Type" value';
is $upload->filename, 'аватар.jpg', 'right filename';
is $upload->size,     4,                  'right size';
is $upload->slurp,    '1234',             'right content';
is $req->content->parts->[0]->asset->slurp, $fname, 'right content';

# Firefox 3.5.8 multipart/form-data request (UTF-8)
$req = Mojo::Message::Request->new;
($fname, $sname, $sex, $avatar, $submit)
  = map { encode 'UTF-8', $_ } 'Иван', 'Иванов', 'мужской',
  'аватар.jpg', 'Сохранить';
my $firefox
  = "-----------------------------213090722714721300002030499922\x0d\x0a"
  . "Content-Disposition: form-data; name=\"fname\"\x0d\x0a\x0d\x0a"
  . "$fname\x0d\x0a"
  . "-----------------------------213090722714721300002030499922\x0d\x0a"
  . "Content-Disposition: form-data; name=\"sname\"\x0d\x0a\x0d\x0a"
  . "$sname\x0d\x0a"
  . "-----------------------------213090722714721300002030499922\x0d\x0a"
  . "Content-Disposition: form-data; name=\"sex\"\x0d\x0a\x0d\x0a"
  . "$sex\x0d\x0a"
  . "-----------------------------213090722714721300002030499922\x0d\x0a"
  . "Content-Disposition: form-data; name=\"bdate\"\x0d\x0a\x0d\x0a"
  . "16.02.1987\x0d\x0a"
  . "-----------------------------213090722714721300002030499922\x0d\x0a"
  . "Content-Disposition: form-data; name=\"phone\"\x0d\x0a\x0d\x0a"
  . "1234567890\x0d\x0a"
  . "-----------------------------213090722714721300002030499922\x0d\x0a"
  . "Content-Disposition: form-data; name=\"avatar\"; filename=\"$avatar\""
  . "\x0d\x0aContent-Type: image/jpeg\x0d\x0a\x0d\x0a1234\x0d\x0a"
  . "-----------------------------213090722714721300002030499922\x0d\x0a"
  . "Content-Disposition: form-data; name=\"submit\"\x0d\x0a\x0d\x0a"
  . "$submit\x0d\x0a"
  . '-----------------------------213090722714721300002030499922--';
$req->parse("POST / HTTP/1.0\x0d\x0a"
    . "Host: 127.0.0.1:10002\x0d\x0a"
    . "Connection: close\x0d\x0a"
    . 'User-Agent: Mozilla/5.0 (X11; U; Linux x86_64; ru; rv:1.9.1.8) Geck'
    . "o/20100214 Ubuntu/9.10 (karmic) Firefox/3.5.8\x0d\x0a"
    . 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q'
    . "=0.8\x0d\x0a"
    . "Accept-Language: ru,en-us;q=0.7,en;q=0.3\x0d\x0a"
    . "Accept-Encoding: gzip,deflate\x0d\x0a"
    . "Accept-Charset: windows-1251,utf-8;q=0.7,*;q=0.7\x0d\x0a"
    . "Referer: http://example.org/\x0d\x0a"
    . 'Cookie: mojolicious=BAcIMTIzNDU2NzgECAgIAwIAAAAXDGFsZXgudm9yb25vdgQ'
    . 'AAAB1c2VyBiWFjksAAAAABwAAAGV4cGlyZXM=--cd933a37999e0fa8d7804205e891'
    . "93a7\x0d\x0a"
    . 'Content-Type: multipart/form-data; boundary=-----------------------'
    . "----213090722714721300002030499922\x0d\x0a"
    . "Content-Length: @{[length $firefox]}\x0d\x0a\x0d\x0a"
    . $firefox);
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.0', 'right version';
is $req->url,         '/', 'right URL';
is $req->cookie('mojolicious')->value,
  'BAcIMTIzNDU2NzgECAgIAwIAAAAXDGFsZXgudm9yb25vdgQAAAB1c2VyBiWFjksAAAAABwA'
  . 'AAGV4cGlyZXM=--cd933a37999e0fa8d7804205e89193a7', 'right value';
like $req->headers->content_type, qr!multipart/form-data!,
  'right "Content-Type" value';
is $req->param('fname'),  'Иван',           'right value';
is $req->param('sname'),  'Иванов',       'right value';
is $req->param('sex'),    'мужской',     'right value';
is $req->param('bdate'),  '16.02.1987',         'right value';
is $req->param('phone'),  '1234567890',         'right value';
is $req->param('submit'), 'Сохранить', 'right value';
$upload = $req->upload('avatar');
is $upload->isa('Mojo::Upload'), 1, 'right upload';
is $upload->headers->content_type, 'image/jpeg', 'right "Content-Type" value';
is $upload->filename, 'аватар.jpg', 'right filename';
is $upload->size,     4,                  'right size';
is $upload->slurp,    '1234',             'right content';
is $req->content->parts->[0]->asset->slurp, $fname, 'right content';

# Opera 9.8 multipart/form-data request (UTF-8)
$req = Mojo::Message::Request->new;
($fname, $sname, $sex, $avatar, $submit)
  = map { encode 'UTF-8', $_ } 'Иван', 'Иванов', 'мужской',
  'аватар.jpg', 'Сохранить';
my $opera
  = "------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
  . "Content-Disposition: form-data; name=\"fname\"\x0d\x0a\x0d\x0a"
  . "$fname\x0d\x0a------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
  . "Content-Disposition: form-data; name=\"sname\"\x0d\x0a\x0d\x0a"
  . "$sname\x0d\x0a------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
  . "Content-Disposition: form-data; name=\"sex\"\x0d\x0a\x0d\x0a"
  . "$sex\x0d\x0a------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
  . "Content-Disposition: form-data; name=\"bdate\"\x0d\x0a\x0d\x0a"
  . "16.02.1987\x0d\x0a------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
  . "Content-Disposition: form-data; name=\"phone\"\x0d\x0a\x0d\x0a"
  . "1234567890\x0d\x0a------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
  . "Content-Disposition: form-data; name=\"avatar\"; filename=\"$avatar\""
  . "\x0d\x0aContent-Type: image/jpeg\x0d\x0a\x0d\x0a"
  . "1234\x0d\x0a------------IWq9cR9mYYG668xwSn56f0\x0d\x0a"
  . "Content-Disposition: form-data; name=\"submit\"\x0d\x0a\x0d\x0a"
  . "$submit\x0d\x0a------------IWq9cR9mYYG668xwSn56f0--";
$req->parse("POST / HTTP/1.0\x0d\x0a"
    . "Host: 127.0.0.1:10002\x0d\x0a"
    . "Connection: close\x0d\x0a"
    . 'User-Agent: Opera/9.80 (X11; Linux x86_64; U; ru) Presto/2.2.15 Ver'
    . "sion/10.10\x0d\x0a"
    . 'Accept: text/html, application/xml;q=0.9, application/xhtml+xml, im'
    . "age/png, image/jpeg, image/gif, image/x-xbitmap, */*;q=0.1\x0d\x0a"
    . "Accept-Language: ru-RU,ru;q=0.9,en;q=0.8\x0d\x0a"
    . "Accept-Charset: iso-8859-1, utf-8, utf-16, *;q=0.1\x0d\x0a"
    . "Accept-Encoding: deflate, gzip, x-gzip, identity, *;q=0\x0d\x0a"
    . "Referer: http://example.org/\x0d\x0a"
    . 'Cookie: mojolicious=BAcIMTIzNDU2NzgECAgIAwIAAAAXDGFsZXgudm9yb25vdgQ'
    . 'AAAB1c2VyBhaIjksAAAAABwAAAGV4cGlyZXM=--78a58a94f98ae5b75a489be1189f'
    . "2672\x0d\x0a"
    . "Cookie2: \$Version=1\x0d\x0a"
    . "TE: deflate, gzip, chunked, identity, trailers\x0d\x0a"
    . "Content-Length: @{[length $opera]}\x0d\x0a"
    . 'Content-Type: multipart/form-data; boundary=----------IWq9cR9mYYG66'
    . "8xwSn56f0\x0d\x0a\x0d\x0a"
    . $opera);
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.0', 'right version';
is $req->url,         '/', 'right URL';
is $req->cookie('mojolicious')->value,
  'BAcIMTIzNDU2NzgECAgIAwIAAAAXDGFsZXgudm9yb25vdgQAAAB1c2VyBhaIjksAAAAABwA'
  . 'AAGV4cGlyZXM=--78a58a94f98ae5b75a489be1189f2672', 'right value';
like $req->headers->content_type, qr!multipart/form-data!,
  'right "Content-Type" value';
is $req->param('fname'),  'Иван',           'right value';
is $req->param('sname'),  'Иванов',       'right value';
is $req->param('sex'),    'мужской',     'right value';
is $req->param('bdate'),  '16.02.1987',         'right value';
is $req->param('phone'),  '1234567890',         'right value';
is $req->param('submit'), 'Сохранить', 'right value';
$upload = $req->upload('avatar');
is $upload->isa('Mojo::Upload'), 1, 'right upload';
is $upload->headers->content_type, 'image/jpeg', 'right "Content-Type" value';
is $upload->filename, 'аватар.jpg', 'right filename';
is $upload->size,     4,                  'right size';
is $upload->slurp,    '1234',             'right content';
is $req->content->parts->[0]->asset->slurp, $fname, 'right content';

# Firefox 14 multipart/form-data request (UTF-8)
$req = Mojo::Message::Request->new;
my ($name, $filename) = map { encode 'UTF-8', $_ } '☃', 'foo bär ☃.txt';
$firefox
  = "-----------------------------1264369278903768281481663536\x0d\x0a"
  . "Content-Disposition: form-data; name=\"$name\"; filename=\"$filename\""
  . "\x0d\x0aContent-Type: text/plain\x0d\x0a\x0d\x0atest 123\x0d\x0a"
  . '-----------------------------1264369278903768281481663536--';
$req->parse("POST /foo HTTP/1.1\x0d\x0a");
$req->parse("Host: 127.0.0.1:3000\x0d\x0a");
$req->parse('User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv');
$req->parse(":14.0) Gecko/20100101 Firefox/14.0.1\x0d\x0a");
$req->parse('Accept: text/html,application/xhtml+xml,application/xml;');
$req->parse("q=0.9,*/*;q=0.8\x0d\x0a");
$req->parse("Accept-Language: en-us,en;q=0.5\x0d\x0a");
$req->parse("Accept-Encoding: gzip, deflate\x0d\x0a");
$req->parse("Connection: keep-alive\x0d\x0a");
$req->parse("Referer: http://127.0.0.1:3000/\x0d\x0a");
$req->parse('Content-Type: multipart/form-data;');
$req->parse('boundary=---------------------------126436927890376828148');
$req->parse("1663536\x0d\x0a");
$req->parse("Content-Length: @{[length $firefox]}\x0d\x0a\x0d\x0a");
$req->parse($firefox);
ok $req->is_finished, 'request is finished';
is $req->method,      'POST', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/foo', 'right URL';
like $req->headers->content_type, qr!multipart/form-data!,
  'right "Content-Type" value';
is $req->upload('☃')->name, '☃', 'right name';
is $req->upload('☃')->filename, 'foo bär ☃.txt', 'right filename';
is $req->upload('☃')->headers->content_type, 'text/plain',
  'right "Content-Type" value';
is $req->upload('☃')->asset->size,  8,          'right size';
is $req->upload('☃')->asset->slurp, 'test 123', 'right content';

# Parse "~" in URL
$req = Mojo::Message::Request->new;
$req->parse("GET /~foobar/ HTTP/1.1\x0d\x0a\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/~foobar/', 'right URL';

# Parse ":" in URL
$req = Mojo::Message::Request->new;
$req->parse("GET /perldoc?Mojo::Message::Request HTTP/1.1\x0d\x0a\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/perldoc?Mojo::Message::Request', 'right URL';
is $req->url->query->params->[0], 'Mojo::Message::Request', 'right value';

# Parse lots of special characters in URL
$req = Mojo::Message::Request->new;
$req->parse('GET /#09azAZ!$%&\'()*+,-./:;=?@[\\]^_`{|}~ ');
$req->parse("HTTP/1.1\x0d\x0a\x0d\x0a");
ok $req->is_finished, 'request is finished';
is $req->method,      'GET', 'right method';
is $req->version,     '1.1', 'right version';
is $req->url,         '/#09azAZ!$%&\'()*+,-./:;=?@%5B%5C%5D%5E_%60%7B%7C%7D~',
  'right URL';

# Abstract methods
eval { Mojo::Message->cookies };
like $@, qr/Method "cookies" not implemented by subclass/, 'right error';
eval { Mojo::Message->extract_start_line };
like $@, qr/Method "extract_start_line" not implemented by subclass/,
  'right error';
eval { Mojo::Message->get_start_line_chunk };
like $@, qr/Method "get_start_line_chunk" not implemented by subclass/,
  'right error';

done_testing();
