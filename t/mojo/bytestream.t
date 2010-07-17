#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use utf8;

# Homer, we're going to ask you a few simple yes or no questions.
# Do you understand?
# Yes. *lie dectector blows up*
use Test::More tests => 60;

use_ok('Mojo::ByteStream', 'b');

# Empty
my $stream = Mojo::ByteStream->new;
is($stream->size,     0, 'size is 0');
is($stream->raw_size, 0, 'raw size is 0');

# Chunk
$stream->add_chunk("line1\nline2");
is($stream->size,     11, 'size is 11');
is($stream->raw_size, 11, 'raw size is 11');

# Clean
my $buffer = $stream->empty;
is($stream->size,     0,              'size is 0');
is($stream->raw_size, 11,             'raw size is 11');
is($buffer,           "line1\nline2", 'right buffer content');

# Add
$stream->add_chunk("first\nsec");
is($stream->size,     9,  'size is 9');
is($stream->raw_size, 20, 'raw size is 20');

# Remove
$buffer = $stream->remove(2);
is($buffer,           'fi', 'removed chunk is "fi"');
is($stream->size,     7,    'size is 7');
is($stream->raw_size, 20,   'raw size is 20');

# Get
is($stream->get_line, 'rst', 'line is "rst"');
is($stream->get_line, undef, 'no more lines');

# Stringify
$stream = Mojo::ByteStream->new->add_chunk('abc');
is("$stream",          'abc', 'right buffer content');
is($stream->to_string, 'abc', 'right buffer content');

# camelize
$stream = b('foo_bar_baz');
is($stream->camelize, 'FooBarBaz', 'right camelized result');
$stream = b('FooBarBaz');
is($stream->camelize, 'Foobarbaz', 'right camelized result');
$stream = b('foo_b_b');
is($stream->camelize, 'FooBB', 'right camelized result');
$stream = b('foo-b_b');
is($stream->camelize, 'Foo::BB', 'right camelized result');

# decamelize
$stream = b('FooBarBaz');
is($stream->decamelize, 'foo_bar_baz', 'right decamelized result');
$stream = b('foo_bar_baz');
is($stream->decamelize, 'foo_bar_baz', 'right decamelized result');
$stream = b('FooBB');
is($stream->decamelize, 'foo_b_b', 'right decamelized result');
$stream = b('Foo::BB');
is($stream->decamelize, 'foo-b_b', 'right decamelized result');

# b64_encode
$stream = b('foobar$%^&3217');
is($stream->b64_encode, "Zm9vYmFyJCVeJjMyMTc=\n",
    'right base64 encoded result');

# b64_decode
$stream = b("Zm9vYmFyJCVeJjMyMTc=\n");
is($stream->b64_decode, 'foobar$%^&3217', 'right base64 decoded result');

# utf8 b64_encode
$stream = b("foo\x{df}\x{0100}bar%23\x{263a}")->b64_encode;
is("$stream", "Zm9vw5/EgGJhciUyM+KYug==\n", 'right base64 encoded result');

# utf8 b64_decode
$stream = b("Zm9vw5/EgGJhciUyM+KYug==\n")->b64_decode->decode('UTF-8');
is( "$stream",
    "foo\x{df}\x{0100}bar%23\x{263a}",
    'right base64 decoded result'
);

# url_escape
$stream = b('business;23');
is($stream->url_escape, 'business%3B23', 'right url escaped result');

# url_unescape
$stream = b('business%3B23');
is($stream->url_unescape, 'business;23', 'right url unescaped result');

# utf8 url_escape
$stream = b("foo\x{df}\x{0100}bar\x{263a}")->url_escape;
is("$stream", 'foo%C3%9F%C4%80bar%E2%98%BA', 'right url escaped result');

# utf8 url_unescape
$stream = b('foo%C3%9F%C4%80bar%E2%98%BA')->url_unescape->decode('UTF-8');
is("$stream", "foo\x{df}\x{0100}bar\x{263a}", 'right url unescaped result');

# url_sanitize
$stream = b('t%c3est%6a1%7E23%30')->url_sanitize;
is("$stream", 't%C3estj1~230', 'right url sanitized result');

# qp_encode
$stream = b("foo\x{99}bar$%^&3217");
like($stream->qp_encode, qr/^foo\=99bar0\^\&3217/, 'right qp encoded result');

# qp_decode
$stream = b("foo=99bar0^&3217=\n");
is($stream->qp_decode, "foo\x{99}bar$%^&3217", 'right qp decoded result');

# quote
$stream = b('foo; 23 "bar');
is($stream->quote, '"foo; 23 \"bar"', 'right quoted result');

# unquote
$stream = b('"foo 23 \"bar"');
is($stream->unquote, 'foo 23 "bar', 'right unquoted result');

# md5_bytes
$stream = b('foo bar baz');
is( unpack('H*', $stream->md5_bytes),
    "ab07acbb1e496801937adfa772424bf7",
    'right 16 byte md5 checksum'
);

# md5_sum
$stream = b('foo bar baz');
is($stream->md5_sum, 'ab07acbb1e496801937adfa772424bf7',
    'right md5 checksum');

# length
$stream = b('foo bar baz');
is($stream->size, 11, 'size is 11');

# "0"
$stream = b('0');
is($stream->size,      1,   'size is 1');
is($stream->to_string, '0', 'right buffer content');

# hmac_md5_sum
is( b('some secret message')->hmac_md5_sum('secret'),
    '5a7dcc4c407032ad10758abdda017f7b',
    'right hmac md5 checksum'
);
is( b('some other message')->hmac_md5_sum('secret'),
    '9ab78f427440259a33abb088d4400526',
    'right hmac md5 checksum'
);
is( b('some secret message')->hmac_md5_sum('secret'),
    '5a7dcc4c407032ad10758abdda017f7b',
    'right hmac md5 checksum'
);

# html_escape
$stream = b('foobar<baz>');
is($stream->html_escape, 'foobar&lt;baz&gt;', 'right html escaped result');

# html_escape (nothing to escape)
$stream = b('foobar');
is($stream->html_escape, 'foobar', 'right html escaped result');

# html_unescape
$stream = b('foobar&lt;baz&gt;&#x26;&#34;');
is($stream->html_unescape, "foobar<baz>&\"", 'right html unescaped result');

# html_unescape (nothing to unescape)
$stream = b('foobar');
is($stream->html_unescape, 'foobar', 'right html unescaped result');

# utf8 html_escape
$stream = b("foobar<baz>&\"\x{152}")->html_escape;
is( "$stream",
    'foobar&lt;baz&gt;&amp;&quot;&OElig;',
    'right html escaped result'
);

# utf8 html_unescape
$stream =
  b('foobar&lt;baz&gt;&#x26;&#34;&OElig;')->decode('UTF-8')->html_unescape;
is("$stream", "foobar<baz>&\"\x{152}", 'right html unescaped result');

# html_escape (path)
$stream =
  b('/usr/local/lib/perl5/site_perl/5.10.0/Mojo/ByteStream.pm')->html_escape;
is( "$stream",
    '/usr/local/lib/perl5/site_perl/5.10.0/Mojo/ByteStream.pm',
    'right html escaped result'
);

# xml_escape
$stream = b(qq/la<f>\nbar"baz"'yada\n'&lt;la/)->xml_escape;
is( "$stream",
    "la&lt;f&gt;\nbar&quot;baz&quot;&apos;yada\n&apos;&amp;lt;la",
    'right xml escaped result'
);

# utf8 xml_escape with nothing to escape
$stream = b('привет')->xml_escape;
is("$stream", 'привет', 'right xml escaped result');

# utf8 xml_escape
$stream = b('привет<foo>')->xml_escape;
is("$stream", 'привет&lt;foo&gt;', 'right xml escaped result');

# Decode invalid utf8
$stream = b("\x{1000}")->decode('UTF-8');
is($stream->to_string, undef, 'decoding invalid utf8 worked');

# punycode_encode
$stream = b('bücher')->punycode_encode;
is("$stream", 'bcher-kva', 'right punycode encoded result');

# punycode_decode
$stream = b('bcher-kva')->punycode_decode;
is("$stream", 'bücher', 'right punycode decoded result');

# say
$buffer = '';
open my $handle, '>', \$buffer;
b('test')->say($handle);
my $backup = *STDOUT;
*STDOUT = $handle;
b('123')->say;
*STDOUT = $backup;
is($buffer, "test\n123\n", 'right output');
