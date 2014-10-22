use Mojo::Base -strict;

use Test::More;
use Mojo::Message::Request;

# Parse Lighttpd CGI environment variables and body
my $req = Mojo::Message::Request->new;
my $body;
$req->content->on(body => sub { $body++ });
$req->parse(
  HTTP_CONTENT_LENGTH => 11,
  HTTP_DNT            => 1,
  PATH_INFO           => '/te+st/index.cgi/foo/bar',
  QUERY_STRING        => 'lalala=23&bar=baz',
  REQUEST_METHOD      => 'POST',
  SCRIPT_NAME         => '/te+st/index.cgi',
  HTTP_HOST           => 'localhost:8080',
  SERVER_PROTOCOL     => 'HTTP/1.0'
);
is $body, 1, 'body event has been emitted once';
$req->parse('Hello ');
is $body, 1, 'body event has been emitted once';
$req->parse('World');
is $body, 1, 'body event has been emitted once';
ok $req->is_finished, 'request is finished';
is $req->method, 'POST', 'right method';
is $req->url->path, 'foo/bar', 'right path';
is $req->url->base->path, '/te+st/index.cgi/', 'right base path';
is $req->url->base->host, 'localhost',         'right base host';
is $req->url->base->port, 8080,                'right base port';
is $req->url->query, 'lalala=23&bar=baz', 'right query';
is $req->version, '1.0', 'right version';
is $req->headers->dnt, 1, 'right "DNT" value';
is $req->body, 'Hello World', 'right content';
is $req->url->to_abs->to_string,
  'http://localhost:8080/te+st/index.cgi/foo/bar?lalala=23&bar=baz',
  'right absolute URL';

# Parse Lighttpd CGI environment variables and body (behind reverse proxy)
$req = Mojo::Message::Request->new;
$req->parse(
  HTTP_CONTENT_LENGTH  => 11,
  HTTP_DNT             => 1,
  HTTP_X_FORWARDED_FOR => '127.0.0.1',
  PATH_INFO            => '/test/index.cgi/foo/bar',
  QUERY_STRING         => 'lalala=23&bar=baz',
  REQUEST_METHOD       => 'POST',
  SCRIPT_NAME          => '/test/index.cgi',
  HTTP_HOST            => 'mojolicio.us',
  SERVER_PROTOCOL      => 'HTTP/1.0'
);
$req->parse('Hello World');
ok $req->is_finished, 'request is finished';
is $req->method, 'POST', 'right method';
is $req->url->path, 'foo/bar', 'right path';
is $req->url->base->path, '/test/index.cgi/', 'right base path';
is $req->url->base->host, 'mojolicio.us',     'right base host';
is $req->url->base->port, '',                 'no base port';
is $req->url->query, 'lalala=23&bar=baz', 'right query';
is $req->version, '1.0', 'right version';
is $req->headers->dnt, 1, 'right "DNT" value';
is $req->body, 'Hello World', 'right content';
is $req->url->to_abs->to_string,
  'http://mojolicio.us/test/index.cgi/foo/bar?lalala=23&bar=baz',
  'right absolute URL';

# Parse Apache CGI environment variables and body
$req = Mojo::Message::Request->new;
$req->parse(
  CONTENT_LENGTH  => 11,
  CONTENT_TYPE    => 'application/x-www-form-urlencoded',
  HTTP_DNT        => 1,
  PATH_INFO       => '/test/index.cgi/foo/bar',
  QUERY_STRING    => 'lalala=23&bar=baz',
  REQUEST_METHOD  => 'POST',
  SCRIPT_NAME     => '/test/index.cgi',
  HTTP_HOST       => 'localhost:8080',
  SERVER_PROTOCOL => 'HTTP/1.0'
);
$req->parse('hello=world');
ok $req->is_finished, 'request is finished';
is $req->method, 'POST', 'right method';
is $req->url->path, 'foo/bar', 'right path';
is $req->url->base->path, '/test/index.cgi/', 'right base path';
is $req->url->base->host, 'localhost',        'right base host';
is $req->url->base->port, 8080,               'right base port';
is $req->url->query, 'lalala=23&bar=baz', 'right query';
is $req->version, '1.0', 'right version';
is $req->headers->dnt, 1, 'right "DNT" value';
is $req->body, 'hello=world', 'right content';
is_deeply $req->param('hello'), 'world', 'right value';
is $req->url->to_abs->to_string,
  'http://localhost:8080/test/index.cgi/foo/bar?lalala=23&bar=baz',
  'right absolute URL';

# Parse Apache CGI environment variables and body (file storage)
{
  local $ENV{MOJO_MAX_MEMORY_SIZE} = 10;
  $req = Mojo::Message::Request->new;
  is $req->content->asset->max_memory_size, 10, 'right size';
  ok !$req->content->is_parsing_body, 'is not parsing body';
  $req->parse(
    CONTENT_LENGTH  => 12,
    CONTENT_TYPE    => 'text/plain',
    HTTP_DNT        => 1,
    PATH_INFO       => '/test/index.cgi/foo/bar',
    QUERY_STRING    => 'lalala=23&bar=baz',
    REQUEST_METHOD  => 'POST',
    SCRIPT_NAME     => '/test/index.cgi',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.1'
  );
  ok $req->content->is_parsing_body, 'is parsing body';
  is $req->content->progress, 0, 'right progress';
  $req->parse('Hello ');
  ok $req->content->is_parsing_body, 'is parsing body';
  ok !$req->content->asset->is_file, 'stored in memory';
  is $req->content->progress, 6, 'right progress';
  $req->parse('World!');
  ok !$req->content->is_parsing_body, 'is not parsing body';
  ok $req->content->asset->is_file, 'stored in file';
  is $req->content->progress, 12, 'right progress';
  ok $req->is_finished, 'request is finished';
  ok !$req->content->is_multipart, 'no multipart content';
  is $req->method, 'POST', 'right method';
  is $req->url->path, 'foo/bar', 'right path';
  is $req->url->base->path, '/test/index.cgi/', 'right base path';
  is $req->url->base->host, 'localhost',        'right base host';
  is $req->url->base->port, 8080,               'right base port';
  is $req->url->query, 'lalala=23&bar=baz', 'right query';
  is $req->version, '1.1', 'right version';
  is $req->headers->dnt,          1,            'right "DNT" value';
  is $req->headers->content_type, 'text/plain', 'right "Content-Type" value';
  is $req->headers->content_length, 12, 'right "Content-Length" value';
  is $req->body, 'Hello World!', 'right content';
  is $req->url->to_abs->to_string,
    'http://localhost:8080/test/index.cgi/foo/bar?lalala=23&bar=baz',
    'right absolute URL';
}

# Parse Apache CGI environment variables with basic authentication
$req = Mojo::Message::Request->new;
$req->parse(
  CONTENT_LENGTH           => 11,
  HTTP_Authorization       => 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  HTTP_Proxy_Authorization => 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
  CONTENT_TYPE             => 'application/x-www-form-urlencoded',
  HTTP_DNT                 => 1,
  PATH_INFO                => '/test/index.cgi/foo/bar',
  QUERY_STRING             => 'lalala=23&bar=baz',
  REQUEST_METHOD           => 'POST',
  SCRIPT_NAME              => '/test/index.cgi',
  HTTP_HOST                => 'localhost:8080',
  SERVER_PROTOCOL          => 'HTTP/1.0'
);
$req->parse('hello=world');
ok $req->is_finished, 'request is finished';
is $req->method, 'POST', 'right method';
is $req->url->path, 'foo/bar', 'right path';
is $req->url->base->path, '/test/index.cgi/', 'right base path';
is $req->url->base->host, 'localhost',        'right base host';
is $req->url->base->port, 8080,               'right base port';
is $req->url->query, 'lalala=23&bar=baz', 'right query';
is $req->version, '1.0', 'right version';
is $req->headers->dnt, 1, 'right "DNT" value';
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

# Parse Apache 2.2 (win32) CGI environment variables and body
$req = Mojo::Message::Request->new;
my ($finished, $progress);
$req->on(finish => sub { $finished = shift->is_finished });
$req->on(progress => sub { $progress++ });
ok !$finished, 'not finished';
ok !$progress, 'no progress';
is $req->content->progress, 0, 'right progress';
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
ok !$finished, 'not finished';
ok $progress, 'made progress';
$progress = 0;
is $req->content->progress, 0, 'right progress';
$req->parse('request=&ajax=true&login=test&password=111&');
ok !$finished, 'not finished';
ok $progress, 'made progress';
$progress = 0;
is $req->content->progress, 43, 'right progress';
$req->parse('edition=db6d8b30-16df-4ecd-be2f-c8194f94e1f4');
ok $finished, 'finished';
ok $progress, 'made progress';
is $req->content->progress, 87, 'right progress';
ok $req->is_finished, 'request is finished';
is $req->method, 'POST', 'right method';
is $req->url->path, '', 'no path';
is $req->url->base->path, '/index.pl/', 'right base path';
is $req->url->base->host, 'test1',      'right base host';
is $req->url->base->port, '',           'no base port';
ok !$req->url->query->to_string, 'no query';
is $req->version, '1.1', 'right version';
is $req->body, 'request=&ajax=true&login=test&password=111&'
  . 'edition=db6d8b30-16df-4ecd-be2f-c8194f94e1f4', 'right content';
is $req->param('ajax'),     'true', 'right value';
is $req->param('login'),    'test', 'right value';
is $req->param('password'), '111',  'right value';
is $req->param('edition'), 'db6d8b30-16df-4ecd-be2f-c8194f94e1f4',
  'right value';
is $req->url->to_abs->to_string, 'http://test1/index.pl', 'right absolute URL';

# Parse Apache 2.2 (win32) CGI environment variables and body
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
ok $req->is_finished, 'request is finished';
is $req->method, 'POST', 'right method';
is $req->url->path, '', 'no path';
is $req->url->base->path, '/index.pl/', 'right base path';
is $req->url->base->host, 'test1',      'right base host';
is $req->url->base->port, '',           'no base port';
ok !$req->url->query->to_string, 'no query';
is $req->version, '1.1', 'right version';
is $req->body, 'request=&ajax=true&login=test&password=111&'
  . 'edition=db6d8b30-16df-4ecd-be2f-c8194f94e1f4', 'right content';
is $req->param('ajax'),     'true', 'right value';
is $req->param('login'),    'test', 'right value';
is $req->param('password'), '111',  'right value';
is $req->param('edition'), 'db6d8b30-16df-4ecd-be2f-c8194f94e1f4',
  'right value';
is $req->url->to_abs->to_string, 'http://test1/index.pl', 'right absolute URL';

# Parse Apache 2.2.14 CGI environment variables and body (root)
$req = Mojo::Message::Request->new;
$req->parse(
  SCRIPT_NAME       => '/upload',
  SERVER_NAME       => '127.0.0.1',
  SERVER_ADMIN      => '[no address given]',
  PATH_INFO         => '/upload',
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
  REQUEST_URI       => '/upload',
  GATEWAY_INTERFACE => 'CGI/1.1',
  SERVER_ADDR       => '127.0.0.1',
  DOCUMENT_ROOT     => '/tmp/SnLu1cQ3t2',
  PATH_TRANSLATED   => '/tmp/test.fcgi/upload',
  HTTP_HOST         => '127.0.0.1:13028'
);
$req->parse('hello=world');
ok $req->is_finished, 'request is finished';
is $req->method, 'POST', 'right method';
is $req->url->base->host, '127.0.0.1', 'right base host';
is $req->url->base->port, 13028,       'right base port';
is $req->url->path, '', 'no path';
is $req->url->base->path, '/upload/', 'right base path';
is $req->version, '1.1', 'right version';
ok !$req->is_secure, 'not secure';
is $req->body, 'hello=world', 'right content';
is_deeply $req->param('hello'), 'world', 'right parameters';
is $req->url->to_abs->to_string, 'http://127.0.0.1:13028/upload',
  'right absolute URL';

# Parse Apache 2.2.11 CGI environment variables and body (HTTPS=ON)
$req = Mojo::Message::Request->new;
$req->parse(
  CONTENT_LENGTH  => 11,
  CONTENT_TYPE    => 'application/x-www-form-urlencoded',
  PATH_INFO       => '/foo/bar',
  QUERY_STRING    => '',
  REQUEST_METHOD  => 'GET',
  SCRIPT_NAME     => '/test/index.cgi',
  HTTP_HOST       => 'localhost',
  HTTPS           => 'ON',
  SERVER_PROTOCOL => 'HTTP/1.0'
);
$req->parse('hello=world');
ok $req->is_finished, 'request is finished';
is $req->method, 'GET', 'right method';
is $req->url->base->host, 'localhost', 'right base host';
is $req->url->path, 'foo/bar', 'right path';
is $req->url->base->path, '/test/index.cgi/', 'right base path';
is $req->version, '1.0', 'right version';
ok $req->is_secure, 'is secure';
is $req->body, 'hello=world', 'right content';
is_deeply $req->param('hello'), 'world', 'right parameters';
is $req->url->to_abs->to_string, 'https://localhost/test/index.cgi/foo/bar',
  'right absolute URL';

# Parse Apache 2.2.11 CGI environment variables and body (trailing slash)
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
ok $req->is_finished, 'request is finished';
is $req->method, 'GET', 'right method';
is $req->url->base->host, 'localhost', 'right base host';
is $req->url->path, 'foo/bar/', 'right path';
is $req->url->base->path, '/test/index.cgi/', 'right base path';
is $req->version, '1.0',         'right version';
is $req->body,    'hello=world', 'right content';
is_deeply $req->param('hello'), 'world', 'right parameters';
is $req->url->to_abs->to_string, 'http://localhost/test/index.cgi/foo/bar/',
  'right absolute URL';

# Parse Apache 2.2.11 CGI environment variables and body (no SCRIPT_NAME)
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
ok $req->is_finished, 'request is finished';
is $req->method, 'GET', 'right method';
is $req->url->base->host, 'localhost', 'right base host';
is $req->url->path, '/foo/bar', 'right path';
is $req->url->base->path, '', 'no base path';
is $req->version, '1.0',         'right version';
is $req->body,    'hello=world', 'right content';
is_deeply $req->param('hello'), 'world', 'right parameters';
is $req->url->to_abs->to_string, 'http://localhost/foo/bar',
  'right absolute URL';

# Parse Apache 2.2.11 CGI environment variables and body (no PATH_INFO)
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
ok $req->is_finished, 'request is finished';
is $req->method, 'GET', 'right method';
is $req->url->base->host, 'localhost', 'right base host';
is $req->url->path, '', 'no path';
is $req->url->base->path, '/test/index.cgi/', 'right base path';
is $req->version, '1.0',         'right version';
is $req->body,    'hello=world', 'right content';
is_deeply $req->param('hello'), 'world', 'right parameters';
is $req->url->to_abs->to_string, 'http://localhost/test/index.cgi',
  'right absolute URL';

# Parse Apache 2.2.9 CGI environment variables (root without PATH_INFO)
$req = Mojo::Message::Request->new;
$req->parse(
  SCRIPT_NAME     => '/cgi-bin/myapp/myapp.pl',
  HTTP_CONNECTION => 'keep-alive',
  HTTP_HOST       => 'getmyapp.org',
  REQUEST_METHOD  => 'GET',
  QUERY_STRING    => '',
  REQUEST_URI     => '/cgi-bin/myapp/myapp.pl',
  SERVER_PROTOCOL => 'HTTP/1.1',
);
ok $req->is_finished, 'request is finished';
is $req->method, 'GET', 'right method';
is $req->url->base->host, 'getmyapp.org', 'right base host';
is $req->url->path, '', 'no path';
is $req->url->base->path, '/cgi-bin/myapp/myapp.pl/', 'right base path';
is $req->version, '1.1', 'right version';
is $req->url->to_abs->to_string, 'http://getmyapp.org/cgi-bin/myapp/myapp.pl',
  'right absolute URL';

# Parse Apache mod_fastcgi CGI environment variables (multipart file upload)
$req = Mojo::Message::Request->new;
is $req->content->progress, 0, 'right progress';
$req->parse(
  SCRIPT_NAME      => '',
  SERVER_NAME      => '127.0.0.1',
  SERVER_ADMIN     => '[no address given]',
  PATH_INFO        => '/upload',
  HTTP_CONNECTION  => 'Keep-Alive',
  REQUEST_METHOD   => 'POST',
  CONTENT_LENGTH   => '139',
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
  REQUEST_URI       => '/upload',
  GATEWAY_INTERFACE => 'CGI/1.1',
  SERVER_ADDR       => '127.0.0.1',
  DOCUMENT_ROOT     => '/tmp/SnLu1cQ3t2',
  PATH_TRANSLATED   => '/tmp/test.fcgi/upload',
  HTTP_HOST         => '127.0.0.1:13028'
);
is $req->content->progress, 0, 'right progress';
$req->parse("--8jXGX\x0d\x0a");
is $req->content->progress, 9, 'right progress';
$req->parse(
      "Content-Disposition: form-data; name=\"file\"; filename=\"file.txt\""
    . "\x0d\x0aContent-Type: application/octet-stream\x0d\x0a\x0d\x0a");
is $req->content->progress, 117, 'right progress';
$req->parse('11023456789');
is $req->content->progress, 128, 'right progress';
$req->parse("\x0d\x0a--8jXGX--");
is $req->content->progress, 139, 'right progress';
ok $req->is_finished, 'request is finished';
ok $req->content->is_multipart, 'multipart content';
is $req->method, 'POST', 'right method';
is $req->url->base->host, '127.0.0.1', 'right base host';
is $req->url->path, '/upload', 'right path';
is $req->url->base->path, '', 'no base path';
is $req->version, '1.1', 'right version';
is $req->url->to_abs->to_string, 'http://127.0.0.1:13028/upload',
  'right absolute URL';
my $file = $req->upload('file');
is $file->filename, 'file.txt',    'right filename';
is $file->slurp,    '11023456789', 'right uploaded content';

# Parse IIS 7.5 like CGI environment (HTTPS=off)
$req = Mojo::Message::Request->new;
$req->parse(
  CONTENT_LENGTH  => 0,
  PATH_INFO       => '/index.pl/',
  SERVER_SOFTWARE => 'Microsoft-IIS/7.5',
  QUERY_STRING    => '',
  REQUEST_METHOD  => 'GET',
  SCRIPT_NAME     => '/index.pl',
  HTTP_HOST       => 'test',
  HTTPS           => 'off',
  SERVER_PROTOCOL => 'HTTP/1.1'
);
ok $req->is_finished, 'request is finished';
is $req->method, 'GET', 'right method';
is $req->url->path, '', 'right URL';
is $req->url->base->protocol, 'http',       'right base protocol';
is $req->url->base->path,     '/index.pl/', 'right base path';
is $req->url->base->host,     'test',       'right base host';
ok !$req->url->query->to_string, 'no query';
is $req->version, '1.1', 'right version';
ok !$req->is_secure, 'not secure';

done_testing();
