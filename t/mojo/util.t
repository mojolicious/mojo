use Mojo::Base -strict;

use Mojo::File qw(curfile);
use lib curfile->sibling('lib')->to_string;

use Test::More;
use Mojo::ByteStream qw(b);
use Mojo::DeprecationTest;
use Sub::Util qw(subname);

use Mojo::Util qw(b64_decode b64_encode camelize class_to_file class_to_path decamelize decode dumper encode),
  qw(extract_usage getopt gunzip gzip hmac_sha1_sum hmac_sha256_sum html_unescape html_attr_unescape humanize_bytes),
  qw(md5_bytes md5_sum monkey_patch network_contains punycode_decode punycode_encode quote scope_guard secure_compare),
  qw(sha1_bytes sha256_bytes sha1_sum sha256_sum slugify split_cookie_header split_header steady_time tablify),
  qw(term_escape trim unindent unquote url_escape url_unescape xml_escape xor_encode);

subtest 'camelize' => sub {
  is camelize('foo_bar_baz'), 'FooBarBaz', 'right camelized result';
  is camelize('FooBarBaz'),   'FooBarBaz', 'right camelized result';
  is camelize('foo_b_b'),     'FooBB',     'right camelized result';
  is camelize('foo-b_b'),     'Foo::BB',   'right camelized result';
  is camelize('FooBar'),      'FooBar',    'already camelized';
  is camelize('Foo::Bar'),    'Foo::Bar',  'already camelized';
};

subtest 'decamelize' => sub {
  is decamelize('FooBarBaz'),   'foo_bar_baz', 'right decamelized result';
  is decamelize('foo_bar_baz'), 'foo_bar_baz', 'right decamelized result';
  is decamelize('FooBB'),       'foo_b_b',     'right decamelized result';
  is decamelize('Foo::BB'),     'foo-b_b',     'right decamelized result';
};

subtest 'class_to_file' => sub {
  is class_to_file('Foo::Bar'),     'foo_bar',     'right file';
  is class_to_file('FooBar'),       'foo_bar',     'right file';
  is class_to_file('FOOBar'),       'foobar',      'right file';
  is class_to_file('FOOBAR'),       'foobar',      'right file';
  is class_to_file('FOO::Bar'),     'foobar',      'right file';
  is class_to_file('FooBAR'),       'foo_bar',     'right file';
  is class_to_file('Foo::BAR'),     'foo_bar',     'right file';
  is class_to_file("Foo'BAR"),      'foo_bar',     'right file';
  is class_to_file("Foo'Bar::Baz"), 'foo_bar_baz', 'right file';
};

subtest 'class_to_path' => sub {
  is class_to_path('Foo::Bar'),      'Foo/Bar.pm',     'right path';
  is class_to_path("Foo'Bar"),       'Foo/Bar.pm',     'right path';
  is class_to_path("Foo'Bar::Baz"),  'Foo/Bar/Baz.pm', 'right path';
  is class_to_path("Foo::Bar'Baz"),  'Foo/Bar/Baz.pm', 'right path';
  is class_to_path("Foo::Bar::Baz"), 'Foo/Bar/Baz.pm', 'right path';
  is class_to_path("Foo'Bar'Baz"),   'Foo/Bar/Baz.pm', 'right path';
};

subtest 'split_header' => sub {
  is_deeply split_header(''), [], 'right result';
  is_deeply split_header('foo=b=a=r'), [['foo', 'b=a=r']], 'right result';
  is_deeply split_header('a=b ,, , c=d ;; ; e=f g h=i'), [['a', 'b'], ['c', 'd', 'e', 'f', 'g', undef, 'h', 'i']],
    'right result';
  is_deeply split_header(',,foo,, ,bar'),     [['foo', undef], ['bar', undef]],                 'right result';
  is_deeply split_header(';;foo; ; ;bar'),    [['foo', undef, 'bar', undef]],                   'right result';
  is_deeply split_header('foo=;bar=""'),      [['foo', '', 'bar', '']],                         'right result';
  is_deeply split_header('foo=bar baz=yada'), [['foo', 'bar', 'baz', 'yada']],                  'right result';
  is_deeply split_header('foo,bar,baz'),      [['foo', undef], ['bar', undef], ['baz', undef]], 'right result';
  is_deeply split_header('f "o" o , ba  r'), [['f', undef, '"o"', undef, 'o', undef], ['ba', undef, 'r', undef]],
    'right result';
  is_deeply split_header('foo="b,; a\" r\"\\\\"'), [['foo', 'b,; a" r"\\']], 'right result';
  is_deeply split_header('foo = "b a\" r\"\\\\"; bar="ba z"'), [['foo', 'b a" r"\\', 'bar', 'ba z']], 'right result';
  my $header = q{</foo/bar>; rel="x"; t*=UTF-8'de'a%20b};
  my $tree   = [['</foo/bar>', undef, 'rel', 'x', 't*', 'UTF-8\'de\'a%20b']];
  is_deeply split_header($header), $tree, 'right result';
  $header = 'a=b c; A=b.c; D=/E; a-b=3; expires=Thu, 07 Aug 2008 07:07:59 GMT; Ab;';
  $tree   = [
    ['a',  'b',   'c',   undef, 'A',    'b.c', 'D',        '/E',  'a-b', '3',   'expires', 'Thu'],
    ['07', undef, 'Aug', undef, '2008', undef, '07:07:59', undef, 'GMT', undef, 'Ab',      undef]
  ];
  is_deeply split_header($header), $tree, 'right result';
};

subtest 'split_cookie_header' => sub {
  is_deeply split_cookie_header(''), [], 'right result';
  is_deeply split_cookie_header('a=b; expires=Thu, 07 Aug 2008 07:07:59 GMT,c=d'),
    [['a', 'b', 'expires', 'Thu, 07 Aug 2008 07:07:59 GMT'], ['c', 'd']], 'right result';
  is_deeply split_cookie_header('a=b; expires=Tuesday, 09-Nov-1999 23:12:40 GMT, c=d'),
    [['a', 'b', 'expires', 'Tuesday, 09-Nov-1999 23:12:40 GMT'], ['c', 'd']], 'right result';
  is_deeply split_cookie_header('a=b; expires=Tuesday, 09-Nov-1999 23:12:40 GMT;, c=d;'),
    [['a', 'b', 'expires', 'Tuesday, 09-Nov-1999 23:12:40 GMT'], ['c', 'd']], 'right result';
  is_deeply split_cookie_header('a=b; expires=Sun,06  Nov  1994  08:49:37  UTC; path=/'),
    [['a', 'b', 'expires', 'Sun,06  Nov  1994  08:49:37  UTC', 'path', '/']], 'right result';
  is_deeply split_cookie_header('a=b ; expires = Sunday 06 Nov 94 08:49:37UTC ; path=/'),
    [['a', 'b', 'expires', 'Sunday 06 Nov 94 08:49:37UTC', 'path', '/']], 'right result';
  my $header = 'expires=Thu, 07 Aug 2008 07:07:59 GMT, a=b';
  my $tree
    = [['expires', 'Thu'], ['07', undef, 'Aug', undef, '2008', undef, '07:07:59', undef, 'GMT', undef], ['a', 'b']];
  is_deeply split_cookie_header($header), $tree, 'right result';
};

subtest 'extract_usage' => sub {
  is extract_usage,                                      "extract_usage test!\n",                  'right result';
  is extract_usage(curfile->sibling('lib', 'myapp.pl')), "USAGE: myapp.pl daemon\n\n test\n123\n", 'right result';
};

=head1 SYNOPSIS

  extract_usage test!

=cut

subtest 'getopt' => sub {
  getopt ['--charset', 'UTF-8'], 'c|charset=s' => \my $charset;
  is $charset, 'UTF-8', 'right string';
  my $array = ['-t', 'test', '-h', '--whatever', 'Whatever!', 'stuff'];
  getopt $array, ['pass_through'], 't|test=s' => \my $test;
  is $test, 'test', 'right string';
  is_deeply $array, ['-h', '--whatever', 'Whatever!', 'stuff'], 'right structure';
  getopt $array, 'h' => \my $flag, 'w|whatever=s' => \my $whatever;
  ok $flag, 'flag has been set';
  is $whatever, 'Whatever!', 'right string';
  is_deeply $array, ['stuff'], 'right structure';
  {
    local @ARGV = ('--charset', 'UTF-16', 'test');
    getopt 'c|charset=s' => \my @charset;
    is_deeply \@charset, ['UTF-16'], 'right structure';
    is_deeply \@ARGV,    ['test'],   'right structure';
  }
};

subtest 'getopt (return value)' => sub {
  local $SIG{__WARN__} = sub { };

  my $return = getopt ['--lang', 'de'], 'l|lang=s' => \my $lang;
  is $lang, 'de', 'right result';
  ok $return, 'right return value';

  $lang   = undef;
  $return = getopt ['--lnag', 'de'], 'l|lang=s' => \$lang;
  is $lang, undef, 'right result';
  ok !$return, 'right return value';

  $lang   = undef;
  $return = getopt ['--lnag', 'de', '--lang', 'de'], 'l|lang=s' => \$lang;
  is $lang, 'de', 'right result';
  ok !$return, 'right return value';
};

subtest 'unindent' => sub {
  is unindent(" test\n  123\n 456\n"),              "test\n 123\n456\n",              'right unindented result';
  is unindent("\ttest\n\t\t123\n\t456\n"),          "test\n\t123\n456\n",             'right unindented result';
  is unindent("\t \ttest\n\t \t\t123\n\t \t456\n"), "test\n\t123\n456\n",             'right unindented result';
  is unindent("\n\n\n test\n  123\n 456\n"),        "\n\n\ntest\n 123\n456\n",        'right unindented result';
  is unindent("   test\n    123\n   456\n"),        "test\n 123\n456\n",              'right unindented result';
  is unindent("    test\n  123\n   456\n"),         "  test\n123\n 456\n",            'right unindented result';
  is unindent("test\n123\n"),                       "test\n123\n",                    'right unindented result';
  is unindent(" test\n\n 123\n"),                   "test\n\n123\n",                  'right unindented result';
  is unindent('  test'),                            'test',                           'right unindented result';
  is unindent(" te st\r\n\r\n  1 2 3\r\n 456\r\n"), "te st\r\n\r\n 1 2 3\r\n456\r\n", 'right unindented result';
};

subtest 'b64_encode' => sub {
  is b64_encode('foobar$%^&3217'), "Zm9vYmFyJCVeJjMyMTc=\n", 'right Base64 encoded result';
};

subtest 'b64_decode' => sub {
  is b64_decode("Zm9vYmFyJCVeJjMyMTc=\n"), 'foobar$%^&3217', 'right Base64 decoded result';
};

subtest 'b64_encode (UTF-8)' => sub {
  is b64_encode(encode 'UTF-8', "foo\x{df}\x{0100}bar%23\x{263a}"), "Zm9vw5/EgGJhciUyM+KYug==\n",
    'right Base64 encoded result';
};

subtest 'b64_decode (UTF-8)' => sub {
  is decode('UTF-8', b64_decode "Zm9vw5/EgGJhciUyM+KYug==\n"), "foo\x{df}\x{0100}bar%23\x{263a}",
    'right Base64 decoded result';
};

subtest 'b64_encode (custom line ending)' => sub {
  is b64_encode('foobar$%^&3217', ''), 'Zm9vYmFyJCVeJjMyMTc=', 'right Base64 encoded result';
};

subtest 'decode (invalid UTF-8)' => sub {
  is decode('UTF-8', "\x{1000}"), undef, 'decoding invalid UTF-8 worked';
};

subtest 'decode (invalid encoding)' => sub {
  is decode('does_not_exist', ''), undef, 'decoding with invalid encoding worked';
};

subtest 'encode (invalid encoding)' => sub {
  eval { encode('does_not_exist', '') };
  like $@, qr/Unknown encoding 'does_not_exist'/, 'right error';
};

subtest 'url_escape' => sub {
  is url_escape('business;23'), 'business%3B23', 'right URL escaped result';
};

subtest 'url_escape (custom pattern)' => sub {
  is url_escape('&business;23', 's&'), '%26bu%73ine%73%73;23', 'right URL escaped result';
};

subtest 'url_escape (nothing to escape)' => sub {
  is url_escape('foobar123-._~'), 'foobar123-._~', 'no changes';
};

subtest 'url_unescape' => sub {
  is url_unescape('business%3B23'), 'business;23', 'right URL unescaped result';
};

subtest 'UTF-8 url_escape' => sub {
  is url_escape(encode 'UTF-8', "foo\x{df}\x{0100}bar\x{263a}"), 'foo%C3%9F%C4%80bar%E2%98%BA',
    'right URL escaped result';
};

subtest 'UTF-8 url_unescape' => sub {
  is decode('UTF-8', url_unescape 'foo%C3%9F%C4%80bar%E2%98%BA'), "foo\x{df}\x{0100}bar\x{263a}",
    'right URL unescaped result';
};

subtest 'html_unescape' => sub {
  is html_unescape('&#x3c;foo&#x3E;bar&lt;baz&gt;&#x0026;&#34;'), "<foo>bar<baz>&\"",   'right HTML unescaped result';
  is html_unescape('foo&lt;baz&gt;&#x26;&#34;&OElig;&Foo;'), "foo<baz>&\"\x{152}&Foo;", 'right HTML unescaped result';
};

subtest 'html_unescape (special entities)' => sub {
  is html_unescape('foo &#x2603; &CounterClockwiseContourIntegral; bar &sup1baz'), "foo ☃ \x{2233} bar ¹baz",
    'right HTML unescaped result';
};

subtest 'html_unescape (multi-character entity)' => sub {
  is html_unescape('&acE;'), "\x{223e}\x{0333}", 'right HTML unescaped result';
};

subtest 'html_unescape (apos)' => sub {
  is html_unescape('foobar&apos;&lt;baz&gt;&#x26;&#34;'), "foobar'<baz>&\"", 'right HTML unescaped result';
};

subtest 'html_unescape (nothing to unescape)' => sub {
  is html_unescape('foobar'), 'foobar', 'no changes';
};

subtest 'html_unescape (relaxed)' => sub {
  is html_unescape('&0&Ltf&amp&0oo&nbspba;&ltr'), "&0&Ltf&&0oo\x{00a0}ba;<r", 'right HTML unescaped result';
};

subtest 'html_attr_unescape' => sub {
  is html_attr_unescape('/?foo&lt=bar'),  '/?foo&lt=bar', 'right HTML unescaped result';
  is html_attr_unescape('/?f&ltoo=bar'),  '/?f&ltoo=bar', 'right HTML unescaped result';
  is html_attr_unescape('/?f&lt-oo=bar'), '/?f<-oo=bar',  'right HTML unescaped result';
  is html_attr_unescape('/?foo=&lt'),     '/?foo=<',      'right HTML unescaped result';
  is html_attr_unescape('/?f&lt;oo=bar'), '/?f<oo=bar',   'right HTML unescaped result';
};

subtest 'url_unescape (bengal numbers with nothing to unescape)' => sub {
  is html_unescape('&#০৩৯;&#x০৩৯;'), '&#০৩৯;&#x০৩৯;', 'no changes';
};

subtest 'xml_escape' => sub {
  is xml_escape(qq{la<f>\nbar"baz"'yada\n'&lt;la}), "la&lt;f&gt;\nbar&quot;baz&quot;&#39;yada\n&#39;&amp;lt;la",
    'right XML escaped result';
  is xml_escape('привет<foo>'), 'привет&lt;foo&gt;', 'right XML escaped result';
};

subtest 'xml_escape (nothing to escape)' => sub {
  is xml_escape('привет'), 'привет', 'no changes';
};

subtest 'xml_escape (XSS)' => sub {
  is xml_escape('<p>'),    '&lt;p&gt;', 'right XSS escaped result';
  is xml_escape(b('<p>')), '<p>',       'right XSS escaped result';
};

subtest 'punycode_encode' => sub {
  is punycode_encode('bücher'), 'bcher-kva', 'right punycode encoded result';
};

subtest 'punycode_decode' => sub {
  is punycode_decode('bcher-kva'), 'bücher', 'right punycode decoded result';
};

subtest 'RFC 3492' => sub {
  my @tests = (
    '(A) Arabic (Egyptian):',
    "\x{0644}\x{064a}\x{0647}\x{0645}\x{0627}\x{0628}\x{062a}\x{0643}"
      . "\x{0644}\x{0645}\x{0648}\x{0634}\x{0639}\x{0631}\x{0628}\x{064a}"
      . "\x{061f}",
    'egbpdaj6bu4bxfgehfvwxn',
    '(B) Chinese (simplified):',
    "\x{4ed6}\x{4eec}\x{4e3a}\x{4ec0}\x{4e48}\x{4e0d}\x{8bf4}\x{4e2d}" . "\x{6587}",
    'ihqwcrb4cv8a8dqg056pqjye',
    '(C) Chinese (traditional):',
    "\x{4ed6}\x{5011}\x{7232}\x{4ec0}\x{9ebd}\x{4e0d}\x{8aaa}\x{4e2d}" . "\x{6587}",
    'ihqwctvzc91f659drss3x8bo0yb',
    '(D) Czech: Pro<ccaron>prost<ecaron>nemluv<iacute><ccaron>esky',
    "\x{0050}\x{0072}\x{006f}\x{010d}\x{0070}\x{0072}\x{006f}\x{0073}"
      . "\x{0074}\x{011b}\x{006e}\x{0065}\x{006d}\x{006c}\x{0075}\x{0076}"
      . "\x{00ed}\x{010d}\x{0065}\x{0073}\x{006b}\x{0079}",
    'Proprostnemluvesky-uyb24dma41a',
    '(E) Hebrew:',
    "\x{05dc}\x{05de}\x{05d4}\x{05d4}\x{05dd}\x{05e4}\x{05e9}\x{05d5}"
      . "\x{05d8}\x{05dc}\x{05d0}\x{05de}\x{05d3}\x{05d1}\x{05e8}\x{05d9}"
      . "\x{05dd}\x{05e2}\x{05d1}\x{05e8}\x{05d9}\x{05ea}",
    '4dbcagdahymbxekheh6e0a7fei0b',
    '(F) Hindi (Devanagari):',
    "\x{092f}\x{0939}\x{0932}\x{094b}\x{0917}\x{0939}\x{093f}\x{0928}"
      . "\x{094d}\x{0926}\x{0940}\x{0915}\x{094d}\x{092f}\x{094b}\x{0902}"
      . "\x{0928}\x{0939}\x{0940}\x{0902}\x{092c}\x{094b}\x{0932}\x{0938}"
      . "\x{0915}\x{0924}\x{0947}\x{0939}\x{0948}\x{0902}",
    'i1baa7eci9glrd9b2ae1bj0hfcgg6iyaf8o0a1dig0cd',
    '(G) Japanese (kanji and hiragana):',
    "\x{306a}\x{305c}\x{307f}\x{3093}\x{306a}\x{65e5}\x{672c}\x{8a9e}"
      . "\x{3092}\x{8a71}\x{3057}\x{3066}\x{304f}\x{308c}\x{306a}\x{3044}"
      . "\x{306e}\x{304b}",
    'n8jok5ay5dzabd5bym9f0cm5685rrjetr6pdxa',
    '(H) Korean (Hangul syllables):',
    "\x{c138}\x{acc4}\x{c758}\x{baa8}\x{b4e0}\x{c0ac}\x{b78c}\x{b4e4}"
      . "\x{c774}\x{d55c}\x{ad6d}\x{c5b4}\x{b97c}\x{c774}\x{d574}\x{d55c}"
      . "\x{b2e4}\x{ba74}\x{c5bc}\x{b9c8}\x{b098}\x{c88b}\x{c744}\x{ae4c}",
    '989aomsvi5e83db1d2a355cv1e0vak1dwrv93d5xbh15a0dt30a5jpsd879ccm6fea98c',
    '(I) Russian (Cyrillic):',
    "\x{043f}\x{043e}\x{0447}\x{0435}\x{043c}\x{0443}\x{0436}\x{0435}"
      . "\x{043e}\x{043d}\x{0438}\x{043d}\x{0435}\x{0433}\x{043e}\x{0432}"
      . "\x{043e}\x{0440}\x{044f}\x{0442}\x{043f}\x{043e}\x{0440}\x{0443}"
      . "\x{0441}\x{0441}\x{043a}\x{0438}",
    'b1abfaaepdrnnbgefbadotcwatmq2g4l',
    '(J) Spanish: Porqu<eacute>nopuedensimplementehablarenEspa<ntilde>ol',
    "\x{0050}\x{006f}\x{0072}\x{0071}\x{0075}\x{00e9}\x{006e}\x{006f}"
      . "\x{0070}\x{0075}\x{0065}\x{0064}\x{0065}\x{006e}\x{0073}\x{0069}"
      . "\x{006d}\x{0070}\x{006c}\x{0065}\x{006d}\x{0065}\x{006e}\x{0074}"
      . "\x{0065}\x{0068}\x{0061}\x{0062}\x{006c}\x{0061}\x{0072}\x{0065}"
      . "\x{006e}\x{0045}\x{0073}\x{0070}\x{0061}\x{00f1}\x{006f}\x{006c}",
    'PorqunopuedensimplementehablarenEspaol-fmd56a',
    '(K) Vietnamese: T<adotbelow>isaoh<odotbelow>kh<ocirc>ngth'
      . '<ecirchookabove>ch<ihookabove>n<oacute>iti<ecircacute>ngVi'
      . '<ecircdotbelow>t',
    "\x{0054}\x{1ea1}\x{0069}\x{0073}\x{0061}\x{006f}\x{0068}\x{1ecd}"
      . "\x{006b}\x{0068}\x{00f4}\x{006e}\x{0067}\x{0074}\x{0068}\x{1ec3}"
      . "\x{0063}\x{0068}\x{1ec9}\x{006e}\x{00f3}\x{0069}\x{0074}\x{0069}"
      . "\x{1ebf}\x{006e}\x{0067}\x{0056}\x{0069}\x{1ec7}\x{0074}",
    'TisaohkhngthchnitingVit-kjcr8268qyxafd2f1b9g',
    '(L) 3<nen>B<gumi><kinpachi><sensei>',
    "\x{0033}\x{5e74}\x{0042}\x{7d44}\x{91d1}\x{516b}\x{5148}\x{751f}",
    '3B-ww4c5e180e575a65lsy2b',
    '(M) <amuro><namie>-with-SUPER-MONKEYS',
    "\x{5b89}\x{5ba4}\x{5948}\x{7f8e}\x{6075}\x{002d}\x{0077}\x{0069}"
      . "\x{0074}\x{0068}\x{002d}\x{0053}\x{0055}\x{0050}\x{0045}\x{0052}"
      . "\x{002d}\x{004d}\x{004f}\x{004e}\x{004b}\x{0045}\x{0059}\x{0053}",
    '-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n',
    '(N) Hello-Another-Way-<sorezore><no><basho>',
    "\x{0048}\x{0065}\x{006c}\x{006c}\x{006f}\x{002d}\x{0041}\x{006e}"
      . "\x{006f}\x{0074}\x{0068}\x{0065}\x{0072}\x{002d}\x{0057}\x{0061}"
      . "\x{0079}\x{002d}\x{305d}\x{308c}\x{305e}\x{308c}\x{306e}\x{5834}"
      . "\x{6240}",
    'Hello-Another-Way--fc4qua05auwb3674vfr0b',
    '(O) <hitotsu><yane><no><shita>2',
    "\x{3072}\x{3068}\x{3064}\x{5c4b}\x{6839}\x{306e}\x{4e0b}\x{0032}",
    '2-u9tlzr9756bt3uc0v',
    '(P) Maji<de>Koi<suru>5<byou><mae>',
    "\x{004d}\x{0061}\x{006a}\x{0069}\x{3067}\x{004b}\x{006f}\x{0069}" . "\x{3059}\x{308b}\x{0035}\x{79d2}\x{524d}",
    'MajiKoi5-783gue6qz075azm5e',
    '(Q) <pafii>de<runba>',
    "\x{30d1}\x{30d5}\x{30a3}\x{30fc}\x{0064}\x{0065}\x{30eb}\x{30f3}" . "\x{30d0}",
    'de-jg4avhby1noc0d',
    '(R) <sono><supiido><de>',
    "\x{305d}\x{306e}\x{30b9}\x{30d4}\x{30fc}\x{30c9}\x{3067}",
    'd9juau41awczczp',
    '(S) -> $1.00 <-',
    "\x{002d}\x{003e}\x{0020}\x{0024}\x{0031}\x{002e}\x{0030}\x{0030}" . "\x{0020}\x{003c}\x{002d}",
    '-> $1.00 <--'
  );

  for (my $i = 0; $i < @tests; $i += 3) {
    my ($d, $o, $p) = @tests[$i, $i + 1, $i + 2];
    is punycode_encode($o), $p, "punycode_encode $d";
    is punycode_decode($p), $o, "punycode_decode $d";
  }
};

subtest 'quote' => sub {
  is quote('foo; 23 "bar'),   '"foo; 23 \"bar"',     'right quoted result';
  is quote('"foo; 23 "bar"'), '"\"foo; 23 \"bar\""', 'right quoted result';
};

subtest 'unquote' => sub {
  is unquote('"foo 23 \"bar"'),     'foo 23 "bar',   'right unquoted result';
  is unquote('"\"foo 23 \"bar\""'), '"foo 23 "bar"', 'right unquoted result';
};

subtest 'trim' => sub {
  is trim(' la la  la '),             'la la  la',         'right trimmed result';
  is trim(" \n la la la \n "),        'la la la',          'right trimmed result';
  is trim("\n la\nla la \n"),         "la\nla la",         'right trimmed result';
  is trim(" \nla \n  \t\nla\nla\n "), "la \n  \t\nla\nla", 'right trimmed result';
};

subtest 'md5_bytes' => sub {
  is unpack('H*', md5_bytes(encode 'UTF-8', 'foo bar baz ♥')), 'a740aeb6e066f158cbf19fd92e890d2d',
    'right binary md5 checksum';
};

subtest 'md5_sum' => sub {
  is md5_sum('foo bar baz'), 'ab07acbb1e496801937adfa772424bf7', 'right md5 checksum';
};

subtest 'sha1_bytes' => sub {
  is unpack('H*', sha1_bytes 'foo bar baz'), 'c7567e8b39e2428e38bf9c9226ac68de4c67dc39', 'right binary sha1 checksum';
};

subtest 'sha1_sum' => sub {
  is sha1_sum('foo bar baz'), 'c7567e8b39e2428e38bf9c9226ac68de4c67dc39', 'right sha1 checksum';
};

subtest 'hmac_sha1_sum' => sub {
  is hmac_sha1_sum('Hi there', 'abc1234567890'), '5344f37e1948dd3ffb07243a4d9201a227abd6e1', 'right hmac sha1 checksum';
};

subtest 'sha256_bytes' => sub {
  is unpack('H*', sha256_bytes 'foo bar baz'), 'dbd318c1c462aee872f41109a4dfd3048871a03dedd0fe0e757ced57dad6f2d7',
    'right binary sha-256 checksum';
};

subtest 'sha256_sum' => sub {
  is sha256_sum('foo bar baz'), 'dbd318c1c462aee872f41109a4dfd3048871a03dedd0fe0e757ced57dad6f2d7',
    'right sha-256 checksum';
};

subtest 'hmac_sha256_sum' => sub {
  is hmac_sha256_sum('Hi there', 'abc256234567890'), 'e6cca557cc5c4843bbd370cffd36ae3df33609da1b5b4743aa0a1acd3168f655',
    'right hmac sha-256 checksum';
};

subtest 'secure_compare' => sub {
  ok secure_compare('hello',  'hello'), 'values are equal';
  ok !secure_compare('hell',  'hello'), 'values are not equal';
  ok !secure_compare('hallo', 'hello'), 'values are not equal';
  ok secure_compare('0',      '0'),     'values are equal';
  ok secure_compare('1',      '1'),     'values are equal';
  ok !secure_compare('1',     '0'),     'values are not equal';
  ok !secure_compare('0',     '1'),     'values are not equal';
  ok secure_compare('00',     '00'),    'values are equal';
  ok secure_compare('11',     '11'),    'values are equal';
  ok !secure_compare('11',    '00'),    'values are not equal';
  ok !secure_compare('00',    '11'),    'values are not equal';
  ok secure_compare('♥',      '♥'),     'values are equal';
  ok secure_compare('0♥',     '0♥'),    'values are equal';
  ok secure_compare('♥1',     '♥1'),    'values are equal';
  ok !secure_compare('♥',     '♥0'),    'values are not equal';
  ok !secure_compare('0♥',    '♥'),     'values are not equal';
  ok !secure_compare('0♥1',   '1♥0'),   'values are not equal';
  ok !secure_compare('',      '♥'),     'values are not equal';
  ok !secure_compare('♥',     ''),      'values are not equal';
};

subtest 'xor_encode' => sub {
  is xor_encode('hello',                'foo'), "\x0e\x0a\x03\x0a\x00",                               'right result';
  is xor_encode("\x0e\x0a\x03\x0a\x00", 'foo'), 'hello',                                              'right result';
  is xor_encode('hello world',          'x'),   "\x10\x1d\x14\x14\x17\x58\x0f\x17\x0a\x14\x1c",       'right result';
  is xor_encode("\x10\x1d\x14\x14\x17\x58\x0f\x17\x0a\x14\x1c", 'x'),         'hello world',          'right result';
  is xor_encode('hello',                                        '123456789'), "\x59\x57\x5f\x58\x5a", 'right result';
  is xor_encode("\x59\x57\x5f\x58\x5a",                         '123456789'), 'hello',                'right result';
};

subtest 'steady_time' => sub {
  like steady_time, qr/^[\d.]+$/, 'high resolution time';
};

subtest 'monkey_patch' => sub {
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
};

subtest 'monkey_patch (with name)' => sub {
  is subname(MojoMonkeyTest->can('foo')), 'MojoMonkeyTest::foo', 'right name';
  is subname(MojoMonkeyTest->can('bar')), 'MojoMonkeyTest::bar', 'right name';
};

subtest 'network_contains' => sub {
  ok !network_contains('10.0.0.0/8',     ''),            'empty address';
  ok !network_contains('',               '10.10.10.10'), 'empty network';
  ok !network_contains('foo',            '10.10.10.10'), 'invalid v4 network';
  ok !network_contains('10.10.10.10',    'foo'),         'invalid v4 address';
  ok !network_contains('foo:',           '::'),          'invalid v6 network';
  ok !network_contains('::',             'foo:'),        'invalid v6 address';
  ok !network_contains('::/96',          '192.168.0.1'), 'v6 network, v4 address';
  ok !network_contains('10.10.10.10/32', '::'),          'v4 network, v6 address';

  ok network_contains('192.168.0.1/33', '192.168.0.1'), 'oversize v4 mask';
  ok network_contains('::/130',         '::'),          'oversize v6 mask';

  ok network_contains('0.0.0.0/0',          '0.0.0.0'),         'v4 network contains addresss';
  ok network_contains('0.0.0.0/0',          '255.255.255.255'), 'v4 network contains addresss';
  ok network_contains('192.168.0.0/24',     '192.168.0.1'),     'v4 network contains addresss';
  ok network_contains('10.10.10.8/30',      '10.10.10.11'),     'v4 network contains addresss';
  ok network_contains('10.10.10.8/30',      '10.10.10.8'),      'v4 network contains addresss';
  ok network_contains('10.10.10.8/31',      '10.10.10.9'),      'v4 network contains addresss';
  ok network_contains('10.0.0.0/8',         '10.255.255.255'),  'v4 network contains addresss';
  ok network_contains('255.255.255.255/32', '255.255.255.255'), 'v4 network contains addresss';
  ok network_contains('10.10.10.8/29',      '10.10.10.10'),     'v4 network contains addresss';
  ok network_contains('127.0.0.1',          '127.0.0.1'),       'v4 network contains addresss';

  ok !network_contains('0.0.0.0/32',     '0.0.0.1'),        'v4 network does not contain address';
  ok !network_contains('192.168.1.0/24', '192.168.0.1'),    'v4 network does not contain address';
  ok !network_contains('10.10.0.8/29',   '10.10.10.8'),     'v4 network does not contain address';
  ok !network_contains('10.10.10.8/29',  '10.10.10.7'),     'v4 network does not contain address';
  ok !network_contains('10.10.10.8/29',  '10.10.10.16'),    'v4 network does not contain address';
  ok !network_contains('10.0.0.0/9',     '10.255.255.255'), 'v4 network does not contain address';
  ok !network_contains('10.10.10.8/29',  '10.10.10.19'),    'v4 network does not contain address';
  ok !network_contains('127.0.0.1',      '127.0.0.2'),      'v4 network does not contain address';
  ok !network_contains('10.0.0.1/8',     '10.0.0.2'),       'v4 network does not contain address';

  ok network_contains('::/128',             '::'),                                      'v6 network contains addresss';
  ok network_contains('::/0',               '::'),                                      'v6 network contains addresss';
  ok network_contains('::1',                '::1'),                                     'v6 network contains addresss';
  ok network_contains('::/0',               'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff'), 'v6 network contains addresss';
  ok network_contains('1:2:3:4:5:6:0::/96', '1:2:3:4:5:6:8000:8'),                      'v6 network contains addresss';
  ok network_contains('1:2:3:4:5:6:8000::/112',       '1:2:3:4:5:6:8000:F1'),           'v6 network contains addresss';
  ok network_contains('1:2:3:4:5:6:8000:20/123',      '1:2:3:4:5:6:8000:3F'),           'v6 network contains addresss';
  ok network_contains('ff:ff:ff:ff:ff:ff:8000::/127', 'ff:ff:ff:ff:ff:ff:8000:0'),      'v6 network contains addresss';
  ok network_contains('ff:ff:ff:ff:ff:ff:8000::/127', 'ff:ff:ff:ff:ff:ff:8000:1'),      'v6 network contains addresss';
  ok network_contains('::1',                          '::1'),                           'v6 network contains addresss';
  ok network_contains('::1/128',                      '::1'),                           'v6 network contains addresss';
  ok network_contains('a0:a0:a0:a0::/64',             'a0:a0:a0:a0:1::1'),              'v6 network contains addresss';
  ok network_contains('a0::/16',                      'a0:b0:a0:a0:1::1'),              'v6 network contains addresss';
  ok network_contains('a000::/8',                     'a0ff:dd0:1234:a0:1::1'),         'v6 network contains addresss';
  ok network_contains('::ffff:0:0/96',                '::ffff:10.10.10.10'),            'v6 network contains addresss';
  ok network_contains('::ffff:127.0.0.0/120',         '::ffff:127.0.0.255'),            'v6 network contains addresss';
  ok network_contains('::ffff:10.10.10.8/127',        '::ffff:10.10.10.9'),             'v6 network contains addresss';

  ok !network_contains('::1/0', '::'),                                         'v6 network does not contain address';
  ok !network_contains('::1',   '::2'),                                        'v6 network does not contain address';
  ok !network_contains('1::/0', 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff'),    'v6 network does not contain address';
  ok !network_contains('1:2:3:4:5:6:0::/96',           '1:2:3:4:5:7:8000:8'),  'v6 network does not contain address';
  ok !network_contains('1:2:3:4:5:6:8000::/112',       '1:2:3:4:5:6:8001:F1'), 'v6 network does not contain address';
  ok !network_contains('1:2:3:4:5:6:8000:20/123',      '1:2:3:4:5:6:8000:40'), 'v6 network does not contain address';
  ok !network_contains('ff:ff:ff:ff:ff:ff:8000::/127', 'ff:ff:ff:ff:ff:ff:8000:4'),
    'v6 network does not contain address';
  ok !network_contains('ff:ff:ff:ff:ff:ff:8000::/127', 'ff:ff:ff:ff:ff:ff:7FFF:0'),
    'v6 network does not contain address';
  ok !network_contains('::1',                   '1::1'),                  'v6 network does not contain address';
  ok !network_contains('::1/128',               '::11'),                  'v6 network does not contain address';
  ok !network_contains('a0:a0:a0:a0::/64',      'a0:a0:a0:a1:1::1'),      'v6 network does not contain address';
  ok !network_contains('a0::/16',               'a1:b0:a0:a0:1::1'),      'v6 network does not contain address';
  ok !network_contains('a000::/8',              'b0ff:dd0:1234:a0:1::1'), 'v6 network does not contain address';
  ok !network_contains('::ffff:0:0/96',         '::fffe:0a0a:0a0a'),      'v6 network does not contain address';
  ok !network_contains('::ffff:127.0.0.0/120',  '::ffff:127.0.1.255'),    'v6 network does not contain address';
  ok !network_contains('::ffff:10.10.10.8/127', '::ffff:10.10.10.12'),    'v6 network does not contain address';
};

subtest 'tablify' => sub {
  is tablify([["f\r\no o\r\n", 'bar']]), "fo o  bar\n",      'right result';
  is tablify([["  foo", '  b a r']]),    "  foo    b a r\n", 'right result';
  is tablify([['foo']]),                 "foo\n",            'right result';
  is tablify([['foo', 'yada'], ['yada', 'yada']]), "foo   yada\nyada  yada\n", 'right result';
  is tablify([[undef, 'yada'], ['yada', undef]]),  "      yada\nyada  \n",     'right result';
  is tablify([['foo', 'bar', 'baz'], ['yada', 'yada', 'yada']]), "foo   bar   baz\nyada  yada  yada\n", 'right result';
  is tablify([['a', '', 0],          [0, '', 'b']]),             "a    0\n0    b\n",                    'right result';
  is tablify([[1, 2], [3]]), "1  2\n3\n", 'right result';
  is tablify([[1], [2, 3]]), "1\n2  3\n", 'right result';
  is tablify([[1], [], [2, 3]]), "1\n\n2  3\n", 'right result';
};

subtest 'deprecated' => sub {
  my ($warn, $die) = @_;
  local $SIG{__WARN__} = sub { $warn = shift };
  local $SIG{__DIE__}  = sub { $die  = shift };
  is Mojo::DeprecationTest::foo(), 'bar', 'right result';
  like $warn, qr/foo is DEPRECATED at .*util\.t line \d+/, 'right warning';
  ok !$die, 'no exception';
  ($warn, $die) = ();
  local $ENV{MOJO_FATAL_DEPRECATIONS} = 1;
  ok !eval { Mojo::DeprecationTest::foo() }, 'no result';
  ok !$warn,                                 'no warning';
  like $die, qr/foo is DEPRECATED at .*util\.t line \d+/, 'right exception';
};

subtest 'dumper' => sub {
  is dumper([1, 2]), "[\n  1,\n  2\n]\n", 'right result';
};

subtest 'term_escape' => sub {
  is term_escape("Accept: */*\x0d\x0a"),          "Accept: */*\\x0d\x0a",         'right result';
  is term_escape("\t\b\r\n\f"),                   "\\x09\\x08\\x0d\n\\x0c",       'right result';
  is term_escape("\x00\x09\x0b\x1f\x7f\x80\x9f"), '\x00\x09\x0b\x1f\x7f\x80\x9f', 'right result';
};

subtest 'slugify' => sub {
  is slugify('a & b'),     'a-b',     'right result';
  is slugify('a &amp; b'), 'a-amp-b', 'right result';
  is slugify(123),         '123',     'right result';
  is slugify(' Jack & Jill like numbers 1,2,3 and 4 and silly characters ?%.$!/'),
    'jack-jill-like-numbers-123-and-4-and-silly-characters', 'right result';
  is slugify("Un \x{e9}l\x{e9}phant \x{e0} l'or\x{e9}e du bois"), 'un-elephant-a-loree-du-bois', 'right result';
  is slugify("Un \x{e9}l\x{e9}phant \x{e0} l'or\x{e9}e du bois", 1), "un-\x{e9}l\x{e9}phant-\x{e0}-lor\x{e9}e-du-bois",
    'right result';
  is slugify('Hello, World!'),     'hello-world', 'right result';
  is slugify('spam & eggs'),       'spam-eggs',   'right result';
  is slugify('spam & ıçüş', 1),    'spam-ıçüş',   'right result';
  is slugify('foo ıç bar', 1),     'foo-ıç-bar',  'right result';
  is slugify('    foo ıç bar', 1), 'foo-ıç-bar',  'right result';
  is slugify('你好', 1),             '你好',          'right result';
};

subtest 'gzip/gunzip' => sub {
  my $uncompressed = 'a' x 1000;
  my $compressed   = gzip $uncompressed;
  isnt $compressed, $uncompressed, 'string changed';
  ok length $compressed < length $uncompressed, 'string is shorter';
  my $result = gunzip $compressed;
  is $result, $uncompressed, 'same string';
};

subtest 'scope_guard' => sub {
  my $test = 'a';
  {
    my $guard = scope_guard sub { $test .= 'c' };
    $test .= 'b';
  }
  $test .= 'd';
  is $test, 'abcd', 'right order';
};

subtest 'humanize_bytes' => sub {
  is humanize_bytes(0),                         '0B',      'zero Bytes';
  is humanize_bytes(1),                         '1B',      'one Byte';
  is humanize_bytes(-1023),                     '-1023B',  'negative Bytes';
  is humanize_bytes(1024),                      '1KiB',    'one KiB';
  is humanize_bytes(1025),                      '1KiB',    'one KiB';
  is humanize_bytes(1024 * 1024),               '1MiB',    'one MiB';
  is humanize_bytes(1024 * 1024 * 1024),        '1GiB',    'one GiB';
  is humanize_bytes(1024 * 1024 * 1024 * 1024), '1TiB',    'one TiB';
  is humanize_bytes(3000),                      '2.9KiB',  'almost 3KiB';
  is humanize_bytes(-3000),                     '-2.9KiB', 'almost -3KiB';
  is humanize_bytes(13443399680),               '13GiB',   'two digits GiB';
  is humanize_bytes(8007188480),                '7.5GiB',  'smaller GiB';
  is humanize_bytes(-8007188480),               '-7.5GiB', 'negative smaller GiB';
  is humanize_bytes(-1099511627776),            '-1TiB',   'negative smaller TiB';
  is humanize_bytes(717946880),                 '685MiB',  'large MiB';
  is humanize_bytes(-717946880),                '-685MiB', 'large negative MiB';
  is humanize_bytes(245760),                    '240KiB',  'less than a MiB';
};

subtest 'Hide DATA usage from error messages' => sub {
  eval { die 'whatever' };
  unlike $@, qr/DATA/, 'DATA has been hidden';
};

done_testing();
