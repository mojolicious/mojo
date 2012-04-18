use Mojo::Base -strict;

use utf8;

# "Homer, we're going to ask you a few simple yes or no questions.
#  Do you understand?
#  Yes. *lie dectector blows up*"
use Test::More tests => 141;

# Need to be loaded first to trigger edge case
use MIME::Base64;
use MIME::QuotedPrint;
use Mojo::Util 'md5_bytes';
use Mojo::ByteStream 'b';

# camelize
my $stream = b('foo_bar_baz');
is $stream->camelize, 'FooBarBaz', 'right camelized result';
$stream = b('FooBarBaz');
is $stream->camelize, 'FooBarBaz', 'right camelized result';
$stream = b('foo_b_b');
is $stream->camelize, 'FooBB', 'right camelized result';
$stream = b('foo-b_b');
is $stream->camelize, 'Foo::BB', 'right camelized result';
$stream = b('FooBar');
is $stream->camelize, 'FooBar', 'already camelized';
$stream = b('Foo::Bar');
is $stream->camelize, 'Foo::Bar', 'already camelized';

# decamelize
$stream = b('FooBarBaz');
is $stream->decamelize, 'foo_bar_baz', 'right decamelized result';
$stream = b('foo_bar_baz');
is $stream->decamelize, 'foo_bar_baz', 'right decamelized result';
$stream = b('FooBB');
is $stream->decamelize, 'foo_b_b', 'right decamelized result';
$stream = b('Foo::BB');
is $stream->decamelize, 'foo-b_b', 'right decamelized result';

# camelize/decamelize roundtrip
my $original = 'MyApp::Controller::FooBAR';
$stream = b($original);
my $result = $stream->decamelize->to_string;
is "$stream", $result, 'stringified successfully';
isnt $result, $original, 'decamelized result is different';
is $stream->camelize,   $original, 'successful roundtrip';
is $stream->decamelize, $result,   'right decamelized result';
isnt "$stream", $original, 'decamelized result is different';
is $stream->camelize, $original, 'successful roundtrip again';

# b64_encode
$stream = b('foobar$%^&3217');
is $stream->b64_encode, "Zm9vYmFyJCVeJjMyMTc=\n",
  'right base64 encoded result';

# b64_decode
$stream = b("Zm9vYmFyJCVeJjMyMTc=\n");
is $stream->b64_decode, 'foobar$%^&3217', 'right base64 decoded result';

# utf8 b64_encode
$stream = b("foo\x{df}\x{0100}bar%23\x{263a}")->encode->b64_encode;
is "$stream", "Zm9vw5/EgGJhciUyM+KYug==\n", 'right base64 encoded result';

# utf8 b64_decode
$stream = b("Zm9vw5/EgGJhciUyM+KYug==\n")->b64_decode->decode('UTF-8');
is "$stream", "foo\x{df}\x{0100}bar%23\x{263a}",
  'right base64 decoded result';

# utf8 b64_decode
$stream = b("Zm9vw5/EgGJhciUyM+KYug==\n")->b64_decode->decode;
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
$stream = b("foo\x{df}\x{0100}bar\x{263a}")->encode->url_escape;
is "$stream", 'foo%C3%9F%C4%80bar%E2%98%BA', 'right url escaped result';

# utf8 url_unescape
$stream = b('foo%C3%9F%C4%80bar%E2%98%BA')->url_unescape->decode('UTF-8');
is "$stream", "foo\x{df}\x{0100}bar\x{263a}", 'right url unescaped result';

# qp_encode
$stream = b("foo\x{99}bar$%^&3217");
like $stream->qp_encode, qr/^foo\=99bar0\^\&3217/, 'right qp encoded result';

# qp_decode
$stream = b("foo=99bar0^&3217=\n");
is $stream->qp_decode, "foo\x{99}bar$%^&3217", 'right qp decoded result';

# quote
$stream = b('foo; 23 "bar');
is $stream->quote, '"foo; 23 \"bar"', 'right quoted result';
$stream = b('"foo; 23 "bar"');
is $stream->quote, '"\"foo; 23 \"bar\""', 'right quoted result';

# unquote
$stream = b('"foo 23 \"bar"');
is $stream->unquote, 'foo 23 "bar', 'right unquoted result';
$stream = b('"\"foo 23 \"bar\""');
is $stream->unquote, '"foo 23 "bar"', 'right unquoted result';

# md5_bytes
$original = b('foo bar baz ♥')->encode->to_string;
my $copy = $original;
$stream = b($copy);
is unpack('H*', $stream->md5_bytes), 'a740aeb6e066f158cbf19fd92e890d2d',
  'right binary md5 checksum';
is unpack('H*', md5_bytes($copy)), 'a740aeb6e066f158cbf19fd92e890d2d',
  'right binary md5 checksum';
is $copy, $original, 'still equal';

# md5_sum
$stream = b('foo bar baz');
is $stream->md5_sum, 'ab07acbb1e496801937adfa772424bf7', 'right md5 checksum';

# sha1_bytes
$stream = b('foo bar baz');
is unpack('H*', $stream->sha1_bytes),
  'c7567e8b39e2428e38bf9c9226ac68de4c67dc39', 'right binary sha1 checksum';

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
is $stream->to_string, '0', 'right content';

# hmac_md5_sum (RFC 2202)
is b('Hi There')->hmac_md5_sum(chr(0x0b) x 16),
  '9294727a3638bb1c13f48ef8158bfc9d', 'right hmac md5 checksum';
is b('what do ya want for nothing?')->hmac_md5_sum('Jefe'),
  '750c783e6ab0b503eaa86e310a5db738', 'right hmac md5 checksum';
is b(chr(0xdd) x 50)->hmac_md5_sum(chr(0xaa) x 16),
  '56be34521d144c88dbb8c733f0e8b3f6', 'right hmac md5 checksum';
is b(chr(0xcd) x 50)
  ->hmac_md5_sum(
  pack 'H*' => '0102030405060708090a0b0c0d0e0f10111213141516171819'),
  '697eaf0aca3a3aea3a75164746ffaa79', 'right hmac md5 checksum';
is b('Test With Truncation')->hmac_md5_sum(chr(0x0c) x 16),
  '56461ef2342edc00f9bab995690efd4c', 'right hmac md5 checksum';
is b('Test Using Larger Than Block-Size Key - Hash Key First')
  ->hmac_md5_sum(chr(0xaa) x 80), '6b1ab7fe4bd7bf8f0b62e6ce61b9d0cd',
  'right hmac md5 checksum';
is b(
  'Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data')
  ->hmac_md5_sum(chr(0xaa) x 80), '6f630fad67cda0ee1fb1f562db3aa53e',
  'right hmac md5 checksum';
is b('Hi there')->hmac_md5_sum(1234567890),
  'e3b5fab1b3f5b9d1fe391d09fce7b2ae', 'right hmac md5 checksum';

# hmac_sha1_sum (RFC 2202)
is b('Hi There')->hmac_sha1_sum(chr(0x0b) x 20),
  'b617318655057264e28bc0b6fb378c8ef146be00', 'right hmac sha1 checksum';
is b('what do ya want for nothing?')->hmac_sha1_sum('Jefe'),
  'effcdf6ae5eb2fa2d27416d5f184df9c259a7c79', 'right hmac sha1 checksum';
is b(chr(0xdd) x 50)->hmac_sha1_sum(chr(0xaa) x 20),
  '125d7342b9ac11cd91a39af48aa17b4f63f175d3', 'right hmac sha1 checksum';
is b(chr(0xcd) x 50)
  ->hmac_sha1_sum(
  pack 'H*' => '0102030405060708090a0b0c0d0e0f10111213141516171819'),
  '4c9007f4026250c6bc8414f9bf50c86c2d7235da', 'right hmac sha1 checksum';
is b('Test With Truncation')->hmac_sha1_sum(chr(0x0c) x 20),
  '4c1a03424b55e07fe7f27be1d58bb9324a9a5a04', 'right hmac sha1 checksum';
is b('Test Using Larger Than Block-Size Key - Hash Key First')
  ->hmac_sha1_sum(chr(0xaa) x 80), 'aa4ae5e15272d00e95705637ce8a3b55ed402112',
  'right hmac sha1 checksum';
is b(
  'Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data')
  ->hmac_sha1_sum(chr(0xaa) x 80),
  'e8e99d0f45237d786d6bbaa7965c7808bbff1a91', 'right hmac sha1 checksum';
is b('Hi there')->hmac_sha1_sum(1234567890),
  '4fd7160f392dc54308608cae6587e137c62c2e39', 'right hmac sha1 checksum';

# html_escape
$stream = b("foobar'<baz>");
is $stream->html_escape, 'foobar&#39;&lt;baz&gt;',
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
$stream = b('foo&lt;baz&gt;&#x26;&#34;&OElig;&Foo;')->decode('UTF-8')
  ->html_unescape;
is "$stream", "foo<baz>&\"\x{152}&Foo;", 'right html unescaped result';

# html_escape (path)
$stream = b('/usr/local/lib/perl5/site_perl/5.10.0/Mojo/ByteStream.pm')
  ->html_escape;
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

# RFC 3492
my @tests = (
  '(A) Arabic (Egyptian):',
  "\x{0644}\x{064A}\x{0647}\x{0645}\x{0627}\x{0628}\x{062A}\x{0643}"
    . "\x{0644}\x{0645}\x{0648}\x{0634}\x{0639}\x{0631}\x{0628}\x{064A}"
    . "\x{061F}",
  'egbpdaj6bu4bxfgehfvwxn',
  '(B) Chinese (simplified):',
  "\x{4ED6}\x{4EEC}\x{4E3A}\x{4EC0}\x{4E48}\x{4E0D}\x{8BF4}\x{4E2D}"
    . "\x{6587}",
  'ihqwcrb4cv8a8dqg056pqjye',
  '(C) Chinese (traditional):',
  "\x{4ED6}\x{5011}\x{7232}\x{4EC0}\x{9EBD}\x{4E0D}\x{8AAA}\x{4E2D}"
    . "\x{6587}",
  'ihqwctvzc91f659drss3x8bo0yb',
  '(D) Czech: Pro<ccaron>prost<ecaron>nemluv<iacute><ccaron>esky',
  "\x{0050}\x{0072}\x{006F}\x{010D}\x{0070}\x{0072}\x{006F}\x{0073}"
    . "\x{0074}\x{011B}\x{006E}\x{0065}\x{006D}\x{006C}\x{0075}\x{0076}"
    . "\x{00ED}\x{010D}\x{0065}\x{0073}\x{006B}\x{0079}",
  'Proprostnemluvesky-uyb24dma41a',
  '(E) Hebrew:',
  "\x{05DC}\x{05DE}\x{05D4}\x{05D4}\x{05DD}\x{05E4}\x{05E9}\x{05D5}"
    . "\x{05D8}\x{05DC}\x{05D0}\x{05DE}\x{05D3}\x{05D1}\x{05E8}\x{05D9}"
    . "\x{05DD}\x{05E2}\x{05D1}\x{05E8}\x{05D9}\x{05EA}",
  '4dbcagdahymbxekheh6e0a7fei0b',
  '(F) Hindi (Devanagari):',
  "\x{092F}\x{0939}\x{0932}\x{094B}\x{0917}\x{0939}\x{093F}\x{0928}"
    . "\x{094D}\x{0926}\x{0940}\x{0915}\x{094D}\x{092F}\x{094B}\x{0902}"
    . "\x{0928}\x{0939}\x{0940}\x{0902}\x{092C}\x{094B}\x{0932}\x{0938}"
    . "\x{0915}\x{0924}\x{0947}\x{0939}\x{0948}\x{0902}",
  'i1baa7eci9glrd9b2ae1bj0hfcgg6iyaf8o0a1dig0cd',
  '(G) Japanese (kanji and hiragana):',
  "\x{306A}\x{305C}\x{307F}\x{3093}\x{306A}\x{65E5}\x{672C}\x{8A9E}"
    . "\x{3092}\x{8A71}\x{3057}\x{3066}\x{304F}\x{308C}\x{306A}\x{3044}"
    . "\x{306E}\x{304B}",
  'n8jok5ay5dzabd5bym9f0cm5685rrjetr6pdxa',
  '(H) Korean (Hangul syllables):',
  "\x{C138}\x{ACC4}\x{C758}\x{BAA8}\x{B4E0}\x{C0AC}\x{B78C}\x{B4E4}"
    . "\x{C774}\x{D55C}\x{AD6D}\x{C5B4}\x{B97C}\x{C774}\x{D574}\x{D55C}"
    . "\x{B2E4}\x{BA74}\x{C5BC}\x{B9C8}\x{B098}\x{C88B}\x{C744}\x{AE4C}",
  '989aomsvi5e83db1d2a355cv1e0vak1dwrv93d5xbh15a0dt30a5jpsd879ccm6fea98c',
  '(I) Russian (Cyrillic):',
  "\x{043F}\x{043E}\x{0447}\x{0435}\x{043C}\x{0443}\x{0436}\x{0435}"
    . "\x{043E}\x{043D}\x{0438}\x{043D}\x{0435}\x{0433}\x{043E}\x{0432}"
    . "\x{043E}\x{0440}\x{044F}\x{0442}\x{043F}\x{043E}\x{0440}\x{0443}"
    . "\x{0441}\x{0441}\x{043A}\x{0438}",
  'b1abfaaepdrnnbgefbadotcwatmq2g4l',
  '(J) Spanish: Porqu<eacute>nopuedensimplementehablarenEspa<ntilde>ol',
  "\x{0050}\x{006F}\x{0072}\x{0071}\x{0075}\x{00E9}\x{006E}\x{006F}"
    . "\x{0070}\x{0075}\x{0065}\x{0064}\x{0065}\x{006E}\x{0073}\x{0069}"
    . "\x{006D}\x{0070}\x{006C}\x{0065}\x{006D}\x{0065}\x{006E}\x{0074}"
    . "\x{0065}\x{0068}\x{0061}\x{0062}\x{006C}\x{0061}\x{0072}\x{0065}"
    . "\x{006E}\x{0045}\x{0073}\x{0070}\x{0061}\x{00F1}\x{006F}\x{006C}",
  'PorqunopuedensimplementehablarenEspaol-fmd56a',
  '(K) Vietnamese: T<adotbelow>isaoh<odotbelow>kh<ocirc>ngth'
    . '<ecirchookabove>ch<ihookabove>n<oacute>iti<ecircacute>ngVi'
    . '<ecircdotbelow>t',
  "\x{0054}\x{1EA1}\x{0069}\x{0073}\x{0061}\x{006F}\x{0068}\x{1ECD}"
    . "\x{006B}\x{0068}\x{00F4}\x{006E}\x{0067}\x{0074}\x{0068}\x{1EC3}"
    . "\x{0063}\x{0068}\x{1EC9}\x{006E}\x{00F3}\x{0069}\x{0074}\x{0069}"
    . "\x{1EBF}\x{006E}\x{0067}\x{0056}\x{0069}\x{1EC7}\x{0074}",
  'TisaohkhngthchnitingVit-kjcr8268qyxafd2f1b9g',
  '(L) 3<nen>B<gumi><kinpachi><sensei>',
  "\x{0033}\x{5E74}\x{0042}\x{7D44}\x{91D1}\x{516B}\x{5148}\x{751F}",
  '3B-ww4c5e180e575a65lsy2b',
  '(M) <amuro><namie>-with-SUPER-MONKEYS',
  "\x{5B89}\x{5BA4}\x{5948}\x{7F8E}\x{6075}\x{002D}\x{0077}\x{0069}"
    . "\x{0074}\x{0068}\x{002D}\x{0053}\x{0055}\x{0050}\x{0045}\x{0052}"
    . "\x{002D}\x{004D}\x{004F}\x{004E}\x{004B}\x{0045}\x{0059}\x{0053}",
  '-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n',
  '(N) Hello-Another-Way-<sorezore><no><basho>',
  "\x{0048}\x{0065}\x{006C}\x{006C}\x{006F}\x{002D}\x{0041}\x{006E}"
    . "\x{006F}\x{0074}\x{0068}\x{0065}\x{0072}\x{002D}\x{0057}\x{0061}"
    . "\x{0079}\x{002D}\x{305D}\x{308C}\x{305E}\x{308C}\x{306E}\x{5834}"
    . "\x{6240}",
  'Hello-Another-Way--fc4qua05auwb3674vfr0b',
  '(O) <hitotsu><yane><no><shita>2',
  "\x{3072}\x{3068}\x{3064}\x{5C4B}\x{6839}\x{306E}\x{4E0B}\x{0032}",
  '2-u9tlzr9756bt3uc0v',
  '(P) Maji<de>Koi<suru>5<byou><mae>',
  "\x{004D}\x{0061}\x{006A}\x{0069}\x{3067}\x{004B}\x{006F}\x{0069}"
    . "\x{3059}\x{308B}\x{0035}\x{79D2}\x{524D}",
  'MajiKoi5-783gue6qz075azm5e',
  '(Q) <pafii>de<runba>',
  "\x{30D1}\x{30D5}\x{30A3}\x{30FC}\x{0064}\x{0065}\x{30EB}\x{30F3}"
    . "\x{30D0}",
  'de-jg4avhby1noc0d',
  '(R) <sono><supiido><de>',
  "\x{305D}\x{306E}\x{30B9}\x{30D4}\x{30FC}\x{30C9}\x{3067}",
  'd9juau41awczczp',
  '(S) -> $1.00 <-',
  "\x{002D}\x{003E}\x{0020}\x{0024}\x{0031}\x{002E}\x{0030}\x{0030}"
    . "\x{0020}\x{003C}\x{002D}",
  '-> $1.00 <--'
);

for (my $i = 0; $i < @tests; $i += 3) {
  my ($d, $o, $p) = @tests[$i, $i + 1, $i + 2];
  is b($o)->punycode_encode->to_string, $p, "punycode_encode $d";
  is b($p)->punycode_decode->to_string, $o, "punycode_decode $d";
}

# trim
$stream = b(' la la la ')->trim;
is "$stream", 'la la la', 'right trimmed result';
$stream = b(" \n la la la \n ")->trim;
is "$stream", 'la la la', 'right trimmed result';
$stream = b("\n la\nla la \n")->trim;
is "$stream", "la\nla la", 'right trimmed result';
$stream = b(" \nla\nla\nla\n ")->trim;
is "$stream", "la\nla\nla", 'right trimmed result';

# split
$stream = b('1,2,3,4,5');
is_deeply [$stream->split(',')->each],   [1, 2, 3, 4, 5], 'right elements';
is_deeply [$stream->split(qr/,/)->each], [1, 2, 3, 4, 5], 'right elements';
is_deeply [b('54321')->split('')->each], [5, 4, 3, 2, 1], 'right elements';
is_deeply [b('')->split('')->each],    [], 'no elements';
is_deeply [b('')->split(',')->each],   [], 'no elements';
is_deeply [b('')->split(qr/,/)->each], [], 'no elements';
$stream = b('1/2/3');
is $stream->split('/')->map(sub { $_->quote })->join(', '),
  '"1", "2", "3"', 'right result';
is $stream->split('/')->map(sub { shift->quote })->join(', '),
  '"1", "2", "3"', 'right result';

# say and autojoin
my $buffer = '';
open my $handle, '>', \$buffer;
b('te', 'st')->say($handle);
my $stdout = *STDOUT;
*STDOUT = $handle;
b(1, 2, 3)->say;
*STDOUT = $stdout;
is $buffer, "test\n123\n", 'right output';

# Nested bytestreams
$stream = b(b('test'));
ok !ref $stream->to_string, 'nested bytestream stringified';
$stream = Mojo::ByteStream->new(Mojo::ByteStream->new('test'));
ok !ref $stream->to_string, 'nested bytestream stringified';

# Secure compare
ok b('hello')->secure_compare('hello'),  'values are equal';
ok !b('hell')->secure_compare('hello'),  'values are not equal';
ok !b('hallo')->secure_compare('hello'), 'values are not equal';
ok b('0')->secure_compare('0'),          'values are equal';
ok b('1')->secure_compare('1'),          'values are equal';
ok !b('1')->secure_compare('0'),         'values are not equal';
ok !b('0')->secure_compare('1'),         'values are not equal';
ok b('00')->secure_compare('00'),        'values are equal';
ok b('11')->secure_compare('11'),        'values are equal';
ok !b('11')->secure_compare('00'),       'values are not equal';
ok !b('00')->secure_compare('11'),       'values are not equal';
ok b('♥')->secure_compare('♥'),      'values are equal';
ok b('0♥')->secure_compare('0♥'),    'values are equal';
ok b('♥1')->secure_compare('♥1'),    'values are equal';
ok !b('♥')->secure_compare('♥0'),    'values are not equal';
ok !b('0♥')->secure_compare('♥'),    'values are not equal';
ok !b('0♥1')->secure_compare('1♥0'), 'values are not equal';
