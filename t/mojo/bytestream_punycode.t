#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Mojo::ByteStream 'b';

binmode Test::More->builder->$_, ":utf8"
  for qw(output failure_output todo_output);

# RFC 3492 samples

my @samples = (
    [   '(A) Arabic (Egyptian):',
        "\x{0644}\x{064A}\x{0647}\x{0645}\x{0627}\x{0628}\x{062A}"
          . "\x{0643}\x{0644}\x{0645}\x{0648}\x{0634}\x{0639}\x{0631}"
          . "\x{0628}\x{064A}\x{061F}",
        'egbpdaj6bu4bxfgehfvwxn',
    ],
    [   '(B) Chinese (simplified):',
        "\x{4ED6}\x{4EEC}\x{4E3A}\x{4EC0}\x{4E48}\x{4E0D}\x{8BF4}"
          . "\x{4E2D}\x{6587}",
        'ihqwcrb4cv8a8dqg056pqjye',
    ],
    [   '(C) Chinese (traditional):',
        "\x{4ED6}\x{5011}\x{7232}\x{4EC0}\x{9EBD}\x{4E0D}\x{8AAA}"
          . "\x{4E2D}\x{6587}",
        'ihqwctvzc91f659drss3x8bo0yb',
    ],
    [   '(D) Czech: Pro<ccaron>prost<ecaron>nemluv<iacute><ccaron>esky',
        "\x{0050}\x{0072}\x{006F}\x{010D}\x{0070}\x{0072}\x{006F}"
          . "\x{0073}\x{0074}\x{011B}\x{006E}\x{0065}\x{006D}\x{006C}"
          . "\x{0075}\x{0076}\x{00ED}\x{010D}\x{0065}\x{0073}\x{006B}"
          . "\x{0079}",
        'Proprostnemluvesky-uyb24dma41a',
    ],
    [   '(E) Hebrew:',
        "\x{05DC}\x{05DE}\x{05D4}\x{05D4}\x{05DD}\x{05E4}\x{05E9}"
          . "\x{05D5}\x{05D8}\x{05DC}\x{05D0}\x{05DE}\x{05D3}\x{05D1}"
          . "\x{05E8}\x{05D9}\x{05DD}\x{05E2}\x{05D1}\x{05E8}\x{05D9}"
          . "\x{05EA}",
        '4dbcagdahymbxekheh6e0a7fei0b',
    ],
    [   '(F) Hindi (Devanagari):',
        "\x{092F}\x{0939}\x{0932}\x{094B}\x{0917}\x{0939}\x{093F}"
          . "\x{0928}\x{094D}\x{0926}\x{0940}\x{0915}\x{094D}\x{092F}"
          . "\x{094B}\x{0902}\x{0928}\x{0939}\x{0940}\x{0902}\x{092C}"
          . "\x{094B}\x{0932}\x{0938}\x{0915}\x{0924}\x{0947}\x{0939}"
          . "\x{0948}\x{0902}",
        'i1baa7eci9glrd9b2ae1bj0hfcgg6iyaf8o0a1dig0cd',
    ],
    [   '(G) Japanese (kanji and hiragana):',
        "\x{306A}\x{305C}\x{307F}\x{3093}\x{306A}\x{65E5}\x{672C}"
          . "\x{8A9E}\x{3092}\x{8A71}\x{3057}\x{3066}\x{304F}\x{308C}"
          . "\x{306A}\x{3044}\x{306E}\x{304B}",
        'n8jok5ay5dzabd5bym9f0cm5685rrjetr6pdxa',
    ],
    [   '(H) Korean (Hangul syllables):',
        "\x{C138}\x{ACC4}\x{C758}\x{BAA8}\x{B4E0}\x{C0AC}\x{B78C}"
          . "\x{B4E4}\x{C774}\x{D55C}\x{AD6D}\x{C5B4}\x{B97C}\x{C774}"
          . "\x{D574}\x{D55C}\x{B2E4}\x{BA74}\x{C5BC}\x{B9C8}\x{B098}"
          . "\x{C88B}\x{C744}\x{AE4C}",
        '989aomsvi5e83db1d2a355cv1e0vak1dwrv93d5xbh15a0dt30a5jpsd879ccm6fea98c',
    ],
    [   '(I) Russian (Cyrillic):',
        "\x{043F}\x{043E}\x{0447}\x{0435}\x{043C}\x{0443}\x{0436}"
          . "\x{0435}\x{043E}\x{043D}\x{0438}\x{043D}\x{0435}\x{0433}"
          . "\x{043E}\x{0432}\x{043E}\x{0440}\x{044F}\x{0442}\x{043F}"
          . "\x{043E}\x{0440}\x{0443}\x{0441}\x{0441}\x{043A}\x{0438}",
        'b1abfaaepdrnnbgefbadotcwatmq2g4l',
    ],
    [   '(J) Spanish: Porqu<eacute>nopuedensimplementehablarenEspa<ntilde>ol',
        "\x{0050}\x{006F}\x{0072}\x{0071}\x{0075}\x{00E9}\x{006E}"
          . "\x{006F}\x{0070}\x{0075}\x{0065}\x{0064}\x{0065}\x{006E}"
          . "\x{0073}\x{0069}\x{006D}\x{0070}\x{006C}\x{0065}\x{006D}"
          . "\x{0065}\x{006E}\x{0074}\x{0065}\x{0068}\x{0061}\x{0062}"
          . "\x{006C}\x{0061}\x{0072}\x{0065}\x{006E}\x{0045}\x{0073}"
          . "\x{0070}\x{0061}\x{00F1}\x{006F}\x{006C}",
        'PorqunopuedensimplementehablarenEspaol-fmd56a',
    ],
    [   '(K) Vietnamese: T<adotbelow>isaoh<odotbelow>kh<ocirc>ngth'
          . '<ecirchookabove>ch<ihookabove>n<oacute>iti<ecircacute>ngVi'
          . '<ecircdotbelow>t',
        "\x{0054}\x{1EA1}\x{0069}\x{0073}\x{0061}\x{006F}\x{0068}"
          . "\x{1ECD}\x{006B}\x{0068}\x{00F4}\x{006E}\x{0067}\x{0074}"
          . "\x{0068}\x{1EC3}\x{0063}\x{0068}\x{1EC9}\x{006E}\x{00F3}"
          . "\x{0069}\x{0074}\x{0069}\x{1EBF}\x{006E}\x{0067}\x{0056}"
          . "\x{0069}\x{1EC7}\x{0074}",
        'TisaohkhngthchnitingVit-kjcr8268qyxafd2f1b9g',
    ],
    [   '(L) 3<nen>B<gumi><kinpachi><sensei>',
        "\x{0033}\x{5E74}\x{0042}\x{7D44}\x{91D1}\x{516B}\x{5148}"
          . "\x{751F}",
        '3B-ww4c5e180e575a65lsy2b',
    ],
    [   '(M) <amuro><namie>-with-SUPER-MONKEYS',
        "\x{5B89}\x{5BA4}\x{5948}\x{7F8E}\x{6075}\x{002D}\x{0077}"
          . "\x{0069}\x{0074}\x{0068}\x{002D}\x{0053}\x{0055}\x{0050}"
          . "\x{0045}\x{0052}\x{002D}\x{004D}\x{004F}\x{004E}\x{004B}"
          . "\x{0045}\x{0059}\x{0053}",
        '-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n',
    ],
    [   '(N) Hello-Another-Way-<sorezore><no><basho>',
        "\x{0048}\x{0065}\x{006C}\x{006C}\x{006F}\x{002D}\x{0041}"
          . "\x{006E}\x{006F}\x{0074}\x{0068}\x{0065}\x{0072}\x{002D}"
          . "\x{0057}\x{0061}\x{0079}\x{002D}\x{305D}\x{308C}\x{305E}"
          . "\x{308C}\x{306E}\x{5834}\x{6240}",
        'Hello-Another-Way--fc4qua05auwb3674vfr0b',
    ],
    [   '(O) <hitotsu><yane><no><shita>2',
        "\x{3072}\x{3068}\x{3064}\x{5C4B}\x{6839}\x{306E}\x{4E0B}"
          . "\x{0032}",
        '2-u9tlzr9756bt3uc0v',
    ],
    [   '(P) Maji<de>Koi<suru>5<byou><mae>',
        "\x{004D}\x{0061}\x{006A}\x{0069}\x{3067}\x{004B}\x{006F}"
          . "\x{0069}\x{3059}\x{308B}\x{0035}\x{79D2}\x{524D}",
        'MajiKoi5-783gue6qz075azm5e',
    ],
    [   '(Q) <pafii>de<runba>',
        "\x{30D1}\x{30D5}\x{30A3}\x{30FC}\x{0064}\x{0065}\x{30EB}"
          . "\x{30F3}\x{30D0}",
        'de-jg4avhby1noc0d',
    ],
    [   '(R) <sono><supiido><de>',
        "\x{305D}\x{306E}\x{30B9}\x{30D4}\x{30FC}\x{30C9}\x{3067}",
        'd9juau41awczczp',
    ],
    [   '(S) -> $1.00 <-',
        "\x{002D}\x{003E}\x{0020}\x{0024}\x{0031}\x{002E}\x{0030}"
          . "\x{0030}\x{0020}\x{003C}\x{002D}",
        '-> $1.00 <--',
    ],
);

plan tests => @samples * 2;

for my $sample (@samples) {
    my ($desc, $orig, $puny) = @$sample;
    is b($orig)->punycode_encode->to_string, $puny, "encode: $desc";
    is b($puny)->punycode_decode->to_string, $orig, "decode: $desc";
}
