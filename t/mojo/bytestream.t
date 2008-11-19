#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

# Homer, we're going to ask you a few simple yes or no questions.
# Do you understand?
# Yes. *lie dectector blows up*
use Test::More tests => 22;

# Lisa, if the Bible has taught us nothing else, and it hasn't,
# it's that girls should stick to girls sports,
# such as hot oil wrestling and foxy boxing and such.
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
my $text =
  Mojo::ByteStream->new("Zm9vw5/EgGJhciUyM+KYug==\n")
  ->b64_decode->decode('utf8');
is("$text", "foo\x{df}\x{0100}bar%23\x{263a}");

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
$text =
  Mojo::ByteStream->new('foo%C3%9F%C4%80bar%E2%98%BA')
  ->url_unescape->decode('utf8');
is("$text", "foo\x{df}\x{0100}bar\x{263a}");

# url_sanitize
$text = Mojo::ByteStream->new('t%c3est%6a1%7E23%30')->url_sanitize;
is("$text", 't%C3estj1~230');

# qp_encode
$stream = Mojo::ByteStream->new("foo\x{99}bar$%^&3217");
is($stream->qp_encode, "foo=99bar0^&3217=\n");

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

# '0'
$stream = Mojo::ByteStream->new('0');
is($stream->length, 1);
is($stream->to_string, '0');
