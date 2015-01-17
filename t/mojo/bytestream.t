use Mojo::Base -strict;

use Test::More;
use Cwd 'abs_path';
use File::Basename 'dirname';
use File::Spec::Functions 'catfile';
use File::Temp 'tempdir';
use FindBin;
use Mojo::ByteStream 'b';

# Tap into method chain
is b('test')->tap(sub { $$_ .= '1' })->camelize, 'Test1', 'right result';

# camelize
is b('foo_bar_baz')->camelize, 'FooBarBaz', 'right camelized result';

# decamelize
is b('FooBarBaz')->decamelize, 'foo_bar_baz', 'right decamelized result';

# unindent
is b(" test\n  123\n 456\n")->unindent, "test\n 123\n456\n",
  'right unindented result';

# b64_encode
is b('foobar$%^&3217')->b64_encode, "Zm9vYmFyJCVeJjMyMTc=\n",
  'right Base64 encoded result';

# b64_decode
is b("Zm9vYmFyJCVeJjMyMTc=\n")->b64_decode, 'foobar$%^&3217',
  'right Base64 decoded result';

# url_escape
is b('business;23')->url_escape, 'business%3B23', 'right URL escaped result';

# url_unescape
is b('foo%C3%9F%C4%80bar%E2%98%BA')->url_unescape->decode,
  "foo\x{df}\x{0100}bar\x{263a}", 'right URL unescaped result';
is b('foo%C3%9F%C4%80bar%E2%98%BA')->url_unescape->decode('UTF-8'),
  "foo\x{df}\x{0100}bar\x{263a}", 'right URL unescaped result';

# html_unescape
is b('&#x3c;foo&#x3E;bar&lt;baz&gt;&#x26;&#34;')->html_unescape,
  "<foo>bar<baz>&\"", 'right HTML unescaped result';

# xml_escape
is b(qq{la<f>\nbar"baz"'yada\n'&lt;la})->xml_escape,
  "la&lt;f&gt;\nbar&quot;baz&quot;&#39;yada\n&#39;&amp;lt;la",
  'right XML escaped result';

# punycode_encode
is b('bücher')->punycode_encode, 'bcher-kva', 'right punycode encoded result';

# punycode_decode
is b('bcher-kva')->punycode_decode, 'bücher', 'right punycode decoded result';

# quote
is b('foo; 23 "bar')->quote, '"foo; 23 \"bar"', 'right quoted result';

# unquote
is b('"foo 23 \"bar"')->unquote, 'foo 23 "bar', 'right unquoted result';

# trim
is b(' la la la ')->trim, 'la la la', 'right trimmed result';

# squish
is b("\n la\nla la \n")->squish, 'la la la', 'right squished result';

# md5_bytes
is unpack('H*', b('foo bar baz ♥')->encode->md5_bytes),
  'a740aeb6e066f158cbf19fd92e890d2d', 'right binary md5 checksum';
is unpack('H*', b('foo bar baz ♥')->encode('UTF-8')->md5_bytes),
  'a740aeb6e066f158cbf19fd92e890d2d', 'right binary md5 checksum';

# md5_sum
is b('foo bar baz')->md5_sum, 'ab07acbb1e496801937adfa772424bf7',
  'right md5 checksum';

# sha1_bytes
is unpack('H*', b('foo bar baz')->sha1_bytes),
  'c7567e8b39e2428e38bf9c9226ac68de4c67dc39', 'right binary sha1 checksum';

# sha1_sum
is b('foo bar baz')->sha1_sum, 'c7567e8b39e2428e38bf9c9226ac68de4c67dc39',
  'right sha1 checksum';

# hmac_sha1_sum
is b('Hi there')->hmac_sha1_sum('abc1234567890'),
  '5344f37e1948dd3ffb07243a4d9201a227abd6e1', 'right hmac sha1 checksum';

# secure_compare
ok b('hello')->secure_compare('hello'), 'values are equal';
ok !b('hell')->secure_compare('hello'), 'values are not equal';

# xor_encode
is b('hello')->xor_encode('foo'), "\x0e\x0a\x03\x0a\x00", 'right result';
is b("\x0e\x0a\x03\x0a\x00")->xor_encode('foo'), 'hello', 'right result';

# Nested bytestreams
my $stream = b(b('test'));
ok !ref $stream->to_string, 'nested bytestream stringified';
$stream = Mojo::ByteStream->new(Mojo::ByteStream->new('test'));
ok !ref $stream->to_string, 'nested bytestream stringified';

# split
$stream = b('1,2,3,4,5');
is_deeply $stream->split(',')->to_array,   [1, 2, 3, 4, 5], 'right elements';
is_deeply $stream->split(qr/,/)->to_array, [1, 2, 3, 4, 5], 'right elements';
is_deeply b('54321')->split('')->to_array, [5, 4, 3, 2, 1], 'right elements';
is_deeply b('')->split('')->to_array,    [], 'no elements';
is_deeply b('')->split(',')->to_array,   [], 'no elements';
is_deeply b('')->split(qr/,/)->to_array, [], 'no elements';
$stream = b('1/2/3');
is $stream->split('/')->map(sub { $_->quote })->join(', '), '"1", "2", "3"',
  'right result';
is $stream->split('/')->map(sub { shift->quote })->join(', '),
  '"1", "2", "3"', 'right result';

# length
is b('foo bar baz')->size, 11, 'size is 11';

# "0"
$stream = b('0');
is $stream->size,      1,   'size is 1';
is $stream->to_string, '0', 'right content';

# clone
$stream = b('foo');
my $clone = $stream->clone;
isnt $stream->b64_encode->to_string, 'foo', 'original changed';
is $clone->to_string, 'foo', 'clone did not change';

# say and autojoin
my $buffer = '';
open my $handle, '>', \$buffer;
b('te', 'st')->say($handle);
{
  local *STDOUT = $handle;
  b(1, 2, 3)->say->quote->say;
}
is $buffer, "test\n123\n\"123\"\n", 'right output';

# slurp
my $file = abs_path catfile(dirname(__FILE__), 'templates', 'exception.mt');
$stream = b($file)->slurp;
is $stream, "test\n% die;\n123\n", 'right content';
$stream = b($file)->slurp->split("\n")->grep(qr/die/)->join;
is $stream, '% die;', 'right content';

# spurt
my $dir = tempdir CLEANUP => 1;
$file = catfile $dir, 'test.txt';
is b("just\nworks!")->spurt($file)->quote, qq{"just\nworks!"}, 'right result';
is b($file)->slurp, "just\nworks!", 'successful roundtrip';

# term_escape
is b("\t\b\r\n\f")->term_escape, "\\x09\\x08\\x0d\n\\x0c", 'right result';

done_testing();
