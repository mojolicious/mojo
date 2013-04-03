use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use File::Spec::Functions qw(catfile splitdir);
use File::Temp 'tempdir';
use Mojo::DeprecationTest;

use Mojo::Util
  qw(b64_decode b64_encode camelize class_to_file class_to_path decamelize),
  qw(decode encode get_line hmac_md5_sum hmac_sha1_sum html_unescape),
  qw(md5_bytes md5_sum monkey_patch punycode_decode punycode_encode quote),
  qw(secure_compare sha1_bytes sha1_sum slurp spurt squish steady_time trim),
  qw(unquote url_escape url_unescape xml_escape xor_encode);

# camelize
is camelize('foo_bar_baz'), 'FooBarBaz', 'right camelized result';
is camelize('FooBarBaz'),   'FooBarBaz', 'right camelized result';
is camelize('foo_b_b'),     'FooBB',     'right camelized result';
is camelize('foo-b_b'),     'Foo::BB',   'right camelized result';
is camelize('FooBar'),      'FooBar',    'already camelized';
is camelize('Foo::Bar'),    'Foo::Bar',  'already camelized';

# decamelize
is decamelize('FooBarBaz'),   'foo_bar_baz', 'right decamelized result';
is decamelize('foo_bar_baz'), 'foo_bar_baz', 'right decamelized result';
is decamelize('FooBB'),       'foo_b_b',     'right decamelized result';
is decamelize('Foo::BB'),     'foo-b_b',     'right decamelized result';

# class_to_file
is class_to_file('Foo::Bar'),     'foo_bar',     'right file';
is class_to_file('FooBar'),       'foo_bar',     'right file';
is class_to_file('FOOBar'),       'foobar',      'right file';
is class_to_file('FOOBAR'),       'foobar',      'right file';
is class_to_file('FOO::Bar'),     'foobar',      'right file';
is class_to_file('FooBAR'),       'foo_bar',     'right file';
is class_to_file('Foo::BAR'),     'foo_bar',     'right file';
is class_to_file("Foo'BAR"),      'foo_bar',     'right file';
is class_to_file("Foo'Bar::Baz"), 'foo_bar_baz', 'right file';

# class_to_path
is class_to_path('Foo::Bar'),      'Foo/Bar.pm',     'right path';
is class_to_path("Foo'Bar"),       'Foo/Bar.pm',     'right path';
is class_to_path("Foo'Bar::Baz"),  'Foo/Bar/Baz.pm', 'right path';
is class_to_path("Foo::Bar'Baz"),  'Foo/Bar/Baz.pm', 'right path';
is class_to_path("Foo::Bar::Baz"), 'Foo/Bar/Baz.pm', 'right path';
is class_to_path("Foo'Bar'Baz"),   'Foo/Bar/Baz.pm', 'right path';

# get_line
my $buffer = "foo\x0d\x0abar\x0dbaz\x0ayada\x0d\x0a";
is get_line(\$buffer), 'foo', 'right line';
is $buffer, "bar\x0dbaz\x0ayada\x0d\x0a", 'right buffer content';
is get_line(\$buffer), "bar\x0dbaz", 'right line';
is $buffer, "yada\x0d\x0a", 'right buffer content';
is get_line(\$buffer), 'yada', 'right line';
is $buffer, '', 'no buffer content';
is get_line(\$buffer), undef, 'no line';

# b64_encode
is b64_encode('foobar$%^&3217'), "Zm9vYmFyJCVeJjMyMTc=\n",
  'right base64 encoded result';

# b64_decode
is b64_decode("Zm9vYmFyJCVeJjMyMTc=\n"), 'foobar$%^&3217',
  'right base64 decoded result';

# b64_encode (UTF-8)
is b64_encode(encode 'UTF-8', "foo\x{df}\x{0100}bar%23\x{263a}"),
  "Zm9vw5/EgGJhciUyM+KYug==\n", 'right base64 encoded result';

# b64_decode (UTF-8)
is decode('UTF-8', b64_decode "Zm9vw5/EgGJhciUyM+KYug==\n"),
  "foo\x{df}\x{0100}bar%23\x{263a}", 'right base64 decoded result';

# b64_encode (custom line ending)
is b64_encode('foobar$%^&3217', ''), 'Zm9vYmFyJCVeJjMyMTc=',
  'right base64 encoded result';

# decode (invalid UTF-8)
is decode('UTF-8', "\x{1000}"), undef, 'decoding invalid UTF-8 worked';

# decode (invalid encoding)
is decode('does_not_exist', ''), undef,
  'decoding with invalid encoding worked';

# encode (invalid encoding)
eval { encode('does_not_exist', '') };
like $@, qr/Unknown encoding 'does_not_exist'/, 'right error';

# url_escape
is url_escape('business;23'), 'business%3B23', 'right url escaped result';

# url_escape (custom pattern)
is url_escape('&business;23', 's&'), '%26bu%73ine%73%73;23',
  'right url escaped result';

# url_escape (nothing to escape)
is url_escape('foobar123-._~'), 'foobar123-._~', 'right url escaped result';

# url_unescape
is url_unescape('business%3B23'), 'business;23', 'right url unescaped result';

# UTF-8 url_escape
is url_escape(encode 'UTF-8', "foo\x{df}\x{0100}bar\x{263a}"),
  'foo%C3%9F%C4%80bar%E2%98%BA', 'right url escaped result';

# UTF-8 url_unescape
is decode('UTF-8', url_unescape 'foo%C3%9F%C4%80bar%E2%98%BA'),
  "foo\x{df}\x{0100}bar\x{263a}", 'right url unescaped result';

# html_unescape
is html_unescape('&#x3c;foo&#x3E;bar&lt;baz&gt;&#x26;&#34;'),
  "<foo>bar<baz>&\"", 'right html unescaped result';

# html_unescape (special entities)
is html_unescape('foo &CounterClockwiseContourIntegral; bar &sup1baz'),
  "foo \x{2233} bar \x{00b9}baz", 'right html unescaped result';

# html_unescape (multi-character entity)
is html_unescape(decode 'UTF-8', '&acE;'), "\x{223e}\x{0333}",
  'right html unescaped result';

# html_unescape (apos)
is html_unescape('foobar&apos;&lt;baz&gt;&#x26;&#34;'), "foobar'<baz>&\"",
  'right html unescaped result';

# html_unescape (nothing to unescape)
is html_unescape('foobar'), 'foobar', 'right html unescaped result';

# html_unescape (relaxed)
is html_unescape('&Ltf&amp&0oo&nbspba;&ltr'), "&Ltf&&0oo\x{00a0}ba;<r",
  'right html unescaped result';

# html_unescape (UTF-8)
is html_unescape(decode 'UTF-8', 'foo&lt;baz&gt;&#x26;&#34;&OElig;&Foo;'),
  "foo<baz>&\"\x{152}&Foo;", 'right html unescaped result';

# xml_escape
is xml_escape(qq{la<f>\nbar"baz"'yada\n'&lt;la}),
  "la&lt;f&gt;\nbar&quot;baz&quot;&#39;yada\n&#39;&amp;lt;la",
  'right xml escaped result';

# xml_escape (UTF-8 with nothing to escape)
is xml_escape('привет'), 'привет', 'right xml escaped result';

# xml_escape (UTF-8)
is xml_escape('привет<foo>'), 'привет&lt;foo&gt;',
  'right xml escaped result';

# punycode_encode
is punycode_encode('bücher'), 'bcher-kva', 'right punycode encoded result';

# punycode_decode
is punycode_decode('bcher-kva'), 'bücher', 'right punycode decoded result';

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
  is punycode_encode($o), $p, "punycode_encode $d";
  is punycode_decode($p), $o, "punycode_decode $d";
}

# quote
is quote('foo; 23 "bar'),   '"foo; 23 \"bar"',     'right quoted result';
is quote('"foo; 23 "bar"'), '"\"foo; 23 \"bar\""', 'right quoted result';

# unquote
is unquote('"foo 23 \"bar"'),     'foo 23 "bar',   'right unquoted result';
is unquote('"\"foo 23 \"bar\""'), '"foo 23 "bar"', 'right unquoted result';

# trim
is trim(' la la  la '),      'la la  la', 'right trimmed result';
is trim(" \n la la la \n "), 'la la la',  'right trimmed result';
is trim("\n la\nla la \n"),  "la\nla la", 'right trimmed result';
is trim(" \nla \n  \t\nla\nla\n "), "la \n  \t\nla\nla",
  'right trimmed result';

# squish
is squish(' la la  la '),             'la la la', 'right squished result';
is squish("\n la\nla la \n"),         'la la la', 'right squished result';
is squish(" \nla \n  \t\nla\nla\n "), 'la la la', 'right squished result';

# md5_bytes
is unpack('H*', md5_bytes(encode 'UTF-8', 'foo bar baz ♥')),
  'a740aeb6e066f158cbf19fd92e890d2d', 'right binary md5 checksum';

# md5_sum
is md5_sum('foo bar baz'), 'ab07acbb1e496801937adfa772424bf7',
  'right md5 checksum';

# sha1_bytes
is unpack('H*', sha1_bytes 'foo bar baz'),
  'c7567e8b39e2428e38bf9c9226ac68de4c67dc39', 'right binary sha1 checksum';

# sha1_sum
is sha1_sum('foo bar baz'), 'c7567e8b39e2428e38bf9c9226ac68de4c67dc39',
  'right sha1 checksum';

# hmac_md5_sum (RFC 2202)
is hmac_md5_sum('Hi There', chr(0x0b) x 16),
  '9294727a3638bb1c13f48ef8158bfc9d', 'right hmac md5 checksum';
is hmac_md5_sum('what do ya want for nothing?', 'Jefe'),
  '750c783e6ab0b503eaa86e310a5db738', 'right hmac md5 checksum';
is hmac_md5_sum(chr(0xdd) x 50, chr(0xaa) x 16),
  '56be34521d144c88dbb8c733f0e8b3f6', 'right hmac md5 checksum';
is hmac_md5_sum(chr(0xcd) x 50,
  pack 'H*' => '0102030405060708090a0b0c0d0e0f10111213141516171819'),
  '697eaf0aca3a3aea3a75164746ffaa79', 'right hmac md5 checksum';
is hmac_md5_sum('Test With Truncation', chr(0x0c) x 16),
  '56461ef2342edc00f9bab995690efd4c', 'right hmac md5 checksum';
is hmac_md5_sum('Test Using Larger Than Block-Size Key - Hash Key First',
  chr(0xaa) x 80),
  '6b1ab7fe4bd7bf8f0b62e6ce61b9d0cd', 'right hmac md5 checksum';
is hmac_md5_sum(
  'Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data',
  chr(0xaa) x 80
  ),
  '6f630fad67cda0ee1fb1f562db3aa53e', 'right hmac md5 checksum';
is hmac_md5_sum('Hi there', 1234567890), 'e3b5fab1b3f5b9d1fe391d09fce7b2ae',
  'right hmac md5 checksum';

# hmac_sha1_sum (RFC 2202)
is hmac_sha1_sum('Hi There', chr(0x0b) x 20),
  'b617318655057264e28bc0b6fb378c8ef146be00', 'right hmac sha1 checksum';
is hmac_sha1_sum('what do ya want for nothing?', 'Jefe'),
  'effcdf6ae5eb2fa2d27416d5f184df9c259a7c79', 'right hmac sha1 checksum';
is hmac_sha1_sum(chr(0xdd) x 50, chr(0xaa) x 20),
  '125d7342b9ac11cd91a39af48aa17b4f63f175d3', 'right hmac sha1 checksum';
is hmac_sha1_sum(chr(0xcd) x 50,
  pack 'H*' => '0102030405060708090a0b0c0d0e0f10111213141516171819'),
  '4c9007f4026250c6bc8414f9bf50c86c2d7235da', 'right hmac sha1 checksum';
is hmac_sha1_sum('Test With Truncation', chr(0x0c) x 20),
  '4c1a03424b55e07fe7f27be1d58bb9324a9a5a04', 'right hmac sha1 checksum';
is hmac_sha1_sum('Test Using Larger Than Block-Size Key - Hash Key First',
  chr(0xaa) x 80),
  'aa4ae5e15272d00e95705637ce8a3b55ed402112', 'right hmac sha1 checksum';
is hmac_sha1_sum(
  'Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data',
  chr(0xaa) x 80
  ),
  'e8e99d0f45237d786d6bbaa7965c7808bbff1a91', 'right hmac sha1 checksum';
is hmac_sha1_sum('Hi there', 1234567890),
  '4fd7160f392dc54308608cae6587e137c62c2e39', 'right hmac sha1 checksum';

# secure_compare
ok secure_compare('hello', 'hello'), 'values are equal';
ok !secure_compare('hell',  'hello'), 'values are not equal';
ok !secure_compare('hallo', 'hello'), 'values are not equal';
ok secure_compare('0', '0'), 'values are equal';
ok secure_compare('1', '1'), 'values are equal';
ok !secure_compare('1', '0'), 'values are not equal';
ok !secure_compare('0', '1'), 'values are not equal';
ok secure_compare('00', '00'), 'values are equal';
ok secure_compare('11', '11'), 'values are equal';
ok !secure_compare('11', '00'), 'values are not equal';
ok !secure_compare('00', '11'), 'values are not equal';
ok secure_compare('♥',  '♥'),  'values are equal';
ok secure_compare('0♥', '0♥'), 'values are equal';
ok secure_compare('♥1', '♥1'), 'values are equal';
ok !secure_compare('♥',   '♥0'),  'values are not equal';
ok !secure_compare('0♥',  '♥'),   'values are not equal';
ok !secure_compare('0♥1', '1♥0'), 'values are not equal';

# xor_encode
is xor_encode('hello', 'foo'), "\x0e\x0a\x03\x0a\x00", 'right result';
is xor_encode("\x0e\x0a\x03\x0a\x00", 'foo'), 'hello', 'right result';
is xor_encode('hello world', 'x'),
  "\x10\x1d\x14\x14\x17\x58\x0f\x17\x0a\x14\x1c", 'right result';
is xor_encode("\x10\x1d\x14\x14\x17\x58\x0f\x17\x0a\x14\x1c", 'x'),
  'hello world', 'right result';
is xor_encode('hello', '123456789'), "\x59\x57\x5f\x58\x5a", 'right result';
is xor_encode("\x59\x57\x5f\x58\x5a", '123456789'), 'hello', 'right result';

# slurp
is slurp(catfile(splitdir($FindBin::Bin), qw(templates exception.mt))),
  "test\n% die;\n123\n", 'right content';

# spurt
my $dir = tempdir CLEANUP => 1;
my $file = catfile $dir, 'test.txt';
spurt "just\nworks!", $file;
is slurp($file), "just\nworks!", 'successful roundtrip';

# steady_time
like steady_time, qr/^\d+\.\d+$/, 'high resolution time';

# monkey_patch
{

  package MojoMonkeyTest;
  sub foo {'foo'}
}
ok !!MojoMonkeyTest->can('foo'), 'function "foo" exists';
is MojoMonkeyTest::foo(), 'foo', 'right result';
ok !MojoMonkeyTest->can('bar'), 'function "bar" does not exist';
monkey_patch 'MojoMonkeyTest', bar => sub {'bar'};
ok !!MojoMonkeyTest->can('bar'), 'function "bar" exists';
is MojoMonkeyTest::bar(), 'bar', 'right result';
monkey_patch 'MojoMonkeyTest', foo => sub {'baz'};
ok !!MojoMonkeyTest->can('foo'), 'function "foo" exists';
is MojoMonkeyTest::foo(), 'baz', 'right result';
ok !MojoMonkeyTest->can('yin'),  'function "yin" does not exist';
ok !MojoMonkeyTest->can('yang'), 'function "yang" does not exist';
monkey_patch 'MojoMonkeyTest',
  yin  => sub {'yin'},
  yang => sub {'yang'};
ok !!MojoMonkeyTest->can('yin'), 'function "yin" exists';
is MojoMonkeyTest::yin(), 'yin', 'right result';
ok !!MojoMonkeyTest->can('yang'), 'function "yang" exists';
is MojoMonkeyTest::yang(), 'yang', 'right result';

# deprecated
{
  my ($warn, $die) = @_;
  local $SIG{__WARN__} = sub { $warn = shift };
  local $SIG{__DIE__}  = sub { $die  = shift };
  is Mojo::DeprecationTest::foo(), 'bar', 'right result';
  like $warn, qr/foo is DEPRECATED at .*util\.t line \d+/, 'right warning';
  ok !$die, 'no exception';
  ($warn, $die) = ();
  local $ENV{MOJO_FATAL_DEPRECATIONS} = 1;
  ok !eval { Mojo::DeprecationTest::foo() }, 'no result';
  ok !$warn, 'no warning';
  like $die, qr/foo is DEPRECATED at .*util\.t line \d+/, 'right exception';
}

done_testing();
