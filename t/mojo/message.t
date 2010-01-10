#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use utf8;

use Test::More tests => 448;

use File::Spec;
use File::Temp;
use Mojo::Filter::Chunked;
use Mojo::Headers;

# When will I learn?
# The answer to life's problems aren't at the bottom of a bottle,
# they're on TV!
use_ok('Mojo::Asset::File');
use_ok('Mojo::Content::Single');
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

# Parse pipelined HTTP 1.1 start line, no headers and body
$req = Mojo::Message::Request->new;
$req->parse("GET / HTTP/1.1\x0d\x0a\x0d\x0aGET / HTTP/1.1\x0d\x0a\x0d\x0a");
is($req->state,     'done_with_leftovers');
is($req->leftovers, "GET / HTTP/1.1\x0d\x0a\x0d\x0a");

# Parse HTTP 1.1 start line, no headers and body with leading CRLFs
# (SHOULD be ignored, RFC2616, Section 4.1)
$req = Mojo::Message::Request->new;
$req->parse("\x0d\x0aGET / HTTP/1.1\x0d\x0a\x0d\x0a");
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

# Parse full HTTP 1.0 request (behind reverse proxy)
my $backup = $ENV{MOJO_REVERSE_PROXY};
$ENV{MOJO_REVERSE_PROXY} = 1;
$req = Mojo::Message::Request->new;
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: text/');
$req->parse("plain\x0d\x0aContent-Length: 27\x0d\x0a");
$req->parse("Host: localhost\x0d\x0a");
$req->parse("X-Forwarded-For: kraih.com, mojolicious.org\x0d\x0a\x0d\x0a");
$req->parse("Hello World!\n1234\nlalalala\n");
is($req->state,         'done');
is($req->method,        'GET');
is($req->major_version, 1);
is($req->minor_version, 0);
is($req->url,           '/foo/bar/baz.html?foo=13#23');
is($req->url->to_abs,   'http://mojolicious.org/foo/bar/baz.html?foo=13#23');
is($req->headers->content_type,   'text/plain');
is($req->headers->content_length, 27);
$ENV{MOJO_REVERSE_PROXY} = $backup;

# Parse full HTTP 1.0 request with zero chunk
$req = Mojo::Message::Request->new;
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: text/');
$req->parse("plain\x0d\x0aContent-Length: 27\x0d\x0a\x0d\x0aHell");
$req->parse("o World!\n123");
$req->parse('0');
$req->parse("\nlalalala\n");
is($req->state,                   'done');
is($req->method,                  'GET');
is($req->major_version,           1);
is($req->minor_version,           0);
is($req->url,                     '/foo/bar/baz.html?foo=13#23');
is($req->headers->content_type,   'text/plain');
is($req->headers->content_length, 27);

# Parse full HTTP 1.0 request with utf8 form input
$req = Mojo::Message::Request->new;
$req->parse('GET /foo/bar/baz.html?fo');
$req->parse("o=13#23 HTTP/1.0\x0d\x0aContent");
$req->parse('-Type: application/');
$req->parse("x-www-form-urlencoded\x0d\x0aContent-Length: 53");
$req->parse("\x0d\x0a\x0d\x0a");
$req->parse('name=%D0%92%D1%8F%D1%87%D0%B5%D1%81%D0%BB%D0%B0%D0%B2');
is($req->state,                   'done');
is($req->method,                  'GET');
is($req->major_version,           1);
is($req->minor_version,           0);
is($req->url,                     '/foo/bar/baz.html?foo=13#23');
is($req->headers->content_type,   'application/x-www-form-urlencoded');
is($req->headers->content_length, 53);
is($req->param('name'),           'Вячеслав');

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
$req->parse("0\x0d\x0a\x0d\x0a");
is($req->state,                   'done');
is($req->method,                  'POST');
is($req->major_version,           1);
is($req->minor_version,           1);
is($req->url,                     '/foo/bar/baz.html?foo=13#23');
is($req->headers->content_length, 13);
is($req->headers->content_type,   'text/plain');
is($req->content->asset->size,    13);
is($req->content->asset->slurp,   'abcdabcdefghi');

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
is($req->content->asset->size,  26);
is($req->content->asset->slurp, 'foo=bar& tset=23+;&foo=bar');
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
is($req->content->asset->size,  26);
is($req->content->asset->slurp, 'foo=bar&+tset=23+;&foo=bar');
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
is($req->headers->content_length,       13);
is($req->content->asset->size,          13);
is($req->content->asset->slurp,         'abcdabcdefghi');

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
is($req->state,         'done_with_leftovers');
is($req->method,        'POST');
is($req->major_version, 1);
is($req->minor_version, 1);
is($req->url,           '/foo/bar/baz.html?foo=13&bar=23#23');
is($req->query_params,  'foo=13&bar=23');
ok(!defined $req->headers->transfer_encoding);
is($req->headers->content_type,        'text/plain');
is($req->headers->header('X-Trailer'), '777');
is($req->headers->content_length,      13);
is($req->content->asset->size,         13);
is($req->content->asset->slurp,        'abcdabcdefghi');

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
is($req->state,                         'done');
is($req->method,                        'POST');
is($req->major_version,                 1);
is($req->minor_version,                 1);
is($req->url,                           '/foo/bar/baz.html?foo=13&bar=23#23');
is($req->query_params,                  'foo=13&bar=23');
is($req->headers->content_type,         'text/plain');
is($req->headers->header('X-Trailer1'), 'test');
is($req->headers->header('X-Trailer2'), '123');
is($req->headers->content_length,       13);
is($req->content->asset->size,          13);
is($req->content->asset->slurp,         'abcdabcdefghi');

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
is($req->state,                         'done');
is($req->method,                        'POST');
is($req->major_version,                 1);
is($req->minor_version,                 1);
is($req->url,                           '/foo/bar/baz.html?foo=13&bar=23#23');
is($req->query_params,                  'foo=13&bar=23');
is($req->headers->content_type,         'text/plain');
is($req->headers->header('X-Trailer1'), 'test');
is($req->headers->header('X-Trailer2'), '123');
is($req->headers->content_length,       13);
is($req->content->asset->size,          13);
is($req->content->asset->slurp,         'abcdabcdefghi');

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
is(ref $req->content->parts->[0],           'Mojo::Content::Single');
is(ref $req->content->parts->[1],           'Mojo::Content::Single');
is(ref $req->content->parts->[2],           'Mojo::Content::Single');
is($req->content->parts->[0]->asset->slurp, "hallo welt test123\n");
is_deeply($req->body_params->to_hash->{text1}, "hallo welt test123\n");
is_deeply($req->body_params->to_hash->{text2}, '');
is($req->upload('upload')->filename,    'hello.pl');
is(ref $req->upload('upload')->asset,   'Mojo::Asset::File');
is($req->upload('upload')->asset->size, 69);
my $file =
  File::Spec->catfile(File::Temp::tempdir(), ("MOJO_TMP." . time . ".txt"));
ok($req->upload('upload')->move_to($file));
is((unlink $file), 1);

# Build minimal HTTP 1.1 request
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/');
is($req->build,
        "GET / HTTP/1.1\x0d\x0a"
      . "Host: 127.0.0.1\x0d\x0aContent-Length: 0\x0d\x0a\x0d\x0a");

# Build HTTP 1.1 start line and header
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
is($req->build,
        "GET /foo/bar HTTP/1.1\x0d\x0a"
      . "Expect: 100-continue\x0d\x0a"
      . "Host: 127.0.0.1\x0d\x0aContent-Length: 0\x0d\x0a\x0d\x0a");

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
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->expect('100-continue');
$req->body("Hello World!\n");
$req->proxy('http://127.0.0.2:8080');
is($req->build,
        "GET http://127.0.0.1/foo/bar HTTP/1.1\x0d\x0a"
      . "Expect: 100-continue\x0d\x0a"
      . "Host: 127.0.0.1\x0d\x0a"
      . "Content-Length: 13\x0d\x0a\x0d\x0a"
      . "Hello World!\n");

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
$req->progress_cb(sub { $counter2++ });
$req->body(
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
      . "\x0d\x0a0\x0d\x0a\x0d\x0a");
ok($counter2);

# Build HTTP 1.1 chunked request with trailing headers
$req = Mojo::Message::Request->new;
$req->method('GET');
$req->url->parse('http://127.0.0.1/foo/bar');
$req->headers->transfer_encoding('chunked');
$req->headers->trailer('X-Test; X-Test2');
$counter = 1;
$chunked = Mojo::Filter::Chunked->new;
$req->body_cb(
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
$res->parse("0\x0d\x0a\x0d\x0a");
is($res->state,                   'done');
is($res->code,                    500);
is($res->message,                 'Internal Server Error');
is($res->major_version,           1);
is($res->minor_version,           1);
is($res->headers->content_type,   'text/plain');
is($res->headers->content_length, 13);
is($res->content->body_size,      13);

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
is(ref $res->content->parts->[0],           'Mojo::Content::Single');
is(ref $res->content->parts->[1],           'Mojo::Content::Single');
is(ref $res->content->parts->[2],           'Mojo::Content::Single');
is($res->content->parts->[0]->asset->slurp, "hallo welt test123\n");

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
push @{$res->content->parts},
  Mojo::Content::Single->new(asset => Mojo::Asset::File->new);
$res->content->parts->[-1]->asset->add_chunk('Hallo Welt lalalalalala!');
$content = Mojo::Content::Single->new;
$content->asset->add_chunk("lala\nfoobar\nperl rocks\n");
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

# Parse IIS 6.0 like CGI environment variables and a body
$req = Mojo::Message::Request->new;
$req->parse(
    CONTENT_LENGTH  => 11,
    HTTP_EXPECT     => '100-continue',
    CONTENT_TYPE    => 'application/x-www-form-urlencoded',
    PATH_INFO       => '/foo/bar',
    PATH_TRANSLATED => 'C:\\FOO\\myapp\\bar',
    SERVER_SOFTWARE => 'Microsoft-IIS/6.0',
    QUERY_STRING    => 'lalala=23&bar=baz',
    REQUEST_METHOD  => 'POST',
    SCRIPT_NAME     => '/foo/bar',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
);
$req->parse('hello=world');
is($req->state,           'done');
is($req->method,          'POST');
is($req->headers->expect, '100-continue');
is($req->url->path,       '/bar');
is($req->url->base->path, '/foo/');
is($req->url->host,       'localhost');
is($req->url->port,       8080);
is($req->url->query,      'lalala=23&bar=baz');
is($req->minor_version,   '0');
is($req->major_version,   '1');
is($req->body,            'hello=world');
is_deeply($req->param('hello'), 'world');
is($req->url->to_abs->to_string,
    'http://localhost:8080/foo/bar?lalala=23&bar=baz');
is($req->env->{HTTP_EXPECT}, '100-continue');

# Parse IIS 6.0 like CGI environment variables and a body (root)
$req = Mojo::Message::Request->new;
$req->parse(
    CONTENT_LENGTH  => 11,
    HTTP_EXPECT     => '100-continue',
    CONTENT_TYPE    => 'application/x-www-form-urlencoded',
    PATH_INFO       => '/foo/bar',
    PATH_TRANSLATED => 'C:\\FOO\\myapp\\foo\\bar',
    SERVER_SOFTWARE => 'Microsoft-IIS/6.0',
    QUERY_STRING    => 'lalala=23&bar=baz',
    REQUEST_METHOD  => 'POST',
    SCRIPT_NAME     => '/foo/bar',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
);
$req->parse('hello=world');
is($req->state,           'done');
is($req->method,          'POST');
is($req->headers->expect, '100-continue');
is($req->url->path,       '/foo/bar');
is($req->url->base->path, '/');
is($req->url->host,       'localhost');
is($req->url->port,       8080);
is($req->url->query,      'lalala=23&bar=baz');
is($req->minor_version,   '0');
is($req->major_version,   '1');
is($req->body,            'hello=world');
is_deeply($req->param('hello'), 'world');
is($req->url->to_abs->to_string,
    'http://localhost:8080/foo/bar?lalala=23&bar=baz');

# Parse IIS 6.0 like CGI environment variables and a body (trailing slash)
$req = Mojo::Message::Request->new;
$req->parse(
    CONTENT_LENGTH  => 11,
    HTTP_EXPECT     => '100-continue',
    CONTENT_TYPE    => 'application/x-www-form-urlencoded',
    PATH_INFO       => '/foo/bar/',
    PATH_TRANSLATED => 'C:\\FOO\\myapp\\foo\\bar\\',
    SERVER_SOFTWARE => 'Microsoft-IIS/6.0',
    QUERY_STRING    => 'lalala=23&bar=baz',
    REQUEST_METHOD  => 'POST',
    SCRIPT_NAME     => '/foo/bar/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
);
$req->parse('hello=world');
is($req->state,           'done');
is($req->method,          'POST');
is($req->headers->expect, '100-continue');
is($req->url->path,       '/foo/bar/');
is($req->url->base->path, '/');
is($req->url->host,       'localhost');
is($req->url->port,       8080);
is($req->url->query,      'lalala=23&bar=baz');
is($req->minor_version,   '0');
is($req->major_version,   '1');
is($req->body,            'hello=world');
is_deeply($req->param('hello'), 'world');
is($req->url->to_abs->to_string,
    'http://localhost:8080/foo/bar/?lalala=23&bar=baz');

# Parse IIS 6.0 like CGI environment variables and a body
# (root and trailing slash)
$req = Mojo::Message::Request->new;
$req->parse(
    CONTENT_LENGTH  => 11,
    HTTP_EXPECT     => '100-continue',
    CONTENT_TYPE    => 'application/x-www-form-urlencoded',
    PATH_INFO       => '/foo/bar/',
    PATH_TRANSLATED => 'C:\\FOO\\myapp\\',
    SERVER_SOFTWARE => 'Microsoft-IIS/6.0',
    QUERY_STRING    => 'lalala=23&bar=baz',
    REQUEST_METHOD  => 'POST',
    SCRIPT_NAME     => '/foo/bar/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
);
$req->parse('hello=world');
is($req->state,           'done');
is($req->method,          'POST');
is($req->headers->expect, '100-continue');
is($req->url->path,       '/');
is($req->url->base->path, '/foo/bar/');
is($req->url->host,       'localhost');
is($req->url->port,       8080);
is($req->url->query,      'lalala=23&bar=baz');
is($req->minor_version,   '0');
is($req->major_version,   '1');
is($req->body,            'hello=world');
is_deeply($req->param('hello'), 'world');
is($req->url->to_abs->to_string,
    'http://localhost:8080/foo/bar/?lalala=23&bar=baz');

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
is($req->state,           'done');
is($req->method,          'POST');
is($req->headers->expect, '100-continue');
is($req->url->path,       '/foo/bar');
is($req->url->base->path, '/test/index.cgi/');
is($req->url->host,       'localhost');
is($req->url->port,       8080);
is($req->url->query,      'lalala=23&bar=baz');
is($req->minor_version,   '0');
is($req->major_version,   '1');
is($req->body,            'Hello World');
is($req->url->to_abs->to_string,
    'http://localhost:8080/test/index.cgi/foo/bar?lalala=23&bar=baz');

# Parse Lighttpd like CGI environment variables and a body
# (behind reverse proxy)
$backup                  = $ENV{MOJO_REVERSE_PROXY};
$ENV{MOJO_REVERSE_PROXY} = 1;
$req                     = Mojo::Message::Request->new;
$req->parse(
    HTTP_CONTENT_LENGTH  => 11,
    HTTP_EXPECT          => '100-continue',
    HTTP_X_FORWARDED_FOR => 'mojolicious.org',
    PATH_INFO            => '/test/index.cgi/foo/bar',
    QUERY_STRING         => 'lalala=23&bar=baz',
    REQUEST_METHOD       => 'POST',
    SCRIPT_NAME          => '/test/index.cgi',
    HTTP_HOST            => 'localhost:8080',
    SERVER_PROTOCOL      => 'HTTP/1.0'
);
$req->parse('Hello World');
is($req->state,           'done');
is($req->method,          'POST');
is($req->headers->expect, '100-continue');
is($req->url->path,       '/foo/bar');
is($req->url->base->path, '/test/index.cgi/');
is($req->url->host,       'localhost');
is($req->url->port,       8080);
is($req->url->query,      'lalala=23&bar=baz');
is($req->minor_version,   '0');
is($req->major_version,   '1');
is($req->body,            'Hello World');
is($req->url->to_abs->to_string,
    'http://mojolicious.org/test/index.cgi/foo/bar?lalala=23&bar=baz');
$ENV{MOJO_REVERSE_PROXY} = $backup;

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
is($req->state,           'done');
is($req->method,          'POST');
is($req->headers->expect, '100-continue');
is($req->url->path,       '/foo/bar');
is($req->url->base->path, '/test/index.cgi/');
is($req->url->host,       'localhost');
is($req->url->port,       8080);
is($req->url->query,      'lalala=23&bar=baz');
is($req->minor_version,   '0');
is($req->major_version,   '1');
is($req->body,            'hello=world');
is_deeply($req->param('hello'), 'world');
is($req->url->to_abs->to_string,
    'http://localhost:8080/test/index.cgi/foo/bar?lalala=23&bar=baz');

# Parse Apache 2.2.11 like CGI environment variables and a body
$req = Mojo::Message::Request->new;
$req->parse(
    CONTENT_LENGTH  => 11,
    CONTENT_TYPE    => 'application/x-www-form-urlencoded',
    PATH_INFO       => '/foo/bar',
    QUERY_STRING    => '',
    REQUEST_METHOD  => 'GET',
    SCRIPT_NAME     => '/test/index.cgi',
    HTTP_HOST       => 'localhost',
    SERVER_PROTOCOL => 'HTTP/1.0'
);
$req->parse('hello=world');
is($req->state,           'done');
is($req->method,          'GET');
is($req->url->host,       'localhost');
is($req->url->path,       '/foo/bar');
is($req->url->base->path, '/test/index.cgi/');
is($req->minor_version,   '0');
is($req->major_version,   '1');
is($req->body,            'hello=world');
is_deeply($req->param('hello'), 'world');
is($req->url->to_abs->to_string, 'http://localhost/test/index.cgi/foo/bar');

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
is($req->state,           'done');
is($req->method,          'GET');
is($req->url->host,       'localhost');
is($req->url->path,       '/foo/bar/');
is($req->url->base->path, '/test/index.cgi/');
is($req->minor_version,   '0');
is($req->major_version,   '1');
is($req->body,            'hello=world');
is_deeply($req->param('hello'), 'world');
is($req->url->to_abs->to_string, 'http://localhost/test/index.cgi/foo/bar/');

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
is($req->state,           'done');
is($req->method,          'GET');
is($req->url->host,       'localhost');
is($req->url->path,       '/foo/bar');
is($req->url->base->path, '');
is($req->minor_version,   '0');
is($req->major_version,   '1');
is($req->body,            'hello=world');
is_deeply($req->param('hello'), 'world');
is($req->url->to_abs->to_string, 'http://localhost/foo/bar');

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
is($req->state,           'done');
is($req->method,          'GET');
is($req->url->host,       'localhost');
is($req->url->path,       '');
is($req->url->base->path, '/test/index.cgi/');
is($req->minor_version,   '0');
is($req->major_version,   '1');
is($req->body,            'hello=world');
is_deeply($req->param('hello'), 'world');
is($req->url->to_abs->to_string, 'http://localhost/test/index.cgi');

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
is($req->state,           'done');
is($req->method,          'GET');
is($req->url->host,       'getbootylicious.org');
is($req->url->path,       '/');
is($req->url->base->path, '/cgi-bin/bootylicious/bootylicious.pl/');
is($req->minor_version,   '1');
is($req->major_version,   '1');
is($req->url->to_abs->to_string,
    'http://getbootylicious.org/cgi-bin/bootylicious/bootylicious.pl');

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
is($cookies->[0]->name,        'foo');
is($cookies->[0]->value,       'bar');
is($cookies->[0]->version,     1);
is($cookies->[0]->path,        '/test');
is($res->cookie('foo')->value, 'bar');
is($res->cookie('foo')->path,  '/test');

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
is($res->build,
        "HTTP/1.1 404 Not Found\x0d\x0a"
      . "Date: Sun, 17 Aug 2008 16:27:35 GMT\x0d\x0a"
      . "Content-Length: 0\x0d\x0a"
      . "Set-Cookie: foo=bar; Version=1; Path=/foobar\x0d\x0a"
      . "Set-Cookie: bar=baz; Version=1; Path=/test/23\x0d\x0a"
      . "Set-Cookie2: baz=yada; Version=1; Path=/foobar\x0d\x0a\x0d\x0a");
my $res2 = Mojo::Message::Response->new;
$res2->parse($res->build);
is($res2->state,                   'done');
is($res2->code,                    404);
is($res2->major_version,           1);
is($res2->minor_version,           1);
is($res2->headers->content_length, 0);
is(defined $res2->cookie('foo'),   1);
is(defined $res2->cookie('baz'),   1);
is(defined $res2->cookie('bar'),   1);
is($res2->cookie('foo')->path,     '/foobar');
is($res2->cookie('foo')->value,    'bar');
is($res2->cookie('baz')->path,     '/foobar');
is($res2->cookie('baz')->value,    'yada');
is($res2->cookie('bar')->path,     '/test/23');
is($res2->cookie('bar')->value,    'baz');

# Build response with callback (make sure its called)
$res = Mojo::Message::Response->new;
$res->code(200);
$res->headers->content_length(10);
$res->body(sub { die "Body coderef was called properly\n" });
eval { $res->get_body_chunk(0) };
is($@, "Body coderef was called properly\n");

# Build response with callback (consistency calls)
$res = Mojo::Message::Response->new;
my $body = 'I is here';
$res->headers->content_length(length($body));
$res->body(sub { return substr($body, $_[1], 1) });
my $full   = '';
my $count  = 0;
my $offset = 0;
while (1) {
    my $chunk = $res->get_body_chunk($offset);
    last unless length($chunk);
    $full .= $chunk;
    $offset = length($full);
    $count++;
}
is($count, length($body));
is($full,  $body);

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
$req->progress_cb(sub { $counter++ });
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

# Parse ~ in URL
$req = Mojo::Message::Request->new;
$req->parse("GET /~foobar/ HTTP/1.1\x0d\x0a\x0d\x0a");
is($req->state,         'done');
is($req->method,        'GET');
is($req->major_version, 1);
is($req->minor_version, 1);
is($req->url,           '/~foobar/');

# Parse : in URL
$req = Mojo::Message::Request->new;
$req->parse("GET /perldoc?Mojo::Message::Request HTTP/1.1\x0d\x0a\x0d\x0a");
is($req->state,         'done');
is($req->method,        'GET');
is($req->major_version, 1);
is($req->minor_version, 1);
is($req->url,           '/perldoc?Mojo::Message::Request');

# Body helper
$req = Mojo::Message::Request->new;
$req->body('hi there!');
is($req->body, 'hi there!');
$req->body('');
is($req->body, '');
$req->body('hi there!');
is($req->body, 'hi there!');
$req->body(undef);
is($req->body, '');
$req->body(sub { });
is(ref $req->body, 'CODE');
$req->body(undef);
is($req->body, '');
$req->body(0);
is($req->body, 0);
$req->body(sub { });
is(ref $req->body, 'CODE');
$req->body('hello!');
is($req->body,    'hello!');
is($req->body_cb, undef);
$req->content(Mojo::Content::MultiPart->new);
$req->body('hi!');
is($req->body, 'hi!');

# Version management
my $m = Mojo::Message->new;
is($m->major_version, 1, 'major_version defaults to 1');
is($m->minor_version, 1, 'minor_version defaults to 1');
ok($m->at_least_version('1.1'), '1.1 passes at_least_version("1.1")');
ok($m->at_least_version('1.0'), '1.1 passes at_least_version("1.0")');
$m = Mojo::Message->new(minor_version => 0);
is($m->minor_version, 0, 'minor_version set to 0');
ok(!$m->at_least_version('1.1'), '1.0 fails at_least_version("1.1")');
ok($m->at_least_version('1.0'),  '1.0 passes at_least_version("1.0")');
$m = Mojo::Message->new(major_version => 0, minor_version => 9);
ok(!$m->at_least_version('1.0'), '0.9 fails at_least_version("1.0")');
ok($m->at_least_version('0.9'),  '0.9 passes at_least_version("0.9")');
