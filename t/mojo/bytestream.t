#!perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

# Homer, we're going to ask you a few simple yes or no questions.
# Do you understand?
# Yes. *lie dectector blows up*
use Test::More tests => 29;

use_ok('Mojo::ByteStream');

# camelize
my $stream = Mojo::ByteStream->new('foo_bar_baz');
is($stream->camelize, 'FooBarBaz');
$stream = Mojo::ByteStream->new('FooBarBaz');
is($stream->camelize, 'Foobarbaz');

# decamelize
$stream = Mojo::ByteStream->new('FooBarBaz');
is($stream->decamelize, 'foo_bar_baz');
$stream = Mojo::ByteStream->new('foo_bar_baz');
is($stream->decamelize, 'foo_bar_baz');

# b64_encode
$stream = Mojo::ByteStream->new('foobar$%^&3217');
is($stream->b64_encode, "Zm9vYmFyJCVeJjMyMTc=\n");

# b64_decode
$stream = Mojo::ByteStream->new("Zm9vYmFyJCVeJjMyMTc=\n");
is($stream->b64_decode, 'foobar$%^&3217');

# utf8 b64_encode
$stream =
  Mojo::ByteStream->new("foo\x{df}\x{0100}bar%23\x{263a}")->encode('utf8')
  ->b64_encode;
is("$stream", "Zm9vw5/EgGJhciUyM+KYug==\n");

# utf8 b64_decode
$stream =
  Mojo::ByteStream->new("Zm9vw5/EgGJhciUyM+KYug==\n")
  ->b64_decode->decode('utf8');
is("$stream", "foo\x{df}\x{0100}bar%23\x{263a}");

# url_escape
$stream = Mojo::ByteStream->new('business;23');
is($stream->url_escape, 'business%3B23');

# url_unescape
$stream = Mojo::ByteStream->new('business%3B23');
is($stream->url_unescape, 'business;23');

# utf8 url_escape
$stream =
  Mojo::ByteStream->new("foo\x{df}\x{0100}bar\x{263a}")->encode('utf8')
  ->url_escape;
is("$stream", 'foo%C3%9F%C4%80bar%E2%98%BA');

# utf8 url_unescape
$stream =
  Mojo::ByteStream->new('foo%C3%9F%C4%80bar%E2%98%BA')
  ->url_unescape->decode('utf8');
is("$stream", "foo\x{df}\x{0100}bar\x{263a}");

# url_sanitize
$stream = Mojo::ByteStream->new('t%c3est%6a1%7E23%30')->url_sanitize;
is("$stream", 't%C3estj1~230');

# qp_encode
$stream = Mojo::ByteStream->new("foo\x{99}bar$%^&3217");
like($stream->qp_encode, qr/^foo\=99bar0\^\&3217/);

# qp_decode
$stream = Mojo::ByteStream->new("foo=99bar0^&3217=\n");
is($stream->qp_decode, "foo\x{99}bar$%^&3217");

# quote
$stream = Mojo::ByteStream->new('foo; 23 "bar');
is($stream->quote, '"foo; 23 \"bar"');

# unquote
$stream = Mojo::ByteStream->new('"foo 23 \"bar"');
is($stream->unquote, 'foo 23 "bar');

# md5_sum
$stream = Mojo::ByteStream->new('foo bar baz');
is($stream->md5_sum, 'ab07acbb1e496801937adfa772424bf7');

# length
$stream = Mojo::ByteStream->new('foo bar baz');
is($stream->length, 11);

# "0"
$stream = Mojo::ByteStream->new('0');
is($stream->length,    1);
is($stream->to_string, '0');

# html_encode
$stream = Mojo::ByteStream->new('foobar<baz>');
is($stream->html_encode, 'foobar&lt;baz&gt;');

# html_encode (nothing to encode)
$stream = Mojo::ByteStream->new('foobar');
is($stream->html_encode, 'foobar');

# html_decode
$stream = Mojo::ByteStream->new('foobar&lt;baz&gt;&#x26;&#34;');
is($stream->html_decode, "foobar<baz>&\"");

# html_decode (nothing to decode)
$stream = Mojo::ByteStream->new('foobar');
is($stream->html_decode, 'foobar');

# utf8 html_encode
$stream = Mojo::ByteStream->new("foobar<baz>&\"\x{152}")->html_encode;
is("$stream", 'foobar&lt;baz&gt;&amp;&quot;&OElig;');

# utf8 html_decode
$stream =
  Mojo::ByteStream->new('foobar&lt;baz&gt;&#x26;&#34;&OElig;')->html_decode;
is("$stream", "foobar<baz>&\"\x{152}");

# html_encode (path)
$stream = Mojo::ByteStream->new(
    '/usr/local/lib/perl5/site_perl/5.10.0/Mojo/ByteStream.pm')->html_encode;
is("$stream", '/usr/local/lib/perl5/site_perl/5.10.0/Mojo/ByteStream.pm');
