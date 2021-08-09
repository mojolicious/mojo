use Mojo::Base -strict;

use Test::More;
use Mojo::Asset::File;
use Mojo::Content::Single;
use Mojo::Content::MultiPart;
use Mojo::File qw(tempdir);
use Mojo::JSON qw(encode_json);
use Mojo::Message::Response;
use Mojo::Util qw(encode gzip);

subtest 'Defaults' => sub {
  my $res = Mojo::Message::Response->new;
  is $res->max_message_size, 2147483648, 'right default';
};

subtest 'Common status codes' => sub {
  my $res = Mojo::Message::Response->new;
  is $res->code(100)->default_message, 'Continue',                        'right message';
  is $res->code(101)->default_message, 'Switching Protocols',             'right message';
  is $res->code(102)->default_message, 'Processing',                      'right message';
  is $res->code(103)->default_message, 'Early Hints',                     'right message';
  is $res->code(200)->default_message, 'OK',                              'right message';
  is $res->code(201)->default_message, 'Created',                         'right message';
  is $res->code(202)->default_message, 'Accepted',                        'right message';
  is $res->code(203)->default_message, 'Non-Authoritative Information',   'right message';
  is $res->code(204)->default_message, 'No Content',                      'right message';
  is $res->code(205)->default_message, 'Reset Content',                   'right message';
  is $res->code(206)->default_message, 'Partial Content',                 'right message';
  is $res->code(207)->default_message, 'Multi-Status',                    'right message';
  is $res->code(208)->default_message, 'Already Reported',                'right message';
  is $res->code(226)->default_message, 'IM Used',                         'right message';
  is $res->code(300)->default_message, 'Multiple Choices',                'right message';
  is $res->code(301)->default_message, 'Moved Permanently',               'right message';
  is $res->code(302)->default_message, 'Found',                           'right message';
  is $res->code(303)->default_message, 'See Other',                       'right message';
  is $res->code(304)->default_message, 'Not Modified',                    'right message';
  is $res->code(305)->default_message, 'Use Proxy',                       'right message';
  is $res->code(307)->default_message, 'Temporary Redirect',              'right message';
  is $res->code(308)->default_message, 'Permanent Redirect',              'right message';
  is $res->code(400)->default_message, 'Bad Request',                     'right message';
  is $res->code(401)->default_message, 'Unauthorized',                    'right message';
  is $res->code(402)->default_message, 'Payment Required',                'right message';
  is $res->code(403)->default_message, 'Forbidden',                       'right message';
  is $res->code(404)->default_message, 'Not Found',                       'right message';
  is $res->code(405)->default_message, 'Method Not Allowed',              'right message';
  is $res->code(406)->default_message, 'Not Acceptable',                  'right message';
  is $res->code(407)->default_message, 'Proxy Authentication Required',   'right message';
  is $res->code(408)->default_message, 'Request Timeout',                 'right message';
  is $res->code(409)->default_message, 'Conflict',                        'right message';
  is $res->code(410)->default_message, 'Gone',                            'right message';
  is $res->code(411)->default_message, 'Length Required',                 'right message';
  is $res->code(412)->default_message, 'Precondition Failed',             'right message';
  is $res->code(413)->default_message, 'Request Entity Too Large',        'right message';
  is $res->code(414)->default_message, 'Request-URI Too Long',            'right message';
  is $res->code(415)->default_message, 'Unsupported Media Type',          'right message';
  is $res->code(416)->default_message, 'Request Range Not Satisfiable',   'right message';
  is $res->code(417)->default_message, 'Expectation Failed',              'right message';
  is $res->code(418)->default_message, "I'm a teapot",                    'right message';
  is $res->code(421)->default_message, 'Misdirected Request',             'right message';
  is $res->code(422)->default_message, 'Unprocessable Entity',            'right message';
  is $res->code(423)->default_message, 'Locked',                          'right message';
  is $res->code(424)->default_message, 'Failed Dependency',               'right message';
  is $res->code(425)->default_message, 'Too Early',                       'right message';
  is $res->code(426)->default_message, 'Upgrade Required',                'right message';
  is $res->code(428)->default_message, 'Precondition Required',           'right message';
  is $res->code(429)->default_message, 'Too Many Requests',               'right message';
  is $res->code(431)->default_message, 'Request Header Fields Too Large', 'right message';
  is $res->code(451)->default_message, 'Unavailable For Legal Reasons',   'right message';
  is $res->code(500)->default_message, 'Internal Server Error',           'right message';
  is $res->code(501)->default_message, 'Not Implemented',                 'right message';
  is $res->code(502)->default_message, 'Bad Gateway',                     'right message';
  is $res->code(503)->default_message, 'Service Unavailable',             'right message';
  is $res->code(504)->default_message, 'Gateway Timeout',                 'right message';
  is $res->code(505)->default_message, 'HTTP Version Not Supported',      'right message';
  is $res->code(506)->default_message, 'Variant Also Negotiates',         'right message';
  is $res->code(507)->default_message, 'Insufficient Storage',            'right message';
  is $res->code(508)->default_message, 'Loop Detected',                   'right message';
  is $res->code(509)->default_message, 'Bandwidth Limit Exceeded',        'right message';
  is $res->code(510)->default_message, 'Not Extended',                    'right message';
  is $res->code(511)->default_message, 'Network Authentication Required', 'right message';
  is $res->default_message(100), 'Continue', 'right message';
};

subtest 'Status code ranges' => sub {
  my $res = Mojo::Message::Response->new;
  ok $res->code(101)->is_info,         'is in range';
  ok $res->code(199)->is_info,         'is in range';
  ok $res->code(200)->is_success,      'is in range';
  ok $res->code(202)->is_success,      'is in range';
  ok $res->code(299)->is_success,      'is in range';
  ok $res->code(301)->is_redirect,     'is in range';
  ok $res->code(399)->is_redirect,     'is in range';
  ok $res->code(401)->is_client_error, 'is in range';
  ok $res->code(499)->is_client_error, 'is in range';
  ok $res->code(400)->is_error,        'is in range';
  ok $res->code(599)->is_error,        'is in range';
  ok $res->code(501)->is_server_error, 'is in range';
  ok $res->code(599)->is_server_error, 'is in range';
  ok !$res->code(200)->is_info,         'not in range';
  ok !$res->code(199)->is_success,      'not in range';
  ok !$res->code(300)->is_success,      'not in range';
  ok !$res->code(200)->is_redirect,     'not in range';
  ok !$res->code(200)->is_error,        'not in range';
  ok !$res->code(200)->is_client_error, 'not in range';
  ok !$res->code(200)->is_server_error, 'not in range';
  ok !$res->code(undef)->is_success,    'no range';
};

subtest 'Status code and message' => sub {
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
};

subtest 'Parse HTTP 1.1 response start-line, no headers and body' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 200 OK\x0d\x0a\x0d\x0a");
  ok !$res->is_finished, 'response is not finished';
  is $res->code,    200,   'right status';
  is $res->message, 'OK',  'right message';
  is $res->version, '1.1', 'right version';
};

subtest 'Parse HTTP 1.1 response start-line, no headers and body (small chunks)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse('H');
  ok !$res->is_finished, 'response is not finished';
  $res->parse('T');
  ok !$res->is_finished, 'response is not finished';
  $res->parse('T');
  ok !$res->is_finished, 'response is not finished';
  $res->parse('P');
  ok !$res->is_finished, 'response is not finished';
  $res->parse('/');
  ok !$res->is_finished, 'response is not finished';
  $res->parse('1');
  ok !$res->is_finished, 'response is not finished';
  $res->parse('.');
  ok !$res->is_finished, 'response is not finished';
  $res->parse('1');
  ok !$res->is_finished, 'response is not finished';
  $res->parse(' ');
  ok !$res->is_finished, 'response is not finished';
  $res->parse('2');
  ok !$res->is_finished, 'response is not finished';
  $res->parse('0');
  ok !$res->is_finished, 'response is not finished';
  $res->parse('0');
  ok !$res->is_finished, 'response is not finished';
  $res->parse(' ');
  ok !$res->is_finished, 'response is not finished';
  $res->parse('O');
  ok !$res->is_finished, 'response is not finished';
  $res->parse('K');
  ok !$res->is_finished, 'response is not finished';
  $res->parse("\x0d");
  ok !$res->is_finished, 'response is not finished';
  $res->parse("\x0a");
  ok !$res->is_finished, 'response is not finished';
  $res->parse("\x0d");
  ok !$res->is_finished, 'response is not finished';
  $res->parse("\x0a");
  ok !$res->is_finished, 'response is not finished';
  is $res->code,    200,   'right status';
  is $res->message, 'OK',  'right message';
  is $res->version, '1.1', 'right version';
};

subtest 'Parse HTTP 1.1 response start-line, no headers and body (no message)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 200\x0d\x0a\x0d\x0a");
  ok !$res->is_finished, 'response is not finished';
  is $res->code,    200,   'right status';
  is $res->message, undef, 'no message';
  is $res->version, '1.1', 'right version';
};

subtest 'Parse HTTP 1.0 response start-line and headers but no body' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.0 404 Damn it\x0d\x0a");
  $res->parse("Content-Type: text/plain\x0d\x0a");
  $res->parse("Content-Length: 0\x0d\x0a\x0d\x0a");
  ok $res->is_finished, 'response is finished';
  is $res->code,        404,       'right status';
  is $res->message,     'Damn it', 'right message';
  is $res->version,     '1.0',     'right version';
  is $res->headers->content_type,   'text/plain', 'right "Content-Type" value';
  is $res->headers->content_length, 0,            'right "Content-Length" value';
};

subtest 'Parse full HTTP 1.0 response' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.0 500 Internal Server Error\x0d\x0a");
  $res->parse("Content-Type: text/plain\x0d\x0a");
  $res->parse("Content-Length: 27\x0d\x0a\x0d\x0a");
  $res->parse("Hello World!\n1234\nlalalala\n");
  ok $res->is_finished, 'response is finished';
  is $res->code,        500,                     'right status';
  is $res->message,     'Internal Server Error', 'right message';
  is $res->version,     '1.0',                   'right version';
  is $res->headers->content_type,   'text/plain', 'right "Content-Type" value';
  is $res->headers->content_length, 27,           'right "Content-Length" value';
  is $res->body, "Hello World!\n1234\nlalalala\n", 'right content';
};

subtest 'Parse full HTTP 1.0 response (keep-alive)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.0 500 Internal Server Error\x0d\x0a");
  $res->parse("Connection: keep-alive\x0d\x0a\x0d\x0a");
  $res->parse("HTTP/1.0 200 OK\x0d\x0a\x0d\x0a");
  ok $res->is_finished, 'response is finished';
  is $res->code,        500,                     'right status';
  is $res->message,     'Internal Server Error', 'right message';
  is $res->version,     '1.0',                   'right version';
  is $res->body,        '',                      'no content';
  is $res->content->leftovers, "HTTP/1.0 200 OK\x0d\x0a\x0d\x0a", 'next response in leftovers';
};

subtest 'Parse full HTTP 1.0 response (no limit)' => sub {
  local $ENV{MOJO_MAX_MESSAGE_SIZE} = 0;
  my $res = Mojo::Message::Response->new;
  is $res->max_message_size, 0, 'right size';
  $res->parse("HTTP/1.0 500 Internal Server Error\x0d\x0a");
  $res->parse("Content-Type: text/plain\x0d\x0a");
  $res->parse("Content-Length: 27\x0d\x0a\x0d\x0a");
  $res->parse("Hello World!\n1234\nlalalala\n");
  ok $res->is_finished, 'response is finished';
  ok !$res->error, 'no error';
  is $res->code,    500,                     'right status';
  is $res->message, 'Internal Server Error', 'right message';
  is $res->version, '1.0',                   'right version';
  is $res->headers->content_type,   'text/plain', 'right "Content-Type" value';
  is $res->headers->content_length, 27,           'right "Content-Length" value';
  is $res->body, "Hello World!\n1234\nlalalala\n", 'right content';
};

subtest 'Parse broken start-line' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("12345\x0d\x0a");
  ok $res->is_finished, 'response is finished';
  is $res->error->{message}, 'Bad response start-line', 'right error';
};

subtest 'Parse full HTTP 1.0 response (missing Content-Length)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.0 500 Internal Server Error\x0d\x0a");
  $res->parse("Content-Type: text/plain\x0d\x0a");
  $res->parse("Connection: close\x0d\x0a\x0d\x0a");
  $res->parse("Hello World!\n1234\nlalalala\n");
  ok !$res->is_finished, 'response is not finished';
  is $res->code,    500,                     'right status';
  is $res->message, 'Internal Server Error', 'right message';
  is $res->version, '1.0',                   'right version';
  is $res->headers->content_type,   'text/plain', 'right "Content-Type" value';
  is $res->headers->content_length, undef,        'no "Content-Length" value';
  is $res->body, "Hello World!\n1234\nlalalala\n", 'right content';
};

subtest 'Parse full HTTP 1.0 response (missing Content-Length and Connection)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.0 500 Internal Server Error\x0d\x0a");
  $res->parse("Content-Type: text/plain\x0d\x0a\x0d\x0a");
  $res->parse("Hello World!\n1");
  $res->parse("234\nlala");
  $res->parse("lala\n");
  ok !$res->is_finished, 'response is not finished';
  is $res->code,    500,                     'right status';
  is $res->message, 'Internal Server Error', 'right message';
  is $res->version, '1.0',                   'right version';
  is $res->headers->content_type,   'text/plain', 'right "Content-Type" value';
  is $res->headers->content_length, undef,        'no "Content-Length" value';
  is $res->body, "Hello World!\n1234\nlalalala\n", 'right content';
};

subtest 'Parse full HTTP 1.1 response (missing Content-Length)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 500 Internal Server Error\x0d\x0a");
  $res->parse("Content-Type: text/plain\x0d\x0a");
  $res->parse("Connection: close\x0d\x0a\x0d\x0a");
  $res->parse("Hello World!\n1234\nlalalala\n");
  ok !$res->is_finished, 'response is not finished';
  ok !$res->is_empty,    'response is not empty';
  ok !$res->content->skip_body, 'body has not been skipped';
  ok $res->content->relaxed, 'relaxed response';
  is $res->code,    500,                     'right status';
  is $res->message, 'Internal Server Error', 'right message';
  is $res->version, '1.1',                   'right version';
  is $res->headers->content_type,   'text/plain', 'right "Content-Type" value';
  is $res->headers->content_length, undef,        'no "Content-Length" value';
  is $res->body, "Hello World!\n1234\nlalalala\n", 'right content';
};

subtest 'Parse full HTTP 1.1 response (broken Content-Length)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 200 OK\x0d\x0a");
  $res->parse("Content-Length: 123test\x0d\x0a\x0d\x0a");
  $res->parse('Hello World!');
  ok $res->is_finished, 'response is finished';
  is $res->code,        200,   'right status';
  is $res->message,     'OK',  'right message';
  is $res->version,     '1.1', 'right version';
  is $res->headers->content_length, '123test', 'right "Content-Length" value';
  is $res->body, '', 'no content';
  is $res->content->leftovers, 'Hello World!', 'content in leftovers';
};

subtest 'Parse full HTTP 1.1 response (100 Continue)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->content->on(body => sub { shift->headers->header('X-Body' => 'one') });
  $res->on(progress => sub { shift->headers->header('X-Progress' => 'two') });
  $res->on(finish   => sub { shift->headers->header('X-Finish'   => 'three') });
  $res->parse("HTTP/1.1 100 Continue\x0d\x0a\x0d\x0a");
  ok $res->is_finished, 'response is finished';
  ok $res->is_empty,    'response is empty';
  ok $res->content->skip_body, 'body has been skipped';
  is $res->code,    100,        'right status';
  is $res->message, 'Continue', 'right message';
  is $res->version, '1.1',      'right version';
  is $res->headers->content_length, undef, 'no "Content-Length" value';
  is $res->headers->header('X-Body'),     'one',   'right "X-Body" value';
  is $res->headers->header('X-Progress'), 'two',   'right "X-Progress" value';
  is $res->headers->header('X-Finish'),   'three', 'right "X-Finish" value';
  is $res->body, '', 'no content';
};

subtest 'Parse full HTTP 1.1 response (304 Not Modified)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 304 Not Modified\x0d\x0a");
  $res->parse("Content-Type: text/html\x0d\x0a");
  $res->parse("Content-Length: 9000\x0d\x0a");
  $res->parse("Connection: keep-alive\x0d\x0a\x0d\x0a");
  ok $res->is_finished, 'response is finished';
  ok $res->is_empty,    'response is empty';
  ok $res->content->skip_body, 'body has been skipped';
  is $res->code,    304,            'right status';
  is $res->message, 'Not Modified', 'right message';
  is $res->version, '1.1',          'right version';
  is $res->headers->content_type,   'text/html',  'right "Content-Type" value';
  is $res->headers->content_length, 9000,         'right "Content-Length" value';
  is $res->headers->connection,     'keep-alive', 'right "Connection" value';
  is $res->body, '', 'no content';
};

subtest 'Parse full HTTP 1.1 response (204 No Content)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->content->on(body => sub { shift->headers->header('X-Body' => 'one') });
  $res->on(finish => sub { shift->headers->header('X-Finish' => 'two') });
  $res->parse("HTTP/1.1 204 No Content\x0d\x0a");
  $res->parse("Content-Type: text/html\x0d\x0a");
  $res->parse("Content-Length: 9001\x0d\x0a");
  $res->parse("Connection: keep-alive\x0d\x0a\x0d\x0a");
  ok $res->is_finished, 'response is finished';
  ok $res->is_empty,    'response is empty';
  ok $res->content->skip_body, 'body has been skipped';
  is $res->code,    204,          'right status';
  is $res->message, 'No Content', 'right message';
  is $res->version, '1.1',        'right version';
  is $res->headers->content_type,   'text/html',  'right "Content-Type" value';
  is $res->headers->content_length, 9001,         'right "Content-Length" value';
  is $res->headers->connection,     'keep-alive', 'right "Connection" value';
  is $res->headers->header('X-Body'),   'one', 'right "X-Body" value';
  is $res->headers->header('X-Finish'), 'two', 'right "X-Finish" value';
  is $res->body, '', 'no content';
};

subtest 'Parse HTTP 1.1 response (413 error in one big chunk)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 413 Request Entity Too Large\x0d\x0a"
      . "Connection: Close\x0d\x0a"
      . "Date: Tue, 09 Feb 2010 16:34:51 GMT\x0d\x0a"
      . "Server: Mojolicious (Perl)\x0d\x0a\x0d\x0a");
  ok !$res->is_finished, 'response is not finished';
  is $res->code,    413,                        'right status';
  is $res->message, 'Request Entity Too Large', 'right message';
  is $res->version, '1.1',                      'right version';
  is $res->headers->content_length, undef, 'right "Content-Length" value';
};

subtest 'Parse HTTP 1.1 chunked response (exceeding limit)' => sub {
  local $ENV{MOJO_MAX_BUFFER_SIZE} = 12;
  my $res = Mojo::Message::Response->new;
  is $res->content->max_buffer_size, 12, 'right size';
  $res->parse("HTTP/1.1 200 OK\x0d\x0a");
  $res->parse("Content-Type: text/plain\x0d\x0a");
  $res->parse("Transfer-Encoding: chunked\x0d\x0a\x0d\x0a");
  ok !$res->is_limit_exceeded, 'limit is not exceeded';
  $res->parse('a' x 1000);
  ok $res->is_finished, 'response is finished';
  ok $res->content->is_finished, 'content is finished';
  is $res->error->{message}, 'Maximum buffer size exceeded', 'right error';
  ok $res->is_limit_exceeded, 'limit is not exceeded';
  is $res->code,              200,   'right status';
  is $res->message,           'OK',  'right message';
  is $res->version,           '1.1', 'right version';
  is $res->headers->content_type, 'text/plain', 'right "Content-Type" value';
};

subtest 'Parse HTTP 1.1 multipart response (exceeding limit)' => sub {
  local $ENV{MOJO_MAX_BUFFER_SIZE} = 12;
  my $res = Mojo::Message::Response->new;
  is $res->content->max_buffer_size, 12, 'right size';
  $res->parse("HTTP/1.1 200 OK\x0d\x0a");
  $res->parse("Content-Length: 420\x0d\x0a");
  $res->parse('Content-Type: multipart/form-data; bo');
  $res->parse("undary=----------0xKhTmLbOuNdArY\x0d\x0a\x0d\x0a");
  ok !$res->content->is_limit_exceeded, 'limit is not exceeded';
  $res->parse('a' x 200);
  ok $res->content->is_limit_exceeded, 'limit is exceeded';
  ok $res->is_finished, 'response is finished';
  ok $res->content->is_finished, 'content is finished';
  is $res->error->{message}, 'Maximum buffer size exceeded', 'right error';
  is $res->code,    200,   'right status';
  is $res->message, 'OK',  'right message';
  is $res->version, '1.1', 'right version';
  is $res->headers->content_type, 'multipart/form-data; boundary=----------0xKhTmLbOuNdArY',
    'right "Content-Type" value';
};

subtest 'Parse HTTP 1.1 gzip compressed response (garbage bytes exceeding limit)' => sub {
  local $ENV{MOJO_MAX_BUFFER_SIZE} = 12;
  my $res = Mojo::Message::Response->new;
  is $res->content->max_buffer_size, 12, 'right size';
  $res->parse("HTTP/1.1 200 OK\x0d\x0a");
  $res->parse("Content-Length: 1000\x0d\x0a");
  $res->parse("Content-Encoding: gzip\x0d\x0a\x0d\x0a");
  $res->parse('a' x 5);
  ok !$res->content->is_limit_exceeded, 'limit is not exceeded';
  $res->parse('a' x 995);
  ok $res->content->is_limit_exceeded, 'limit is exceeded';
  ok $res->is_finished, 'response is finished';
  ok $res->content->is_finished, 'content is finished';
  is $res->error->{message}, 'Maximum buffer size exceeded', 'right error';
  is $res->code,    200,   'right status';
  is $res->message, 'OK',  'right message';
  is $res->version, '1.1', 'right version';
  is $res->body,    '',    'no content';
};

subtest 'Parse HTTP 1.1 chunked response' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 500 Internal Server Error\x0d\x0a");
  $res->parse("Content-Type: text/plain\x0d\x0a");
  $res->parse("Transfer-Encoding: chunked\x0d\x0a\x0d\x0a");
  $res->parse("4\x0d\x0a");
  $res->parse("abcd\x0d\x0a");
  $res->parse("9\x0d\x0a");
  $res->parse("abcdefghi\x0d\x0a");
  $res->parse("0\x0d\x0a\x0d\x0a");
  ok $res->is_finished, 'response is finished';
  is $res->code,        500,                     'right status';
  is $res->message,     'Internal Server Error', 'right message';
  is $res->version,     '1.1',                   'right version';
  is $res->headers->content_type,      'text/plain', 'right "Content-Type" value';
  is $res->headers->content_length,    13,           'right "Content-Length" value';
  is $res->headers->transfer_encoding, undef,        'no "Transfer-Encoding" value';
  is $res->body_size, 13, 'right size';
};

subtest 'Parse HTTP 1.1 multipart response' => sub {
  my $res = Mojo::Message::Response->new;
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
  ok $res->is_finished, 'response is finished';
  is $res->code,        200,   'right status';
  is $res->message,     'OK',  'right message';
  is $res->version,     '1.1', 'right version';
  is $res->headers->content_type, 'multipart/form-data; boundary=----------0xKhTmLbOuNdArY', 'right "Content-Type" value';
  ok !$res->content->parts->[0]->is_multipart, 'no multipart content';
  ok !$res->content->parts->[1]->is_multipart, 'no multipart content';
  ok !$res->content->parts->[2]->is_multipart, 'no multipart content';
  is $res->content->parts->[0]->asset->slurp, "hallo welt test123\n", 'right content';

  my $dir = tempdir;
  my $file = $dir->child('multipart.html');
  eval { $res->save_to($file) };
  like $@, qr/^Multipart content cannot be saved to files/, 'right error';
};

subtest 'Parse HTTP 1.1 chunked multipart response with leftovers (at once)' => sub {
  my $res = Mojo::Message::Response->new;
  my $multipart
    = "HTTP/1.1 200 OK\x0d\x0a"
    . "Transfer-Encoding: chunked\x0d\x0a"
    . 'Content-Type: multipart/form-data; bo'
    . "undary=----------0xKhTmLbOuNdArY\x0d\x0a\x0d\x0a"
    . "19f\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a"
    . "Content-Disposition: form-data; name=\"text1\"\x0d\x0a"
    . "\x0d\x0ahallo welt test123\n"
    . "\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a"
    . "Content-Disposition: form-data; name=\"text2\"\x0d\x0a"
    . "\x0d\x0a\x0d\x0a------------0xKhTmLbOuNdArY\x0d\x0a"
    . 'Content-Disposition: form-data; name="upload"; file'
    . "name=\"hello.pl\"\x0d\x0a"
    . "Content-Type: application/octet-stream\x0d\x0a\x0d\x0a"
    . "#!/usr/bin/perl\n\n"
    . "use strict;\n"
    . "use warnings;\n\n"
    . "print \"Hello World :)\\n\"\n"
    . "\x0d\x0a------------0xKhTmLbOuNdA"
    . "r\x0d\x0a3\x0d\x0aY--\x0d\x0a"
    . "0\x0d\x0a\x0d\x0a"
    . "HTTP/1.0 200 OK\x0d\x0a\x0d\x0a";
  $res->parse($multipart);
  ok $res->is_finished, 'response is finished';
  is $res->code,        200,   'right status';
  is $res->message,     'OK',  'right message';
  is $res->version,     '1.1', 'right version';
  is $res->headers->content_type, 'multipart/form-data; boundary=----------0xKhTmLbOuNdArY', 'right "Content-Type" value';
  is $res->headers->content_length,    418,   'right "Content-Length" value';
  is $res->headers->transfer_encoding, undef, 'no "Transfer-Encoding" value';
  is $res->body_size, 418, 'right size';
  ok !$res->content->parts->[0]->is_multipart, 'no multipart content';
  ok !$res->content->parts->[1]->is_multipart, 'no multipart content';
  ok !$res->content->parts->[2]->is_multipart, 'no multipart content';
  is $res->content->parts->[0]->asset->slurp, "hallo welt test123\n", 'right content';
  is $res->upload('upload')->filename, 'hello.pl', 'right filename';
  ok !$res->upload('upload')->asset->is_file, 'stored in memory';
  is $res->upload('upload')->asset->size, 69, 'right size';
  is $res->content->parts->[2]->headers->content_type, 'application/octet-stream', 'right "Content-Type" value';
  is $res->content->leftovers, "HTTP/1.0 200 OK\x0d\x0a\x0d\x0a", 'next response in leftovers';
};

subtest 'Parse HTTP 1.1 chunked multipart response (in multiple small chunks)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 200 OK\x0d\x0a");
  $res->parse("Transfer-Encoding: chunked\x0d\x0a");
  $res->parse('Content-Type: multipart/parallel; boundary=AAA; charset=utf-8');
  $res->parse("\x0d\x0a\x0d\x0a");
  $res->parse("7\x0d\x0a");
  $res->parse("--AAA\x0d\x0a");
  $res->parse("\x0d\x0a1a\x0d\x0a");
  $res->parse("Content-Type: image/jpeg\x0d\x0a");
  $res->parse("\x0d\x0a16\x0d\x0a");
  $res->parse("Content-ID: 600050\x0d\x0a\x0d\x0a");
  $res->parse("\x0d");
  $res->parse("\x0a6");
  $res->parse("\x0d\x0aabcd\x0d\x0a");
  $res->parse("\x0d\x0a7\x0d\x0a");
  $res->parse("--AAA\x0d\x0a");
  $res->parse("\x0d\x0a1a\x0d\x0a");
  $res->parse("Content-Type: image/jpeg\x0d\x0a");
  $res->parse("\x0d\x0a16\x0d\x0a");
  $res->parse("Content-ID: 600051\x0d\x0a\x0d\x0a");
  $res->parse("\x0d\x0a6\x0d\x0a");
  $res->parse("efgh\x0d\x0a");
  $res->parse("\x0d\x0a7\x0d\x0a");
  $res->parse('--AAA--');
  ok !$res->is_finished, 'response is not finished';
  $res->parse("\x0d\x0a0\x0d\x0a\x0d\x0a");
  ok $res->is_finished, 'response is finished';
  is $res->code,        200,   'right status';
  is $res->message,     'OK',  'right message';
  is $res->version,     '1.1', 'right version';
  is $res->headers->content_type,      'multipart/parallel; boundary=AAA; charset=utf-8', 'right "Content-Type" value';
  is $res->headers->content_length,    129,                                               'right "Content-Length" value';
  is $res->headers->transfer_encoding, undef,                                             'no "Transfer-Encoding" value';
  is $res->body_size, 129, 'right size';
  ok !$res->content->parts->[0]->is_multipart, 'no multipart content';
  ok !$res->content->parts->[1]->is_multipart, 'no multipart content';
  is $res->content->parts->[0]->asset->slurp,          'abcd',       'right content';
  is $res->content->parts->[0]->headers->content_type, 'image/jpeg', 'right "Content-Type" value';
  is $res->content->parts->[0]->headers->header('Content-ID'), 600050, 'right "Content-ID" value';
  is $res->content->parts->[1]->asset->slurp,          'efgh',       'right content';
  is $res->content->parts->[1]->headers->content_type, 'image/jpeg', 'right "Content-Type" value';
  is $res->content->parts->[1]->headers->header('Content-ID'), 600051, 'right "Content-ID" value';
};

subtest 'Parse HTTP 1.1 multipart response with missing boundary' => sub {
  my $res = Mojo::Message::Response->new;
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
  ok $res->is_finished, 'response is finished';
  is $res->code,        200,   'right status';
  is $res->message,     'OK',  'right message';
  is $res->version,     '1.1', 'right version';
  is $res->headers->content_type, 'multipart/form-data; bo', 'right "Content-Type" value';
  ok !$res->content->is_multipart, 'no multipart content';
  like $res->content->asset->slurp, qr/hallo welt/, 'right content';
};

subtest 'Parse HTTP 1.1 gzip compressed response' => sub {
  my $uncompressed = 'abc' x 1000;
  my $compressed   = gzip $uncompressed;
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 200 OK\x0d\x0a");
  $res->parse("Content-Type: text/plain\x0d\x0a");
  $res->parse("Content-Length: @{[length $compressed]}\x0d\x0a");
  $res->parse("Content-Encoding: GZip\x0d\x0a\x0d\x0a");
  ok $res->content->is_compressed, 'content is compressed';
  is $res->content->progress, 0, 'right progress';
  $res->parse(substr($compressed, 0, 1));
  is $res->content->progress, 1, 'right progress';
  $res->parse(substr($compressed, 1, length($compressed)));
  is $res->content->progress, length($compressed), 'right progress';
  ok !$res->content->is_compressed, 'content is not compressed anymore';
  ok $res->is_finished, 'response is finished';
  ok !$res->error, 'no error';
  is $res->code,    200,   'right status';
  is $res->message, 'OK',  'right message';
  is $res->version, '1.1', 'right version';
  is $res->headers->content_type,     'text/plain', 'right "Content-Type" value';
  is $res->headers->content_length,   length($uncompressed), 'right "Content-Length" value';
  is $res->headers->content_encoding, undef, 'no "Content-Encoding" value';
  is $res->body, $uncompressed, 'right content';
};

subtest 'Parse HTTP 1.1 chunked gzip compressed response' => sub {
  my $uncompressed = 'abc' x 1000;
  my $compressed   = undef;
  $compressed      = gzip $uncompressed;
  my $res          = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 200 OK\x0d\x0a");
  $res->parse("Content-Type: text/plain\x0d\x0a");
  $res->parse("Content-Encoding: gzip\x0d\x0a");
  $res->parse("Transfer-Encoding: chunked\x0d\x0a\x0d\x0a");
  ok $res->content->is_chunked,    'content is chunked';
  ok $res->content->is_compressed, 'content is compressed';
  $res->parse("1\x0d\x0a");
  $res->parse(substr($compressed, 0, 1));
  $res->parse("\x0d\x0a");
  $res->parse(sprintf('%x', length($compressed) - 1));
  $res->parse("\x0d\x0a");
  $res->parse(substr($compressed, 1, length($compressed) - 1));
  $res->parse("\x0d\x0a");
  $res->parse("0\x0d\x0a\x0d\x0a");
  ok !$res->content->is_chunked,    'content is not chunked anymore';
  ok !$res->content->is_compressed, 'content is not compressed anymore';
  ok $res->is_finished, 'response is finished';
  ok !$res->error, 'no error';
  is $res->code,    200,   'right status';
  is $res->message, 'OK',  'right message';
  is $res->version, '1.1', 'right version';
  is $res->headers->content_type,      'text/plain', 'right "Content-Type" value';
  is $res->headers->content_length,    length($uncompressed), 'right "Content-Length" value';
  is $res->headers->transfer_encoding, undef, 'no "Transfer-Encoding" value';
  is $res->headers->content_encoding,  undef, 'no "Content-Encoding" value';
  is $res->body, $uncompressed, 'right content';
};

subtest 'Build HTTP 1.1 response start-line with minimal headers' => sub {
  my $res = Mojo::Message::Response->new;
  $res->code(404);
  $res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
  $res = Mojo::Message::Response->new->parse($res->to_string);
  ok $res->is_finished, 'response is finished';
  is $res->code,        '404',       'right status';
  is $res->message,     'Not Found', 'right message';
  is $res->version,     '1.1',       'right version';
  is $res->headers->date,           'Sun, 17 Aug 2008 16:27:35 GMT', 'right "Date" value';
  is $res->headers->content_length, 0,                               'right "Content-Length" value';
};

subtest 'Build HTTP 1.1 response start-line with minimal headers (strange message)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->code(404);
  $res->message('Looks-0k!@ ;\':" #$%^<>,.\\o/ &*()');
  $res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
  $res = Mojo::Message::Response->new->parse($res->to_string);
  ok $res->is_finished, 'response is finished';
  is $res->code,        '404',                                'right status';
  is $res->message,     'Looks-0k!@ ;\':" #$%^<>,.\\o/ &*()', 'right message';
  is $res->version,     '1.1',                                'right version';
  is $res->headers->date,           'Sun, 17 Aug 2008 16:27:35 GMT', 'right "Date" value';
  is $res->headers->content_length, 0,                               'right "Content-Length" value';
};

subtest 'Build HTTP 1.1 response start-line and header' => sub {
  my $res = Mojo::Message::Response->new;
  $res->code(200);
  $res->headers->connection('keep-alive');
  $res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
  $res = Mojo::Message::Response->new->parse($res->to_string);
  ok $res->is_finished, 'response is finished';
  is $res->code,        '200', 'right status';
  is $res->message,     'OK',  'right message';
  is $res->version,     '1.1', 'right version';
  is $res->headers->connection, 'keep-alive',                    'right "Connection" value';
  is $res->headers->date,       'Sun, 17 Aug 2008 16:27:35 GMT', 'right "Date" value';
};

subtest 'Build full HTTP 1.1 response' => sub {
  my $res = Mojo::Message::Response->new;
  $res->code(200);
  $res->headers->connection('keep-alive');
  $res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
  $res->body("Hello World!\n");
  $res = Mojo::Message::Response->new->parse($res->to_string);
  ok $res->is_finished, 'response is finished';
  is $res->code,        '200', 'right status';
  is $res->message,     'OK',  'right message';
  is $res->version,     '1.1', 'right version';
  is $res->headers->connection,     'keep-alive',                    'right "Connection" value';
  is $res->headers->date,           'Sun, 17 Aug 2008 16:27:35 GMT', 'right "Date" value';
  is $res->headers->content_length, '13',                            'right "Content-Length" value';
  is $res->body, "Hello World!\n", 'right content';
};

subtest 'Build HTTP 1.1 response parts with progress' => sub {
  my $res = Mojo::Message::Response->new;
  my ($finished, $state, $progress);
  $res->on(finish => sub { $finished = shift->is_finished });
  $res->on(
    progress => sub {
      my ($res, $part, $offset) = @_;
      $state = $part;
      $progress += $offset;
    }
  );
  $res->code(200);
  $res->headers->connection('keep-alive');
  $res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
  $res->body("Hello World!\n");
  ok !$state,    'no state';
  ok !$progress, 'no progress';
  ok !$finished, 'not finished';
  ok $res->build_start_line, 'built start-line';
  is $state, 'start_line', 'made progress on start_line';
  ok $progress, 'made progress';
  $progress = 0;
  ok !$finished, 'not finished';
  ok $res->build_headers, 'built headers';
  is $state, 'headers', 'made progress on headers';
  ok $progress, 'made progress';
  $progress = 0;
  ok !$finished, 'not finished';
  ok $res->build_body, 'built body';
  is $state,    'body', 'made progress on headers';
  ok $progress, 'made progress';
  ok $finished, 'finished';
};

subtest 'Build HTTP 1.1 response with dynamic content' => sub {
  my $res = Mojo::Message::Response->new;
  $res->code(200);
  $res->content->write_chunk(
    'Hello ' => sub {
      shift->write_chunk(undef, sub { shift->write_chunk('World!')->write_chunk('') });
    }
  );
  ok $res->content->is_dynamic, 'dynamic content';
  $res = Mojo::Message::Response->new->parse($res->to_string);
  ok !$res->content->is_dynamic, 'no dynamic content';
  ok $res->is_finished, 'response is finished';
  is $res->code,        200,   'right status';
  is $res->message,     'OK',  'right message';
  is $res->version,     '1.1', 'right version';
  is $res->headers->content_length, '12', 'right "Content-Length" value';
  is $res->body, 'Hello World!', 'right content';
};

subtest 'Build HTTP 1.1 multipart response' => sub {
  my $res = Mojo::Message::Response->new;
  $res->content(Mojo::Content::MultiPart->new);
  $res->code(200);
  $res->headers->content_type('multipart/mixed; boundary=7am1X');
  $res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
  push @{$res->content->parts}, Mojo::Content::Single->new(asset => Mojo::Asset::File->new);
  $res->content->parts->[-1]->asset->add_chunk('Hallo Welt lalalalalala!');
  my $content = Mojo::Content::Single->new;
  $content->asset->add_chunk("lala\nfoobar\nperl rocks\n");
  $content->headers->content_type('text/plain');
  push @{$res->content->parts}, $content;
  $res = Mojo::Message::Response->new->parse($res->to_string);
  ok $res->is_finished, 'response is finished';
  is $res->code,        200,   'right status';
  is $res->message,     'OK',  'right message';
  is $res->version,     '1.1', 'right version';
  is $res->headers->date,           'Sun, 17 Aug 2008 16:27:35 GMT',   'right "Date" value';
  is $res->headers->content_length, '110',                             'right "Content-Length" value';
  is $res->headers->content_type,   'multipart/mixed; boundary=7am1X', 'right "Content-Type" value';
  is $res->content->parts->[0]->asset->slurp,          'Hallo Welt lalalalalala!',   'right content';
  is $res->content->parts->[1]->headers->content_type, 'text/plain',                 'right "Content-Type" value';
  is $res->content->parts->[1]->asset->slurp,          "lala\nfoobar\nperl rocks\n", 'right content';
};

subtest 'Parse response with cookie' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.0 200 OK\x0d\x0a");
  $res->parse("Content-Type: text/plain\x0d\x0a");
  $res->parse("Content-Length: 27\x0d\x0a");
  $res->parse("Set-Cookie: foo=bar; path=/test\x0d\x0a\x0d\x0a");
  $res->parse("Hello World!\n1234\nlalalala\n");
  ok $res->is_finished, 'response is finished';
  is $res->code,        200,   'right status';
  is $res->message,     'OK',  'right message';
  is $res->version,     '1.0', 'right version';
  is $res->headers->content_type,   'text/plain',          'right "Content-Type" value';
  is $res->headers->content_length, 27,                    'right "Content-Length" value';
  is $res->headers->set_cookie,     'foo=bar; path=/test', 'right "Set-Cookie" value';
  my $cookies = $res->cookies;
  is $cookies->[0]->name,  'foo',   'right name';
  is $cookies->[0]->value, 'bar',   'right value';
  is $cookies->[0]->path,  '/test', 'right path';
  is $res->cookie('foo')->value, 'bar',   'right value';
  is $res->cookie('foo')->path,  '/test', 'right path';
};

subtest 'Parse WebSocket handshake response' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 101 Switching Protocols\x0d\x0a");
  $res->parse("Upgrade: websocket\x0d\x0a");
  $res->parse("Connection: Upgrade\x0d\x0a");
  $res->parse("Sec-WebSocket-Accept: abcdef=\x0d\x0a");
  $res->parse("Sec-WebSocket-Protocol: sample\x0d\x0a\x0d\x0a");
  ok $res->is_finished, 'response is finished';
  ok $res->is_empty,    'response is empty';
  ok $res->content->skip_body, 'body has been skipped';
  is $res->code,    101,                   'right status';
  is $res->message, 'Switching Protocols', 'right message';
  is $res->version, '1.1',                 'right version';
  is $res->headers->upgrade,                'websocket', 'right "Upgrade" value';
  is $res->headers->connection,             'Upgrade',   'right "Connection" value';
  is $res->headers->sec_websocket_accept,   'abcdef=',   'right "Sec-WebSocket-Accept" value';
  is $res->headers->sec_websocket_protocol, 'sample',    'right "Sec-WebSocket-Protocol" value';
  is $res->body, '', 'no content';
  ok !defined $res->headers->content_length, '"Content-Length" does not exist';
};

subtest 'Parse WebSocket handshake response (with frame)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 101 Switching Protocols\x0d\x0a");
  $res->parse("Upgrade: websocket\x0d\x0a");
  $res->parse("Connection: Upgrade\x0d\x0a");
  $res->parse("Sec-WebSocket-Accept: abcdef=\x0d\x0a");
  $res->parse("Sec-WebSocket-Protocol: sample\x0d\x0a");
  $res->parse("\x0d\x0a\x81\x08\x77\x68\x61\x74\x65\x76\x65\x72");
  ok $res->is_finished, 'response is finished';
  ok $res->is_empty,    'response is empty';
  ok $res->content->skip_body, 'body has been skipped';
  is $res->code,    101,                   'right status';
  is $res->message, 'Switching Protocols', 'right message';
  is $res->version, '1.1',                 'right version';
  is $res->headers->upgrade,                'websocket', 'right "Upgrade" value';
  is $res->headers->connection,             'Upgrade',   'right "Connection" value';
  is $res->headers->sec_websocket_accept,   'abcdef=',   'right "Sec-WebSocket-Accept" value';
  is $res->headers->sec_websocket_protocol, 'sample',    'right "Sec-WebSocket-Protocol" value';
  is $res->body, '', 'no content';
  is $res->content->leftovers, "\x81\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'frame in leftovers';
  ok !defined $res->headers->content_length, '"Content-Length" does not exist';
};

subtest 'Build WebSocket handshake response' => sub {
  my $res = Mojo::Message::Response->new;
  $res->code(101);
  $res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
  $res->headers->upgrade('websocket');
  $res->headers->connection('Upgrade');
  $res->headers->sec_websocket_accept('abcdef=');
  $res->headers->sec_websocket_protocol('sample');
  $res = Mojo::Message::Response->new->parse($res->to_string);
  ok $res->is_finished, 'response is finished';
  is $res->code,        '101',                 'right status';
  is $res->message,     'Switching Protocols', 'right message';
  is $res->version,     '1.1',                 'right version';
  is $res->headers->connection, 'Upgrade',                       'right "Connection" value';
  is $res->headers->date,       'Sun, 17 Aug 2008 16:27:35 GMT', 'right "Date" value';
  ok !defined $res->headers->content_length, '"Content-Length" does not exist';
  is $res->headers->upgrade,                'websocket', 'right "Upgrade" value';
  is $res->headers->sec_websocket_accept,   'abcdef=',   'right "Sec-WebSocket-Accept" value';
  is $res->headers->sec_websocket_protocol, 'sample',    'right "Sec-WebSocket-Protocol" value';
  is $res->body, '', 'no content';
  ok !defined $res->headers->content_length, '"Content-Length" does not exist';
};

subtest 'Build and parse HTTP 1.1 response with 3 cookies' => sub {
  my $res = Mojo::Message::Response->new;
  $res->code(404);
  $res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
  $res->cookies({name => 'foo', value => 'bar',  path => '/foobar'}, {name => 'bar', value => 'baz', path => '/test/23'});
  $res->cookies({name => 'baz', value => 'yada', path => '/foobar'});
  ok !!$res->to_string, 'message built';
  my $res2 = Mojo::Message::Response->new;
  $res2->parse($res->to_string);
  ok $res2->is_finished, 'response is finished';
  is $res2->code,        404,   'right status';
  is $res2->version,     '1.1', 'right version';
  is $res2->headers->content_length, 0, 'right "Content-Length" value';
  ok defined $res2->cookie('foo'),   'cookie "foo" exists';
  ok defined $res2->cookie('bar'),   'cookie "bar" exists';
  ok defined $res2->cookie('baz'),   'cookie "baz" exists';
  ok !defined $res2->cookie('yada'), 'cookie "yada" does not exist';
  is $res2->cookie('foo')->path,  '/foobar',  'right path';
  is $res2->cookie('foo')->value, 'bar',      'right value';
  is $res2->cookie('bar')->path,  '/test/23', 'right path';
  is $res2->cookie('bar')->value, 'baz',      'right value';
  is $res2->cookie('baz')->path,  '/foobar',  'right path';
  is $res2->cookie('baz')->value, 'yada',     'right value';
};

subtest 'Build chunked response body' => sub {
  my $res = Mojo::Message::Response->new;
  $res->code(200);
  my $invocant;
  $res->content->write_chunk('hello!' => sub { $invocant = shift });
  $res->content->write_chunk('hello world!')->write_chunk('');
  ok $res->content->is_chunked, 'chunked content';
  ok $res->content->is_dynamic, 'dynamic content';
  is $res->build_body, "6\x0d\x0ahello!\x0d\x0ac\x0d\x0ahello world!\x0d\x0a0\x0d\x0a\x0d\x0a", 'right format';
  isa_ok $invocant, 'Mojo::Content::Single', 'right invocant';
};

subtest 'Build dynamic response body' => sub {
  my $res = Mojo::Message::Response->new;
  $res->code(200);
  my $invocant;
  $res->content->write('hello!' => sub { $invocant = shift });
  $res->content->write('hello world!')->write('');
  ok !$res->content->is_chunked, 'no chunked content';
  ok $res->content->is_dynamic, 'dynamic content';
  is $res->build_body, "hello!hello world!", 'right format';
  isa_ok $invocant, 'Mojo::Content::Single', 'right invocant';
};

subtest 'Build response with callback (make sure it is called)' => sub {
  my $res = Mojo::Message::Response->new;
  $res->code(200);
  $res->headers->content_length(10);
  $res->content->write('lala' => sub { die "Body callback was called properly\n" });
  $res->get_body_chunk(0);
  eval { $res->get_body_chunk(3) };
  is $@, "Body callback was called properly\n", 'right error';
};

subtest 'Build response with callback (consistency calls)' => sub {
  my $res = Mojo::Message::Response->new;
  my $body = 'I is here';
  $res->headers->content_length(length($body));
  my $cb = sub { shift->write(substr($body, pop, 1), __SUB__) };
  $res->content->write('' => $cb);
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
  ok $res->content->is_dynamic, 'dynamic content';
  is $count, length($body), 'right length';
  is $full, $body, 'right content';
};

subtest 'Build response with callback (no Content-Length header)' => sub {
  my $res  = Mojo::Message::Response->new;
  my $body = 'I is here';
  my $cb;
  $cb   = sub { shift->write(substr($body, pop, 1), $cb) };
  $res->content->write('' => $cb);
  $res->fix_headers;
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
  is $res->headers->connection, 'close', 'right "Connection" value';
  ok $res->content->is_dynamic, 'dynamic content';
  is $count, length($body), 'right length';
  is $full, $body, 'right content';
};

subtest 'Body' => sub {
  my $res = Mojo::Message::Response->new;
  $res->body('hi there!');
  ok !$res->content->asset->is_file,      'stored in memory';
  ok !$res->content->asset->auto_upgrade, 'no upgrade';
  is $res->body, 'hi there!', 'right content';
  $res->body('');
  is $res->body, '', 'no content';
  $res->body('hi there!');
  is $res->body, 'hi there!', 'right content';
  $res->body(0);
  is $res->body, 0, 'right content';
  is $res->body('hello!')->body, 'hello!', 'right content';
  $res->content(Mojo::Content::MultiPart->new);
  $res->body('hi!');
  is $res->body, 'hi!', 'right content';
};

subtest 'Text' => sub {
  my $res = Mojo::Message::Response->new;
  my $snowman = encode 'UTF-8', '☃';
  is $res->body($snowman)->text, '☃', 'right content';
  is $res->body($snowman)->dom->text, '☃', 'right text';
  $res = Mojo::Message::Response->new;
  my $yatta = encode 'shift_jis', 'やった';
  is $res->body($yatta)->text, $yatta, 'right content';
  $res->headers->content_type('text/plain;charset=shift_jis');
  is $res->body($yatta)->text, 'やった', 'right content';
  is $res->body($yatta)->dom->text, 'やった', 'right text';
};

subtest 'Body exceeding memory limit (no upgrade)' => sub {
  local $ENV{MOJO_MAX_MEMORY_SIZE} = 8;
  my $res = Mojo::Message::Response->new;
  $res->body('hi there!');
  is $res->body, 'hi there!', 'right content';
  is $res->content->asset->max_memory_size, 8, 'right size';
  is $res->content->asset->size,            9, 'right size';
  ok !$res->content->asset->is_file, 'stored in memory';
};

subtest 'Parse response and extract JSON data' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 200 OK\x0a");
  $res->parse("Content-Type: application/json\x0a");
  $res->parse("Content-Length: 27\x0a\x0a");
  $res->parse(encode_json({foo => 'bar', baz => [1, 2, 3]}));
  ok $res->is_finished, 'response is finished';
  is $res->code,        200,   'right status';
  is $res->message,     'OK',  'right message';
  is $res->version,     '1.1', 'right version';
  is_deeply $res->json, {foo => 'bar', baz => [1, 2, 3]}, 'right JSON data';
  is $res->json('/foo'),        'bar', 'right result';
  is $res->json('/baz/1'),      2,     'right result';
  is_deeply $res->json('/baz'), [1, 2, 3], 'right result';
  $res->json->{baz}[1] = 4;
  is_deeply $res->json('/baz'), [1, 4, 3], 'right result';
};

subtest 'Parse response and extract HTML' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.1 200 OK\x0a");
  $res->parse("Content-Type: text/html\x0a");
  $res->parse("Content-Length: 51\x0a\x0a");
  $res->parse('<p>foo<a href="/">bar</a><a href="/baz">baz</a></p>');
  ok $res->is_finished, 'response is finished';
  is $res->code,        200,   'right status';
  is $res->message,     'OK',  'right message';
  is $res->version,     '1.1', 'right version';
  is $res->dom->at('p')->text,     'foo', 'right value';
  is $res->dom->at('p > a')->text, 'bar', 'right value';
  is $res->dom('p')->first->text, 'foo', 'right value';
  is_deeply $res->dom('p > a')->map('text')->to_array, [qw(bar baz)], 'right values';
  my @text = $res->dom('a')->map(content => 'yada')->first->root->find('p > a')->map('text')->each;
  is_deeply \@text, [qw(yada yada)], 'right values';
  is_deeply $res->dom('p > a')->map('text')->to_array, [qw(yada yada)], 'right values';
  @text = $res->dom->find('a')->map(content => 'test')->first->root->find('p > a')->map('text')->each;
  is_deeply \@text, [qw(test test)], 'right values';
  is_deeply $res->dom->find('p > a')->map('text')->to_array, [qw(test test)], 'right values';

  my $dir = tempdir;
  my $file = $dir->child('single.html');
  is $res->save_to($file)->body, '<p>foo<a href="/">bar</a><a href="/baz">baz</a></p>', 'right content';
  is $file->slurp, '<p>foo<a href="/">bar</a><a href="/baz">baz</a></p>', 'right content';
};

subtest 'Build DOM from response with charset' => sub {
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.0 200 OK\x0a");
  $res->parse("Content-Type: application/atom+xml; charset=UTF-8; type=feed\x0a");
  $res->parse("\x0a");
  $res->body('<p>foo <a href="/">bar</a><a href="/baz">baz</a></p>');
  ok !$res->is_finished, 'response is not finished';
  is $res->headers->content_type, 'application/atom+xml; charset=UTF-8; type=feed', 'right "Content-Type" value';
  ok $res->dom, 'dom built';
  my $count = 0;
  $res->dom('a')->each(sub { $count++ });
  is $count, 2, 'all anchors found';
};

done_testing();
