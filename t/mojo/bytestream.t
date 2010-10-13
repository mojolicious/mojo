#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

# Homer, we're going to ask you a few simple yes or no questions.
# Do you understand?
# Yes. *lie dectector blows up*
use Test::More;

plan skip_all => 'Perl 5.10 required for this test!'
  unless eval { require Digest::SHA; 1 };
plan tests => 81;

use_ok 'Mojo::ByteStream', 'b';

# Empty
my $stream = Mojo::ByteStream->new;
is $stream->size,     0, 'size is 0';
is $stream->raw_size, 0, 'raw size is 0';

# Chunk
$stream->add_chunk("line1\nline2");
is $stream->size,     11, 'size is 11';
is $stream->raw_size, 11, 'raw size is 11';

# Clean
my $buffer = $stream->empty;
is $stream->size,     0,  'size is 0';
is $stream->raw_size, 11, 'raw size is 11';
is $buffer, "line1\nline2", 'right buffer content';

# Add
$stream->add_chunk("first\nsec");
is $stream->size,     9,  'size is 9';
is $stream->raw_size, 20, 'raw size is 20';

# Remove
$buffer = $stream->remove(2);
is $buffer, 'fi', 'removed chunk is "fi"';
is $stream->size,     7,  'size is 7';
is $stream->raw_size, 20, 'raw size is 20';

# Get
is $stream->get_line, 'rst', 'line is "rst"';
is $stream->get_line, undef, 'no more lines';

# Stringify
$stream = Mojo::ByteStream->new->add_chunk('abc');
is "$stream", 'abc', 'right buffer content';
is $stream->to_string, 'abc', 'right buffer content';

# camelize
$stream = b('foo_bar_baz');
is $stream->camelize, 'FooBarBaz', 'right camelized result';
$stream = b('FooBarBaz');
is $stream->camelize, 'Foobarbaz', 'right camelized result';
$stream = b('foo_b_b');
is $stream->camelize, 'FooBB', 'right camelized result';
$stream = b('foo-b_b');
is $stream->camelize, 'Foo::BB', 'right camelized result';

# decamelize
$stream = b('FooBarBaz');
is $stream->decamelize, 'foo_bar_baz', 'right decamelized result';
$stream = b('foo_bar_baz');
is $stream->decamelize, 'foo_bar_baz', 'right decamelized result';
$stream = b('FooBB');
is $stream->decamelize, 'foo_b_b', 'right decamelized result';
$stream = b('Foo::BB');
is $stream->decamelize, 'foo-b_b', 'right decamelized result';

# b64_encode
$stream = b('foobar$%^&3217');
is $stream->b64_encode, "Zm9vYmFyJCVeJjMyMTc=\n",
  'right base64 encoded result';

# b64_decode
$stream = b("Zm9vYmFyJCVeJjMyMTc=\n");
is $stream->b64_decode, 'foobar$%^&3217', 'right base64 decoded result';

# utf8 b64_encode
$stream = b("foo\x{df}\x{0100}bar%23\x{263a}")->b64_encode;
is "$stream", "Zm9vw5/EgGJhciUyM+KYug==\n", 'right base64 encoded result';

# utf8 b64_decode
$stream = b("Zm9vw5/EgGJhciUyM+KYug==\n")->b64_decode->decode('UTF-8');
is "$stream", "foo\x{df}\x{0100}bar%23\x{263a}",
  'right base64 decoded result';

# b64_encode (custom line ending)
$stream = b('foobar$%^&3217');
is $stream->b64_encode(''),
  "Zm9vYmFyJCVeJjMyMTc=", 'right base64 encoded result';

# url_escape
$stream = b('business;23');
is $stream->url_escape, 'business%3B23', 'right url escaped result';

# url_unescape
$stream = b('business%3B23');
is $stream->url_unescape, 'business;23', 'right url unescaped result';

# utf8 url_escape
$stream = b("foo\x{df}\x{0100}bar\x{263a}")->url_escape;
is "$stream", 'foo%C3%9F%C4%80bar%E2%98%BA', 'right url escaped result';

# utf8 url_unescape
$stream = b('foo%C3%9F%C4%80bar%E2%98%BA')->url_unescape->decode('UTF-8');
is "$stream", "foo\x{df}\x{0100}bar\x{263a}", 'right url unescaped result';

# url_sanitize
$stream = b('t%c3est%6a1%7E23%30')->url_sanitize;
is "$stream", 't%C3estj1~230', 'right url sanitized result';

# qp_encode
$stream = b("foo\x{99}bar$%^&3217");
like $stream->qp_encode, qr/^foo\=99bar0\^\&3217/, 'right qp encoded result';

# qp_decode
$stream = b("foo=99bar0^&3217=\n");
is $stream->qp_decode, "foo\x{99}bar$%^&3217", 'right qp decoded result';

# quote
$stream = b('foo; 23 "bar');
is $stream->quote, '"foo; 23 \"bar"', 'right quoted result';

# unquote
$stream = b('"foo 23 \"bar"');
is $stream->unquote, 'foo 23 "bar', 'right unquoted result';

# md5_bytes
$stream = b('foo bar baz');
is unpack('H*', $stream->md5_bytes), "ab07acbb1e496801937adfa772424bf7",
  'right binary md5 checksum';

# md5_sum
$stream = b('foo bar baz');
is $stream->md5_sum, 'ab07acbb1e496801937adfa772424bf7', 'right md5 checksum';

# sha1_bytes
$stream = b('foo bar baz');
is unpack('H*', $stream->sha1_bytes),
  "c7567e8b39e2428e38bf9c9226ac68de4c67dc39", 'right binary sha1 checksum';

# sha1_sum
$stream = b('foo bar baz');
is $stream->sha1_sum, 'c7567e8b39e2428e38bf9c9226ac68de4c67dc39',
  'right sha1 checksum';

# length
$stream = b('foo bar baz');
is $stream->size, 11, 'size is 11';

# "0"
$stream = b('0');
is $stream->size,      1,   'size is 1';
is $stream->to_string, '0', 'right buffer content';

# hmac_md5_sum (RFC2202)
is b("Hi There")->hmac_md5_sum(chr(0x0b) x 16),
  '9294727a3638bb1c13f48ef8158bfc9d', 'right hmac md5 checksum';
is b("what do ya want for nothing?")->hmac_md5_sum("Jefe"),
  '750c783e6ab0b503eaa86e310a5db738', 'right hmac md5 checksum';
is b(chr(0xdd) x 50)->hmac_md5_sum(chr(0xaa) x 16),
  '56be34521d144c88dbb8c733f0e8b3f6', 'right hmac md5 checksum';
is b(chr(0xcd) x 50)
  ->hmac_md5_sum(
    pack 'H*' => '0102030405060708090a0b0c0d0e0f10111213141516171819'),
  '697eaf0aca3a3aea3a75164746ffaa79', 'right hmac md5 checksum';
is b("Test With Truncation")->hmac_md5_sum(chr(0x0c) x 16),
  '56461ef2342edc00f9bab995690efd4c', 'right hmac md5 checksum';
is b("Test Using Larger Than Block-Size Key - Hash Key First")
  ->hmac_md5_sum(chr(0xaa) x 80), '6b1ab7fe4bd7bf8f0b62e6ce61b9d0cd',
  'right hmac md5 checksum';
is b(
    "Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data"
  )->hmac_md5_sum(chr(0xaa) x 80), '6f630fad67cda0ee1fb1f562db3aa53e',
  'right hmac md5 checksum';

# hmac_sha1_sum (RFC2202)
is b("Hi There")->hmac_sha1_sum(chr(0x0b) x 20),
  'b617318655057264e28bc0b6fb378c8ef146be00', 'right hmac sha1 checksum';
is b("what do ya want for nothing?")->hmac_sha1_sum("Jefe"),
  'effcdf6ae5eb2fa2d27416d5f184df9c259a7c79', 'right hmac sha1 checksum';
is b(chr(0xdd) x 50)->hmac_sha1_sum(chr(0xaa) x 20),
  '125d7342b9ac11cd91a39af48aa17b4f63f175d3', 'right hmac sha1 checksum';
is b(chr(0xcd) x 50)
  ->hmac_sha1_sum(
    pack 'H*' => '0102030405060708090a0b0c0d0e0f10111213141516171819'),
  '4c9007f4026250c6bc8414f9bf50c86c2d7235da', 'right hmac sha1 checksum';
is b("Test With Truncation")->hmac_sha1_sum(chr(0x0c) x 20),
  '4c1a03424b55e07fe7f27be1d58bb9324a9a5a04', 'right hmac sha1 checksum';
is b("Test Using Larger Than Block-Size Key - Hash Key First")
  ->hmac_sha1_sum(chr(0xaa) x 80), 'aa4ae5e15272d00e95705637ce8a3b55ed402112',
  'right hmac sha1 checksum';
is b(
    "Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data"
  )->hmac_sha1_sum(chr(0xaa) x 80),
  'e8e99d0f45237d786d6bbaa7965c7808bbff1a91', 'right hmac sha1 checksum';

# html_escape
$stream = b("foobar'<baz>");
is $stream->html_escape, "foobar&#39;&lt;baz&gt;",
  'right html escaped result';

# html_escape (nothing to escape)
$stream = b('foobar');
is $stream->html_escape, 'foobar', 'right html escaped result';

# html_unescape
$stream = b('foobar&lt;baz&gt;&#x26;&#34;');
is $stream->html_unescape, "foobar<baz>&\"", 'right html unescaped result';

# html_unescape (apos)
$stream = b('foobar&apos;&lt;baz&gt;&#x26;&#34;');
is $stream->html_unescape, "foobar'<baz>&\"", 'right html unescaped result';

# html_unescape (nothing to unescape)
$stream = b('foobar');
is $stream->html_unescape, 'foobar', 'right html unescaped result';

# utf8 html_escape
$stream = b("foobar<baz>&\"\x{152}")->html_escape;
is "$stream", 'foobar&lt;baz&gt;&amp;&quot;&OElig;',
  'right html escaped result';

# utf8 html_unescape
$stream =
  b('foobar&lt;baz&gt;&#x26;&#34;&OElig;')->decode('UTF-8')->html_unescape;
is "$stream", "foobar<baz>&\"\x{152}", 'right html unescaped result';

# html_escape (path)
$stream =
  b('/usr/local/lib/perl5/site_perl/5.10.0/Mojo/ByteStream.pm')->html_escape;
is "$stream", '/usr/local/lib/perl5/site_perl/5.10.0/Mojo/ByteStream.pm',
  'right html escaped result';

# xml_escape
$stream = b(qq/la<f>\nbar"baz"'yada\n'&lt;la/)->xml_escape;
is "$stream", "la&lt;f&gt;\nbar&quot;baz&quot;&#39;yada\n&#39;&amp;lt;la",
  'right xml escaped result';

# utf8 xml_escape with nothing to escape
$stream = b('привет')->xml_escape;
is "$stream", 'привет', 'right xml escaped result';

# utf8 xml_escape
$stream = b('привет<foo>')->xml_escape;
is "$stream", 'привет&lt;foo&gt;', 'right xml escaped result';

# Decode invalid utf8
$stream = b("\x{1000}")->decode('UTF-8');
is $stream->to_string, undef, 'decoding invalid utf8 worked';

# punycode_encode
$stream = b('bücher')->punycode_encode;
is "$stream", 'bcher-kva', 'right punycode encoded result';

# punycode_decode
$stream = b('bcher-kva')->punycode_decode;
is "$stream", 'bücher', 'right punycode decoded result';

# trim
$stream = b(' la la la ')->trim;
is "$stream", 'la la la', 'right trimmed result';
$stream = b(" \n la la la \n ")->trim;
is "$stream", 'la la la', 'right trimmed result';
$stream = b("\n la\nla la \n")->trim;
is "$stream", "la\nla la", 'right trimmed result';
$stream = b(" \nla\nla\nla\n ")->trim;
is "$stream", "la\nla\nla", 'right trimmed result';

# say and autojoin
$buffer = '';
open my $handle, '>', \$buffer;
b('te', 'st')->say($handle);
my $backup = *STDOUT;
*STDOUT = $handle;
b(1, 2, 3)->say;
*STDOUT = $backup;
is $buffer, "test\n123\n", 'right output';

# Nested bytestreams
$stream = b(b('test'));
ok !ref $stream->to_string, 'nested bytestream stringified';
$stream = Mojo::ByteStream->new(Mojo::ByteStream->new('test'));
ok !ref $stream->to_string, 'nested bytestream stringified';
