#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 224;

use Mojo::Filter::Chunked;
use Mojo::Headers;

# When will I learn?
# The answer to life's problems aren't at the bottom of a bottle,
# they're on TV!
use_ok('Mojo::File');
use_ok('Mojo::Content');
use_ok('Mojo::Content::MultiPart');
use_ok('Mojo::Cookie::Request');
use_ok('Mojo::Cookie::Response');
use_ok('Mojo::Headers');
use_ok('Mojo::Message');
use_ok('Mojo::Message::Request');
use_ok('Mojo::Message::Response');

# Parse HTTP 1.1 start line, no headers and body
my $req = Mojo::Message::Request->new;
$req->parse("GET / HTTP/1.1\x0d\x0a\x0d\x0a");
is($req->state,         'done');
is($req->method,        'GET');
is($req->major_version, 1);
is($req->minor_version, 1);
is($req->url,           '/');

# Parse HTTP 1.0 start line and headers, no body
$req = Mojo::Message::Request->new;
$req->parse("GET /foo/bar/baz.html HTTP/1.0\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a");
$req->parse("Content-Length: 0\x0d\x0a\x0d\x0a");
is($req->state,                   'done');
is($req->method,                  'GET');
is($req->major_version,           1);
is($req->minor_version,           0);
is($req->url,                     '/foo/bar/baz.html');
is($req->headers->content_type,   'text/plain');
is($req->headers->content_length, 0);

# Parse full HTTP 1.0 request
$req = Mojo::Message::Request->new;
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: text/');
$req->parse("plain\x0d\x0aContent-Length: 27\x0d\x0a\x0d\x0aHell");
$req->parse("o World!\n1234\nlalalala\n");
is($req->state,                   'done');
is($req->method,                  'GET');
is($req->major_version,           1);
is($req->minor_version,           0);
is($req->url,                     '/foo/bar/baz.html?foo=13#23');
is($req->headers->content_type,   'text/plain');
is($req->headers->content_length, 27);

# Parse HTTP 0.9 request
$req = Mojo::Message::Request->new;
$req->parse("GET /\x0d\x0a\x0d\x0a");
is($req->state,         'done');
is($req->method,        'GET');
is($req->major_version, 0);
is($req->minor_version, 9);
is($req->url,           '/');

# Parse HTTP 1.1 chunked request
$req = Mojo::Message::Request->new;
$req->parse("POST /foo/bar/baz.html?foo=13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Type: text/plain\x0d\x0a");
$req->parse("Transfer-Encoding: chunked\x0d\x0a\x0d\x0a");
$req->parse("4\x0d\x0a");
$req->parse("abcd\x0d\x0a");
$req->parse("9\x0d\x0a");
$req->parse("abcdefghi\x0d\x0a");
$req->parse("0\x0d\x0a");
is($req->state,                 'done');
is($req->method,                'POST');
is($req->major_version,         1);
is($req->minor_version,         1);
is($req->url,                   '/foo/bar/baz.html?foo=13#23');
is($req->headers->content_type, 'text/plain');
is($req->content->file->length, 13);
is($req->content->file->slurp,  'abcdabcdefghi');

# Parse HTTP 1.1 "x-application-urlencoded"
$req = Mojo::Message::Request->new;
$req->parse("POST /foo/bar/baz.html?foo=13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 26\x0d\x0a");
$req->parse("Content-Type: x-application-urlencoded\x0d\x0a\x0d\x0a");
$req->parse('foo=bar& tset=23+;&foo=bar');
is($req->state,                 'done');
is($req->method,                'POST');
is($req->major_version,         1);
is($req->minor_version,         1);
is($req->url,                   '/foo/bar/baz.html?foo=13#23');
is($req->headers->content_type, 'x-application-urlencoded');
is($req->content->file->length, 26);
is($req->content->file->slurp,  'foo=bar& tset=23+;&foo=bar');
is($req->body_params,           'foo=bar&+tset=23+&foo=bar');
is_deeply($req->body_params->to_hash->{foo}, [qw/bar bar/]);
is_deeply($req->body_params->to_hash->{' tset'}, '23 ');
is_deeply($req->params->to_hash->{foo}, [qw/bar bar 13/]);

# Parse HTTP 1.1 "application/x-www-form-urlencoded"
$req = Mojo::Message::Request->new;
$req->parse("POST /foo/bar/baz.html?foo=13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 26\x0d\x0a");
$req->parse("Content-Type: application/x-www-form-urlencoded\x0d\x0a");
$req->parse("\x0d\x0afoo=bar&+tset=23+;&foo=bar");
is($req->state,                 'done');
is($req->method,                'POST');
is($req->major_version,         1);
is($req->minor_version,         1);
is($req->url,                   '/foo/bar/baz.html?foo=13#23');
is($req->headers->content_type, 'application/x-www-form-urlencoded');
is($req->content->file->length, 26);
is($req->content->file->slurp,  'foo=bar&+tset=23+;&foo=bar');
is($req->body_params,           'foo=bar&+tset=23+&foo=bar');
is_deeply($req->body_params->to_hash->{foo}, [qw/bar bar/]);
is_deeply($req->body_params->to_hash->{' tset'}, '23 ');
is_deeply($req->params->to_hash->{foo}, [qw/bar bar 13/]);
is_deeply([$req->param('foo')], [qw/bar bar 13/]);
is_deeply($req->param(' tset'), '23 ');
$req->param('set', 'single');
is_deeply($req->param('set'), 'single', 'setting single param works');
$req->param('multi', 1, 2, 3);
is_deeply([$req->param('multi')],
    [qw/1 2 3/], 'setting multiple value param works');
is($req->param('test23'), undef);

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
is($req->state,                         'done');
is($req->method,                        'POST');
is($req->major_version,                 1);
is($req->minor_version,                 1);
is($req->url,                           '/foo/bar/baz.html?foo=13&bar=23#23');
is($req->query_params,                  'foo=13&bar=23');
is($req->headers->content_type,         'text/plain');
is($req->headers->header('X-Trailer1'), 'test');
is($req->headers->header('X-Trailer2'), '123');
is($req->content->file->length,         13);
is($req->content->file->slurp,          'abcdabcdefghi');

# Parse HTTP 1.1 multipart request
$req = Mojo::Message::Request->new;
$req->parse("GET /foo/bar/baz.html?foo13#23 HTTP/1.1\x0d\x0a");
$req->parse("Content-Length: 814\x0d\x0a");
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
is($req->state,         'done');
is($req->method,        'GET');
is($req->major_version, 1);
is($req->minor_version, 1);
is($req->url,           '/foo/bar/baz.html?foo13#23');
is($req->query_params,  'foo13');
like($req->headers->content_type, qr/multipart\/form-data/);
is(ref $req->content->parts->[0],          'Mojo::Content');
is(ref $req->content->parts->[1],          'Mojo::Content');
is(ref $req->content->parts->[2],          'Mojo::Content');
is($req->content->parts->[0]->file->slurp, "hallo welt test123\n");
is_deeply($req->body_params->to_hash->{text1}, "hallo welt test123\n");
is_deeply($req->body_params->to_hash->{text2}, '');
is($req->upload('upload')->filename,     'hello.pl');
is(ref $req->upload('upload')->file,     'Mojo::File');
is($req->upload('upload')->file->length, 69);
ok($req->upload('upload')->copy_to('MOJO_TMP.txt'));
is((unlink 'MOJO_TMP.txt'), 1);

# Build minimal HTTP 1.1 request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/');
is($req->build,
        "GET / HTTP/1.1\x0d\x0a"
      . "Host: 127.0.0.1\x0d\x0a"
      . "Content-Length: 0\x0d\x0a\x0d\x0a");

# Build HTTP 1.1 start line and header
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
is($req->build,
        "GET /foo/bar HTTP/1.1\x0d\x0a"
      . "Expect: 100-continue\x0d\x0a"
      . "Host: 127.0.0.1\x0d\x0a"
      . "Content-Length: 0\x0d\x0a\x0d\x0a");

# Build full HTTP 1.1 request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
is($req->build,
        "GET /foo/bar HTTP/1.1\x0d\x0a"
      . "Expect: 100-continue\x0d\x0a"
      . "Host: 127.0.0.1\x0d\x0a"
      . "Content-Length: 13\x0d\x0a\x0d\x0a"
      . "Hello World!\n");

# Build full HTTP 1.1 proxy request
my $backup = $ENV{HTTP_PROXY} || '';
$ENV{HTTP_PROXY} = 'http://foo:bar@127.0.0.1:8080';
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
is($req->build,
        "GET http://127.0.0.1/foo/bar HTTP/1.1\x0d\x0a"
      . "Expect: 100-continue\x0d\x0a"
      . "Host: 127.0.0.1\x0d\x0a"
      . "Proxy-Authorization: Basic Zm9vOmJhcg==\x0d\x0a"
      . "Content-Length: 13\x0d\x0a\x0d\x0a"
      . "Hello World!\n");
$ENV{HTTP_PROXY} = $backup;

# Build HTTP 1.1 multipart request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->content(Mojo::Content::MultiPart->new);
$req->headers->content_type('multipart/mixed; boundary=7am1X');
push @{$req->content->parts}, Mojo::Content->new;
$req->content->parts->[-1]->file->add_chunk('Hallo Welt lalalala!');
my $content = Mojo::Content->new;
$content->file->add_chunk("lala\nfoobar\nperl rocks\n");
$content->headers->content_type('text/plain');
push @{$req->content->parts}, $content;
is($req->build,
        "GET /foo/bar HTTP/1.1\x0d\x0a"
      . "Host: 127.0.0.1\x0d\x0a"
      . "Content-Length: 106\x0d\x0a"
      . "Content-Type: multipart/mixed; boundary=7am1X\x0d\x0a\x0d\x0a"
      . "\x0d\x0a--7am1X\x0d\x0a\x0d\x0a"
      . "Hallo Welt lalalala!"
      . "\x0d\x0a--7am1X\x0d\x0a"
      . "Content-Type: text/plain\x0d\x0a\x0d\x0a"
      . "lala\nfoobar\nperl rocks\n"
      . "\x0d\x0a--7am1X--");

# Build HTTP 1.1 chunked request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1:8080/foo/bar');
$req->headers->transfer_encoding('chunked');
my $counter  = 1;
my $chunked  = Mojo::Filter::Chunked->new;
my $counter2 = 0;
$req->builder_progress_cb(sub { $counter2++ });
$req->build_body_cb(
    sub {
        my $self  = shift;
        my $chunk = '';
        $chunk = "hello world!"      if $counter == 1;
        $chunk = "hello world2!\n\n" if $counter == 2;
        $counter++;
        return $chunked->build($chunk);
    }
);
is($req->build,
        "GET /foo/bar HTTP/1.1\x0d\x0a"
      . "Transfer-Encoding: chunked\x0d\x0a"
      . "Host: 127.0.0.1:8080\x0d\x0a\x0d\x0a"
      . "c\x0d\x0a"
      . "hello world!"
      . "\x0d\x0af\x0d\x0a"
      . "hello world2!\n\n"
      . "\x0d\x0a0\x0d\x0a");
is($counter2, 6);

# Build HTTP 1.1 chunked request with trailing headers
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->transfer_encoding('chunked');
$req->headers->trailer('X-Test; X-Test2');
$counter = 1;
$chunked = Mojo::Filter::Chunked->new;
$req->build_body_cb(
    sub {
        my $self  = shift;
        my $chunk = Mojo::Headers->new;
        $chunk->header('X-Test',  'test');
        $chunk->header('X-Test2', '123');
        $chunk = "hello world!"      if $counter == 1;
        $chunk = "hello world2!\n\n" if $counter == 2;
        $counter++;
        return $chunked->build($chunk);
    }
);
is($req->build,
        "GET /foo/bar HTTP/1.1\x0d\x0a"
      . "Trailer: X-Test; X-Test2\x0d\x0a"
      . "Transfer-Encoding: chunked\x0d\x0a"
      . "Host: 127.0.0.1\x0d\x0a\x0d\x0a"
      . "c\x0d\x0a"
      . "hello world!"
      . "\x0d\x0af\x0d\x0a"
      . "hello world2!\n\n"
      . "\x0d\x0a0\x0d\x0a"
      . "X-Test: test\x0d\x0a"
      . "X-Test2: 123\x0d\x0a\x0d\x0a");

# Status code and message
my $res = Mojo::Message::Response->new;
is($res->code,            undef);
is($res->default_message, 'OK');
is($res->message,         undef);
$res->message('Test');
is($res->message, 'Test');
$res->code(500);
is($res->code,            500);
is($res->message,         'Test');
is($res->default_message, 'Internal Server Error');
$res = Mojo::Message::Response->new;
is($res->code(400)->default_message, 'Bad Request');

# Parse HTTP 1.1 response start line, no headers and body
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.1 200 OK\x0d\x0a\x0d\x0a");
is($res->state,         'done');
is($res->code,          200);
is($res->message,       'OK');
is($res->major_version, 1);
is($res->minor_version, 1);

# Parse HTTP 0.9 response
$res = Mojo::Message::Response->new;
$res->parse("HTT... this is just a document and valid HTTP 0.9\n\n");
is($res->state,         'done');
is($res->major_version, 0);
is($res->minor_version, 9);
is($res->body, "HTT... this is just a document and valid HTTP 0.9\n\n");

# Parse HTTP 1.0 response start line and headers but no body
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.0 404 Damn it\x0d\x0a");
$res->parse("Content-Type: text/plain\x0d\x0a");
$res->parse("Content-Length: 0\x0d\x0a\x0d\x0a");
is($res->state,                   'done');
is($res->code,                    404);
is($res->message,                 'Damn it');
is($res->major_version,           1);
is($res->minor_version,           0);
is($res->headers->content_type,   'text/plain');
is($res->headers->content_length, 0);

# Parse full HTTP 1.0 response
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.0 500 Internal Server Error\x0d\x0a");
$res->parse("Content-Type: text/plain\x0d\x0a");
$res->parse("Content-Length: 27\x0d\x0a\x0d\x0a");
$res->parse("Hello World!\n1234\nlalalala\n");
is($res->state,                   'done');
is($res->code,                    500);
is($res->message,                 'Internal Server Error');
is($res->major_version,           1);
is($res->minor_version,           0);
is($res->headers->content_type,   'text/plain');
is($res->headers->content_length, 27);

# Parse HTTP 1.1 chunked response
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.1 500 Internal Server Error\x0d\x0a");
$res->parse("Content-Type: text/plain\x0d\x0a");
$res->parse("Transfer-Encoding: chunked\x0d\x0a\x0d\x0a");
$res->parse("4\x0d\x0a");
$res->parse("abcd\x0d\x0a");
$res->parse("9\x0d\x0a");
$res->parse("abcdefghi\x0d\x0a");
$res->parse("0\x0d\x0a");
is($res->state,                 'done');
is($res->code,                  500);
is($res->message,               'Internal Server Error');
is($res->major_version,         1);
is($res->minor_version,         1);
is($res->headers->content_type, 'text/plain');
is($res->content->body_length,  13);

# Parse HTTP 1.1 multipart response
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.1 200 OK\x0d\x0a");
$res->parse("Content-Length: 814\x0d\x0a");
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
is($res->state,         'done');
is($res->code,          200);
is($res->message,       'OK');
is($res->major_version, 1);
is($res->minor_version, 1);
ok($res->headers->content_type =~ /multipart\/form-data/);
is(ref $res->content->parts->[0],          'Mojo::Content');
is(ref $res->content->parts->[1],          'Mojo::Content');
is(ref $res->content->parts->[2],          'Mojo::Content');
is($res->content->parts->[0]->file->slurp, "hallo welt test123\n");

# Build HTTP 1.1 response start line with minimal headers
$res = Mojo::Message::Response->new;
$res->code(404);
$res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
is($res->build,
        "HTTP/1.1 404 Not Found\x0d\x0a"
      . "Date: Sun, 17 Aug 2008 16:27:35 GMT\x0d\x0a"
      . "Content-Length: 0\x0d\x0a\x0d\x0a");

# Build HTTP 1.1 response start line and header
$res = Mojo::Message::Response->new;
$res->code(200);
$res->headers->connection('keep-alive');
$res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
is($res->build,
        "HTTP/1.1 200 OK\x0d\x0a"
      . "Connection: keep-alive\x0d\x0a"
      . "Date: Sun, 17 Aug 2008 16:27:35 GMT\x0d\x0a"
      . "Content-Length: 0\x0d\x0a\x0d\x0a");

# Build full HTTP 1.1 response
$res = Mojo::Message::Response->new;
$res->code(200);
$res->headers->connection('keep-alive');
$res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
$res->body("Hello World!\n");
is($res->build,
        "HTTP/1.1 200 OK\x0d\x0a"
      . "Connection: keep-alive\x0d\x0a"
      . "Date: Sun, 17 Aug 2008 16:27:35 GMT\x0d\x0a"
      . "Content-Length: 13\x0d\x0a\x0d\x0a"
      . "Hello World!\n");

# Build HTTP 0.9 response
$res = Mojo::Message::Response->new;
$res->major_version(0);
$res->minor_version(9);
$res->body("this is just a document and valid HTTP 0.9\nlalala\n");
is($res->build, "this is just a document and valid HTTP 0.9\nlalala\n");

# Build HTTP 1.1 multipart response
$res = Mojo::Message::Response->new;
$res->content(Mojo::Content::MultiPart->new);
$res->code(200);
$res->headers->content_type('multipart/mixed; boundary=7am1X');
$res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
push @{$res->content->parts}, Mojo::Content->new(file => Mojo::File->new);
$res->content->parts->[-1]->file->add_chunk('Hallo Welt lalalalalala!');
$content = Mojo::Content->new;
$content->file->add_chunk("lala\nfoobar\nperl rocks\n");
$content->headers->content_type('text/plain');
push @{$res->content->parts}, $content;
is($res->build,
        "HTTP/1.1 200 OK\x0d\x0a"
      . "Date: Sun, 17 Aug 2008 16:27:35 GMT\x0d\x0a"
      . "Content-Length: 110\x0d\x0a"
      . "Content-Type: multipart/mixed; boundary=7am1X\x0d\x0a\x0d\x0a"
      . "\x0d\x0a--7am1X\x0d\x0a\x0d\x0a"
      . 'Hallo Welt lalalalalala!'
      . "\x0d\x0a--7am1X\x0d\x0a"
      . "Content-Type: text/plain\x0d\x0a\x0d\x0a"
      . "lala\nfoobar\nperl rocks\n"
      . "\x0d\x0a--7am1X--");

# Parse Lighttpd like CGI like environment variables and a body
$req = Mojo::Message::Request->new;
$req->parse(
    {   HTTP_CONTENT_LENGTH => 11,
        HTTP_EXPECT         => '100-continue',
        PATH_INFO           => '/test/index.cgi/foo/bar',
        QUERY_STRING        => 'lalala=23&bar=baz',
        REQUEST_METHOD      => 'POST',
        SCRIPT_NAME         => '/test/index.cgi',
        HTTP_HOST           => 'localhost:8080',
        SERVER_PROTOCOL     => 'HTTP/1.0'
    }
);
$req->parse('Hello World');
is($req->state,           'done');
is($req->method,          'POST');
is($req->headers->expect, '100-continue');
is($req->url->path,       '/test/index.cgi/foo/bar');
is($req->url->base->path, '/test/index.cgi');
is($req->url->host,       'localhost');
is($req->url->port,       8080);
is($req->url->query,      'lalala=23&bar=baz');
is($req->minor_version,   '0');
is($req->major_version,   '1');
is($req->body,            'Hello World');

# Parse Apache like CGI like environment variables and a body
$req = Mojo::Message::Request->new;
$req->parse(
    {   CONTENT_LENGTH  => 11,
        CONTENT_TYPE    => 'application/x-www-form-urlencoded',
        HTTP_EXPECT     => '100-continue',
        PATH_INFO       => '/test/index.cgi/foo/bar',
        QUERY_STRING    => 'lalala=23&bar=baz',
        REQUEST_METHOD  => 'POST',
        SCRIPT_NAME     => '/test/index.cgi',
        HTTP_HOST       => 'localhost:8080',
        SERVER_PROTOCOL => 'HTTP/1.0'
    }
);
$req->parse('hello=world');
is($req->state,           'done');
is($req->method,          'POST');
is($req->headers->expect, '100-continue');
is($req->url->path,       '/test/index.cgi/foo/bar');
is($req->url->base->path, '/test/index.cgi');
is($req->url->host,       'localhost');
is($req->url->port,       8080);
is($req->url->query,      'lalala=23&bar=baz');
is($req->minor_version,   '0');
is($req->major_version,   '1');
is($req->body,            'hello=world');
is_deeply($req->param('hello'), 'world');

# Parse response with cookie
$res = Mojo::Message::Response->new;
$res->parse("HTTP/1.0 200 OK\x0d\x0a");
$res->parse("Content-Type: text/plain\x0d\x0a");
$res->parse("Content-Length: 27\x0d\x0a");
$res->parse("Set-Cookie: foo=bar; Version=1; Path=/test\x0d\x0a\x0d\x0a");
$res->parse("Hello World!\n1234\nlalalala\n");
is($res->state,                   'done');
is($res->code,                    200);
is($res->message,                 'OK');
is($res->major_version,           1);
is($res->minor_version,           0);
is($res->headers->content_type,   'text/plain');
is($res->headers->content_length, 27);
is($res->headers->set_cookie,     'foo=bar; Version=1; Path=/test');
my $cookies = $res->cookies;
is($cookies->[0]->name,    'foo');
is($cookies->[0]->value,   'bar');
is($cookies->[0]->version, 1);
is($cookies->[0]->path,    '/test');

# Build HTTP 1.1 response with 2 cookies
$res = Mojo::Message::Response->new;
$res->code(404);
$res->headers->date('Sun, 17 Aug 2008 16:27:35 GMT');
$res->cookies(
    Mojo::Cookie::Response->new(
        {   name  => 'foo',
            value => 'bar',
            path  => '/foobar'
        }
    ),
    Mojo::Cookie::Response->new(
        {   name  => 'bar',
            value => 'baz',
            path  => '/test/23'
        }
    )
);
is($res->build,
        "HTTP/1.1 404 Not Found\x0d\x0a"
      . "Date: Sun, 17 Aug 2008 16:27:35 GMT\x0d\x0a"
      . "Content-Length: 0\x0d\x0a"
      . "Set-Cookie: foo=bar; Version=1; Path=/foobar\x0d\x0a"
      . "Set-Cookie: bar=baz; Version=1; Path=/test/23\x0d\x0a\x0d\x0a");

# Build full HTTP 1.1 request with cookies
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->cookies(
    Mojo::Cookie::Request->new(
        {   name  => 'foo',
            value => 'bar',
            path  => '/foobar'
        }
    ),
    Mojo::Cookie::Request->new(
        {   name  => 'bar',
            value => 'baz',
            path  => '/test/23'
        }
    )
);
$req->body("Hello World!\n");
is($req->build,
        "GET /foo/bar HTTP/1.1\x0d\x0a"
      . "Expect: 100-continue\x0d\x0a"
      . "Host: 127.0.0.1\x0d\x0a"
      . "Content-Length: 13\x0d\x0a"
      . 'Cookie: $Version=1; foo=bar; $Path=/foobar; bar=baz; $Path=/test/23'
      . "\x0d\x0a\x0d\x0a"
      . "Hello World!\n");

# Parse full HTTP 1.0 request with cookies
$req     = Mojo::Message::Request->new;
$counter = 0;
$req->parser_progress_cb(sub { $counter++ });
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: text/');
$req->parse("plain\x0d\x0a");
$req->parse('Cookie: $Version=1; foo=bar; $Path=/foobar; bar=baz; $Path=/t');
$req->parse("est/23\x0d\x0a");
$req->parse("Content-Length: 27\x0d\x0a\x0d\x0aHell");
$req->parse("o World!\n1234\nlalalala\n");
is($counter,                      8);
is($req->state,                   'done');
is($req->method,                  'GET');
is($req->major_version,           1);
is($req->minor_version,           0);
is($req->url,                     '/foo/bar/baz.html?foo=13#23');
is($req->headers->content_type,   'text/plain');
is($req->headers->content_length, 27);
$cookies = $req->cookies;
is($cookies->[0]->name,    'foo');
is($cookies->[0]->value,   'bar');
is($cookies->[0]->version, 1);
is($cookies->[0]->path,    '/foobar');
is($cookies->[1]->name,    'bar');
is($cookies->[1]->value,   'baz');
is($cookies->[1]->version, 1);
is($cookies->[1]->path,    '/test/23');

# Build HTTP 1.1 request with start line callback
$req = Mojo::Message::Request->new;
$req->url->parse('http://127.0.0.1/test');
$counter = 1;
$req->build_start_line_cb(
    sub {
        my $startline = '';
        $startline = "GET /foo/bar HTTP/1.1\x0d\x0a" if $counter == 1;
        $counter++;
        return $startline;
    }
);
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
is($req->build,
        "GET /foo/bar HTTP/1.1\x0d\x0a"
      . "Expect: 100-continue\x0d\x0a"
      . "Host: 127.0.0.1\x0d\x0a"
      . "Content-Length: 13\x0d\x0a\x0d\x0a"
      . "Hello World!\n");

# Build HTTP 1.1 request with start line callback
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/test');
$counter = 1;
$req->build_headers_cb(
    sub {
        my $h       = '';
        my $headers = Mojo::Headers->new;
        $headers->expect('100-continue');
        $h = "$headers\x0d\x0a\x0d\x0a" if $counter == 1;
        $counter++;
        return $h;
    }
);
$req->body("Hello World!\n");
is($req->build,
        "GET /test HTTP/1.1\x0d\x0a"
      . "Expect: 100-continue\x0d\x0a\x0d\x0a"
      . "Hello World!\n");

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
is($req->is_done, 1);
is_deeply($req->param('Vorname'), 'T');

{
    my $m = Mojo::Message->new;
    is( $m->major_version, 1, "major_version defaults to 1");
    is( $m->minor_version, 1, "minor_version defaults to 1");
    ok( $m->is_version('1.1'), "1.1 object passes is_version('1.1')");
    ok( $m->is_version('1.0'), "1.1 object passes is_version('1.0')");
}
{
    my $m = Mojo::Message->new( minor_version => 0 );
    is( $m->minor_version, 0, "minor_version set to 0");
    ok( !$m->is_version('1.1'), "1.0 object fails is_version('1.1')");
    ok( $m->is_version('1.0'), "1.0 object passes is_version('1.0')");
}
