use Mojo::Base -strict;

use Test::More;
use Mojo::ByteStream qw(b);

subtest 'Tap into method chain' => sub {
  is b('test')->tap(sub { $$_ .= '1' })->camelize, 'Test1', 'right result';
};

subtest 'camelize' => sub {
  is b('foo_bar_baz')->camelize, 'FooBarBaz', 'right camelized result';
};

subtest 'decamelize' => sub {
  is b('FooBarBaz')->decamelize, 'foo_bar_baz', 'right decamelized result';
};

subtest 'unindent' => sub {
  is b(" test\n  123\n 456\n")->unindent, "test\n 123\n456\n", 'right unindented result';
};

subtest 'b64_encode' => sub {
  is b('foobar$%^&3217')->b64_encode, "Zm9vYmFyJCVeJjMyMTc=\n", 'right Base64 encoded result';
};

subtest 'b64_decode' => sub {
  is b("Zm9vYmFyJCVeJjMyMTc=\n")->b64_decode, 'foobar$%^&3217', 'right Base64 decoded result';
};

subtest 'url_escape' => sub {
  is b('business;23')->url_escape, 'business%3B23', 'right URL escaped result';
};

subtest 'url_unescape' => sub {
  is b('foo%C3%9F%C4%80bar%E2%98%BA')->url_unescape->decode, "foo\x{df}\x{0100}bar\x{263a}",
    'right URL unescaped result';
  is b('foo%C3%9F%C4%80bar%E2%98%BA')->url_unescape->decode('UTF-8'), "foo\x{df}\x{0100}bar\x{263a}",
    'right URL unescaped result';
};

subtest 'html_unescape' => sub {
  is b('&#x3c;foo&#x3E;bar&lt;baz&gt;&#x26;&#34;')->html_unescape, "<foo>bar<baz>&\"", 'right HTML unescaped result';
};

subtest 'xml_escape' => sub {
  is b(qq{la<f>\nbar"baz"'yada\n'&lt;la})->xml_escape, "la&lt;f&gt;\nbar&quot;baz&quot;&#39;yada\n&#39;&amp;lt;la",
    'right XML escaped result';
};

subtest 'punycode_encode' => sub {
  is b('bücher')->punycode_encode, 'bcher-kva', 'right punycode encoded result';
};

subtest 'punycode_decode' => sub {
  is b('bcher-kva')->punycode_decode, 'bücher', 'right punycode decoded result';
};

subtest 'quote' => sub {
  is b('foo; 23 "bar')->quote, '"foo; 23 \"bar"', 'right quoted result';
};

subtest 'unquote' => sub {
  is b('"foo 23 \"bar"')->unquote, 'foo 23 "bar', 'right unquoted result';
};

subtest 'trim' => sub {
  is b(' la la la ')->trim, 'la la la', 'right trimmed result';
};

subtest 'md5_bytes' => sub {
  is unpack('H*', b('foo bar baz ♥')->encode->md5_bytes), 'a740aeb6e066f158cbf19fd92e890d2d',
    'right binary md5 checksum';
  is unpack('H*', b('foo bar baz ♥')->encode('UTF-8')->md5_bytes), 'a740aeb6e066f158cbf19fd92e890d2d',
    'right binary md5 checksum';
};

subtest 'md5_sum' => sub {
  is b('foo bar baz')->md5_sum, 'ab07acbb1e496801937adfa772424bf7', 'right md5 checksum';
};

subtest 'sha1_bytes' => sub {
  is unpack('H*', b('foo bar baz')->sha1_bytes), 'c7567e8b39e2428e38bf9c9226ac68de4c67dc39',
    'right binary sha1 checksum';
};

subtest 'sha1_sum' => sub {
  is b('foo bar baz')->sha1_sum, 'c7567e8b39e2428e38bf9c9226ac68de4c67dc39', 'right sha1 checksum';
};

subtest 'hmac_sha1_sum' => sub {
  is b('Hi there')->hmac_sha1_sum('abc1234567890'), '5344f37e1948dd3ffb07243a4d9201a227abd6e1',
    'right hmac sha1 checksum';
};

subtest 'secure_compare' => sub {
  ok b('hello')->secure_compare('hello'), 'values are equal';
  ok !b('hell')->secure_compare('hello'), 'values are not equal';
};

subtest 'xor_encode' => sub {
  is b('hello')->xor_encode('foo'),                "\x0e\x0a\x03\x0a\x00", 'right result';
  is b("\x0e\x0a\x03\x0a\x00")->xor_encode('foo'), 'hello',                'right result';
};

subtest 'Nested bytestreams' => sub {
  my $stream = b(b('test'));
  ok !ref $stream->to_string, 'nested bytestream stringified';
  $stream = Mojo::ByteStream->new(Mojo::ByteStream->new('test'));
  ok !ref $stream->to_string, 'nested bytestream stringified';
};

subtest 'split' => sub {
  my $stream = b('1,2,3,4,5');
  is_deeply $stream->split(',')->to_array,               [1, 2, 3, 4, 5],             'right elements';
  is_deeply $stream->split(qr/,/)->to_array,             [1, 2, 3, 4, 5],             'right elements';
  is_deeply b('1,2,3,4,5,,,')->split(',')->to_array,     [1, 2, 3, 4, 5],             'right elements';
  is_deeply b('1,2,3,4,5,,,')->split(',', -1)->to_array, [1, 2, 3, 4, 5, '', '', ''], 'right elements';
  is_deeply b('54321')->split('')->to_array,             [5, 4, 3, 2, 1],             'right elements';
  is_deeply b('')->split('')->to_array,                  [],                          'no elements';
  is_deeply b('')->split(',')->to_array,                 [],                          'no elements';
  is_deeply b('')->split(qr/,/)->to_array,               [],                          'no elements';
  $stream = b('1/2/3');
  is $stream->split('/')->map(sub { $_->quote })->join(', '),    '"1", "2", "3"', 'right result';
  is $stream->split('/')->map(sub { shift->quote })->join(', '), '"1", "2", "3"', 'right result';
};

subtest 'length' => sub {
  is b('foo bar baz')->size, 11, 'size is 11';
};

subtest '"0"' => sub {
  my $stream = b('0');
  is $stream->size,      1,   'size is 1';
  is $stream->to_string, '0', 'right content';
};

subtest 'clone' => sub {
  my $stream = b('foo');
  my $clone  = $stream->clone;
  isnt $stream->b64_encode->to_string, 'foo', 'original changed';
  is $clone->to_string,                'foo', 'clone did not change';
};

subtest 'say and autojoin' => sub {
  my $buffer = '';
  open my $handle, '>', \$buffer;
  b('te', 'st')->say($handle);
  {
    local *STDOUT = $handle;
    b(1, 2, 3)->say->quote->say;
  }
  is $buffer, "test\n123\n\"123\"\n", 'right output';
};

subtest 'term_escape' => sub {
  is b("\t\b\r\n\f")->term_escape, "\\x09\\x08\\x0d\n\\x0c", 'right result';
};

subtest 'slugify' => sub {
  is b("Un \x{e9}l\x{e9}phant \x{e0} l'or\x{e9}e du bois")->slugify->to_string, 'un-elephant-a-loree-du-bois',
    'right result';
  is b("Un \x{e9}l\x{e9}phant \x{e0} l'or\x{e9}e du bois")->slugify(1)->to_string,
    "un-\x{e9}l\x{e9}phant-\x{e0}-lor\x{e9}e-du-bois", 'right result';
};

subtest 'gzip/gunzip' => sub {
  my $uncompressed = b('a' x 1000);
  my $compressed   = $uncompressed->clone->gzip;
  isnt $compressed->to_string, $uncompressed->to_string, 'bytestream changed';
  ok $compressed->size < $uncompressed->size, 'bytestream is shorter';
  is $compressed->gunzip->to_string, $uncompressed->to_string, 'same bytestream';
};

subtest 'humanize_bytes' => sub {
  is b(8007188480)->humanize_bytes,  '7.5GiB',  'humanized';
  is b(-8007188480)->humanize_bytes, '-7.5GiB', 'humanized';
};

done_testing();
