package Mojo::Util;
use Mojo::Base 'Exporter';

# These are core modules since 5.8, no need for pure-Perl implementations
# (even though they would be simple)
require Digest::MD5;
require Encode;
require MIME::Base64;
require MIME::QuotedPrint;

# Core module since Perl 5.9.3
use constant SHA1 => eval 'use Digest::SHA (); 1';

# Punycode bootstring parameters
use constant {
  PUNYCODE_BASE         => 36,
  PUNYCODE_TMIN         => 1,
  PUNYCODE_TMAX         => 26,
  PUNYCODE_SKEW         => 38,
  PUNYCODE_DAMP         => 700,
  PUNYCODE_INITIAL_BIAS => 72,
  PUNYCODE_INITIAL_N    => 128
};

# Punycode delimiter
my $DELIMITER = chr 0x2D;

# HTML5 entities for html_unescape (without "apos")
my %ENTITIES = (
  Aacute   => 193,
  aacute   => 225,
  Acirc    => 194,
  acirc    => 226,
  acute    => 180,
  AElig    => 198,
  aelig    => 230,
  Agrave   => 192,
  agrave   => 224,
  alefsym  => 8501,
  Alpha    => 913,
  alpha    => 945,
  amp      => 38,
  and      => 8743,
  ang      => 8736,
  '#39'    => 39,
  Aring    => 197,
  aring    => 229,
  asymp    => 8776,
  Atilde   => 195,
  atilde   => 227,
  Auml     => 196,
  auml     => 228,
  bdquo    => 8222,
  Beta     => 914,
  beta     => 946,
  brvbar   => 166,
  bull     => 8226,
  cap      => 8745,
  Ccedil   => 199,
  ccedil   => 231,
  cedil    => 184,
  cent     => 162,
  Chi      => 935,
  chi      => 967,
  circ     => 710,
  clubs    => 9827,
  cong     => 8773,
  copy     => 169,
  crarr    => 8629,
  cup      => 8746,
  curren   => 164,
  Dagger   => 8225,
  dagger   => 8224,
  dArr     => 8659,
  darr     => 8595,
  deg      => 176,
  Delta    => 916,
  delta    => 948,
  diams    => 9830,
  divide   => 247,
  Eacute   => 201,
  eacute   => 233,
  Ecirc    => 202,
  ecirc    => 234,
  Egrave   => 200,
  egrave   => 232,
  empty    => 8709,
  emsp     => 8195,
  ensp     => 8194,
  Epsilon  => 917,
  epsilon  => 949,
  equiv    => 8801,
  Eta      => 919,
  eta      => 951,
  ETH      => 208,
  eth      => 240,
  Euml     => 203,
  euml     => 235,
  euro     => 8364,
  exist    => 8707,
  fnof     => 402,
  forall   => 8704,
  frac12   => 189,
  frac14   => 188,
  frac34   => 190,
  frasl    => 8260,
  Gamma    => 915,
  gamma    => 947,
  ge       => 8805,
  gt       => 62,
  hArr     => 8660,
  harr     => 8596,
  hearts   => 9829,
  hellip   => 8230,
  Iacute   => 205,
  iacute   => 237,
  Icirc    => 206,
  icirc    => 238,
  iexcl    => 161,
  Igrave   => 204,
  igrave   => 236,
  image    => 8465,
  infin    => 8734,
  int      => 8747,
  Iota     => 921,
  iota     => 953,
  iquest   => 191,
  isin     => 8712,
  Iuml     => 207,
  iuml     => 239,
  Kappa    => 922,
  kappa    => 954,
  Lambda   => 923,
  lambda   => 955,
  lang     => 9001,
  laquo    => 171,
  lArr     => 8656,
  larr     => 8592,
  lceil    => 8968,
  ldquo    => 8220,
  le       => 8804,
  lfloor   => 8970,
  lowast   => 8727,
  loz      => 9674,
  lrm      => 8206,
  lsaquo   => 8249,
  lsquo    => 8216,
  lt       => 60,
  macr     => 175,
  mdash    => 8212,
  micro    => 181,
  middot   => 183,
  minus    => 8722,
  Mu       => 924,
  mu       => 956,
  nabla    => 8711,
  nbsp     => 160,
  ndash    => 8211,
  ne       => 8800,
  ni       => 8715,
  not      => 172,
  notin    => 8713,
  nsub     => 8836,
  Ntilde   => 209,
  ntilde   => 241,
  Nu       => 925,
  nu       => 957,
  Oacute   => 211,
  oacute   => 243,
  Ocirc    => 212,
  ocirc    => 244,
  OElig    => 338,
  oelig    => 339,
  Ograve   => 210,
  ograve   => 242,
  oline    => 8254,
  Omega    => 937,
  omega    => 969,
  Omicron  => 927,
  omicron  => 959,
  oplus    => 8853,
  or       => 8744,
  ordf     => 170,
  ordm     => 186,
  Oslash   => 216,
  oslash   => 248,
  Otilde   => 213,
  otilde   => 245,
  otimes   => 8855,
  Ouml     => 214,
  ouml     => 246,
  para     => 182,
  part     => 8706,
  permil   => 8240,
  perp     => 8869,
  Phi      => 934,
  phi      => 966,
  Pi       => 928,
  pi       => 960,
  piv      => 982,
  plusmn   => 177,
  pound    => 163,
  Prime    => 8243,
  prime    => 8242,
  prod     => 8719,
  prop     => 8733,
  Psi      => 936,
  psi      => 968,
  quot     => 34,
  radic    => 8730,
  rang     => 9002,
  raquo    => 187,
  rArr     => 8658,
  rarr     => 8594,
  rceil    => 8969,
  rdquo    => 8221,
  real     => 8476,
  reg      => 174,
  rfloor   => 8971,
  Rho      => 929,
  rho      => 961,
  rlm      => 8207,
  rsaquo   => 8250,
  rsquo    => 8217,
  sbquo    => 8218,
  Scaron   => 352,
  scaron   => 353,
  sdot     => 8901,
  sect     => 167,
  shy      => 173,
  Sigma    => 931,
  sigma    => 963,
  sigmaf   => 962,
  sim      => 8764,
  spades   => 9824,
  sub      => 8834,
  sube     => 8838,
  sum      => 8721,
  sup      => 8835,
  sup1     => 185,
  sup2     => 178,
  sup3     => 179,
  supe     => 8839,
  szlig    => 223,
  Tau      => 932,
  tau      => 964,
  there4   => 8756,
  Theta    => 920,
  theta    => 952,
  thetasym => 977,
  thinsp   => 8201,
  THORN    => 222,
  thorn    => 254,
  tilde    => 732,
  times    => 215,
  trade    => 8482,
  Uacute   => 218,
  uacute   => 250,
  uArr     => 8657,
  uarr     => 8593,
  Ucirc    => 219,
  ucirc    => 251,
  Ugrave   => 217,
  ugrave   => 249,
  uml      => 168,
  upsih    => 978,
  Upsilon  => 933,
  upsilon  => 965,
  Uuml     => 220,
  uuml     => 252,
  weierp   => 8472,
  Xi       => 926,
  xi       => 958,
  Yacute   => 221,
  yacute   => 253,
  yen      => 165,
  Yuml     => 376,
  yuml     => 255,
  Zeta     => 918,
  zeta     => 950,
  zwj      => 8205,
  zwnj     => 8204
);

# Reverse entities for html_escape
my %REVERSE_ENTITIES = reverse %ENTITIES;

# "apos"
$ENTITIES{apos} = 39;

# Encode cache
my %ENCODE;

# "Bart, stop pestering Satan!"
our @EXPORT_OK = qw/b64_decode b64_encode camelize decamelize decode encode/;
push @EXPORT_OK, qw/get_line hmac_md5_sum hmac_sha1_sum html_escape/;
push @EXPORT_OK, qw/html_unescape md5_bytes md5_sum punycode_decode/;
push @EXPORT_OK, qw/punycode_encode qp_decode qp_encode quote/;
push @EXPORT_OK, qw/secure_compare sha1_bytes sha1_sum trim unquote/;
push @EXPORT_OK, qw/url_escape url_unescape xml_escape/;

sub b64_decode { $_[0] = MIME::Base64::decode_base64($_[0]) }

sub b64_encode { $_[0] = MIME::Base64::encode_base64($_[0], $_[1]) }

sub camelize {
  return if $_[0] =~ /^[A-Z]/;

  # Module parts
  my @parts;
  for my $part (split /-/, $_[0]) {
    next unless $part;

    # Camel case words
    my @words = split /_/, $part;
    @words = map { ucfirst lc } @words;
    push @parts, join '', @words;
  }
  $_[0] = join '::', @parts;
}

sub decamelize {
  return if $_[0] !~ /^[A-Z]/;

  # Module parts
  my @parts;
  for my $part (split /\:\:/, $_[0]) {

    # Camel case words
    my @words;
    push @words, $1 while ($part =~ s/([A-Z]{1}[^A-Z]*)//);
    @words = map {lc} @words;
    push @parts, join '_', @words;
  }
  $_[0] = join '-', @parts;
}

sub decode {

  # Try decoding
  eval {

    # UTF-8
    if ($_[0] eq 'UTF-8') { die unless utf8::decode $_[1] }

    # Everything else
    else {
      $_[1] =
        ($ENCODE{$_[0]} ||= Encode::find_encoding($_[0]))->decode($_[1], 1);
    }
  };

  # Failed
  $_[1] = undef if $@;
}

sub encode {

  # UTF-8
  if ($_[0] eq 'UTF-8') { utf8::encode $_[1] }

  # Everything else
  else {
    $_[1] = ($ENCODE{$_[0]} ||= Encode::find_encoding($_[0]))->encode($_[1]);
  }
}

sub get_line {

  # Locate line ending
  return if (my $pos = index $_[0], "\x0a") == -1;

  # Extract line and ending
  my $line = substr $_[0], 0, $pos + 1, '';
  $line =~ s/\x0d?\x0a$//;

  return $line;
}

sub hmac_md5_sum { _hmac(\&_md5, @_) }

sub hmac_sha1_sum { _hmac(\&_sha1, @_) }

sub html_escape {
  my $escaped = '';
  for (1 .. length $_[0]) {

    # Escape entities
    my $char = substr $_[0], 0, 1, '';
    my $num = unpack 'U', $char;
    my $named = $REVERSE_ENTITIES{$num};
    $char = "&$named;" if $named;
    $escaped .= $char;
  }
  $_[0] = $escaped;
}

# "Daddy, I'm scared. Too scared to even wet my pants.
#  Just relax and it'll come, son."
sub html_unescape {
  $_[0] =~ s/
    &
    (?:
      \#
      (
        (?:
          \d{1,7}             # Number
          |
          x[0-9A-Fa-f]{1,6}   # Hex
        )
      )
      |
      ([A-Za-z]{1,8})         # Name
    )
    ;
  /_unescape($1, $2)/gex;
}

sub md5_bytes { _md5(@_) }

sub md5_sum { Digest::MD5::md5_hex(@_) }

sub punycode_decode {
  use integer;

  # Defaults
  my $n    = PUNYCODE_INITIAL_N;
  my $i    = 0;
  my $bias = PUNYCODE_INITIAL_BIAS;
  my @output;

  # Delimiter
  if ($_[0] =~ s/(.*)$DELIMITER//os) { push @output, split //, $1 }

  # Decode (direct translation of RFC 3492)
  while (length $_[0]) {
    my $oldi = $i;
    my $w    = 1;

    # Base to infinity in steps of base
    for (my $k = PUNYCODE_BASE; 1; $k += PUNYCODE_BASE) {

      # Digit
      my $digit = ord substr $_[0], 0, 1, '';
      $digit = $digit < 0x40 ? $digit + (26 - 0x30) : ($digit & 0x1f) - 1;
      $i += $digit * $w;
      my $t = $k - $bias;
      $t =
          $t < PUNYCODE_TMIN ? PUNYCODE_TMIN
        : $t > PUNYCODE_TMAX ? PUNYCODE_TMAX
        :                      $t;
      last if $digit < $t;

      $w *= (PUNYCODE_BASE - $t);
    }

    # Bias
    $bias = _adapt($i - $oldi, @output + 1, $oldi == 0);
    $n += $i / (@output + 1);
    $i = $i % (@output + 1);

    # Insert
    splice @output, $i, 0, chr($n);
    $i++;
  }

  $_[0] = join '', @output;
}

sub punycode_encode {
  use integer;

  # Defaults
  my $output = $_[0];
  my $len    = length $_[0];

  # Remove non basic characters
  $output =~ s/[^\x00-\x7f]+//ogs;

  # Non basic characters in input
  my $h = my $b = length $output;
  $output .= $DELIMITER if $b > 0;

  # Split input
  my @input = map ord, split //, $_[0];
  my @chars = sort grep { $_ >= PUNYCODE_INITIAL_N } @input;

  # Defaults
  my $n     = PUNYCODE_INITIAL_N;
  my $delta = 0;
  my $bias  = PUNYCODE_INITIAL_BIAS;

  # Encode (direct translation of RFC 3492)
  for my $m (@chars) {

    # Basic character
    next if $m < $n;

    # Delta
    $delta += ($m - $n) * ($h + 1);

    # Walk all code points in order
    $n = $m;
    for (my $i = 0; $i < $len; $i++) {
      my $c = $input[$i];

      # Basic character
      $delta++ if $c < $n;

      # Non basic character
      if ($c == $n) {
        my $q = $delta;

        # Base to infinity in steps of base
        for (my $k = PUNYCODE_BASE; 1; $k += PUNYCODE_BASE) {
          my $t = $k - $bias;
          $t =
              $t < PUNYCODE_TMIN ? PUNYCODE_TMIN
            : $t > PUNYCODE_TMAX ? PUNYCODE_TMAX
            :                      $t;
          last if $q < $t;

          # Code point for digit "t"
          my $o = $t + (($q - $t) % (PUNYCODE_BASE - $t));
          $output .= chr $o + ($o < 26 ? 0x61 : 0x30 - 26);

          $q = ($q - $t) / (PUNYCODE_BASE - $t);
        }

        # Code point for digit "q"
        $output .= chr $q + ($q < 26 ? 0x61 : 0x30 - 26);

        # Bias
        $bias = _adapt($delta, $h + 1, $h == $b);
        $delta = 0;
        $h++;
      }
    }

    $delta++;
    $n++;
  }

  $_[0] = $output;
}

sub qp_decode { $_[0] = MIME::QuotedPrint::decode_qp($_[0]) }

sub qp_encode { $_[0] = MIME::QuotedPrint::encode_qp($_[0]) }

sub quote {

  # Escape and quote
  $_[0] =~ s/([\"\\])/\\$1/g;
  $_[0] = '"' . $_[0] . '"';
}

sub secure_compare {
  my ($a, $b) = @_;
  return if length $a != length $b;
  my $r = 0;
  $r |= ord(substr $a, $_) ^ ord(substr $b, $_) for 0 .. length($a) - 1;
  return $r == 0 ? 1 : undef;
}

sub sha1_bytes { _sha1(@_) }

sub sha1_sum {
  die <<'EOF' unless SHA1;
Module "Digest::SHA" not present in this version of Perl.
Please install it manually or upgrade Perl to at least version 5.10.
EOF
  Digest::SHA::sha1_hex(@_);
}

sub trim {
  for ($_[0]) {
    s/^\s*//;
    s/\s*$//;
  }
}

sub unquote {

  # Not quoted
  return unless $_[0] =~ /^\".*\"$/g;

  # Unquote
  for ($_[0]) {
    s/^\"//g;
    s/\"$//g;
    s/\\\\/\\/g;
    s/\\\"/\"/g;
  }
}

sub url_escape {

  # Default to unreserved characters
  my $pattern = $_[1] || 'A-Za-z0-9\-\.\_\~';

  # Escape
  return unless $_[0] =~ /[^$pattern]/;
  $_[0] =~ s/([^$pattern])/sprintf('%%%02X',ord($1))/ge;
}

# "I've gone back in time to when dinosaurs weren't just confined to zoos."
sub url_unescape {
  return if index($_[0], '%') == -1;
  $_[0] =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
}

sub xml_escape {

  # Replace "&", "<", ">", """ and "'"
  for ($_[0]) {
    s/&/&amp;/g;
    s/</&lt;/g;
    s/>/&gt;/g;
    s/"/&quot;/g;
    s/'/&#39;/g;
  }
}

# Helper for punycode
sub _adapt {
  my ($delta, $numpoints, $firsttime) = @_;

  use integer;
  $delta = $firsttime ? $delta / PUNYCODE_DAMP : $delta / 2;
  $delta += $delta / $numpoints;
  my $k = 0;
  while ($delta > ((PUNYCODE_BASE - PUNYCODE_TMIN) * PUNYCODE_TMAX) / 2) {
    $delta /= PUNYCODE_BASE - PUNYCODE_TMIN;
    $k += PUNYCODE_BASE;
  }

  return $k
    + (
    ((PUNYCODE_BASE - PUNYCODE_TMIN + 1) * $delta) / ($delta + PUNYCODE_SKEW)
    );
}

sub _hmac {

  # Secret
  my $secret = $_[2] || 'Very unsecure!';
  $secret = $_[0]->($secret) if length $secret > 64;

  # HMAC
  my $ipad = $secret ^ (chr(0x36) x 64);
  my $opad = $secret ^ (chr(0x5c) x 64);
  return unpack 'H*', $_[0]->($opad . $_[0]->($ipad . $_[1]));
}

# Helper for md5_bytes
sub _md5 { Digest::MD5::md5(shift) }

# Helper for sha1_bytes
sub _sha1 {
  die <<'EOF' unless SHA1;
Module "Digest::SHA" not present in this version of Perl.
Please install it manually or upgrade Perl to at least version 5.10.
EOF
  Digest::SHA::sha1(shift);
}

# Helper for html_unescape
sub _unescape {
  if ($_[0]) {
    return chr hex $_[0] if substr($_[0], 0, 1) eq 'x';
    return chr $_[0];
  }
  return exists $ENTITIES{$_[1]} ? chr $ENTITIES{$_[1]} : "&$_[1];";
}

1;
__END__

=head1 NAME

Mojo::Util - Portable Utility Functions

=head1 SYNOPSIS

  use Mojo::Util qw/url_escape url_unescape/;

  my $string = 'test=23';
  url_escape $string;
  url_unescape $string;

=head1 DESCRIPTION

L<Mojo::Util> provides portable utility functions for L<Mojo>.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 FUNCTIONS

L<Mojo::Util> implements the following functions.

=head2 C<b64_decode>

  b64_decode $string;

Base64 decode in-place.

=head2 C<b64_encode>

  b64_encode $string;

Base64 encode in-place.

=head2 C<camelize>

  camelize $string;

Convert snake case string to camel case and replace C<-> with C<::> in-place.

  foo_bar     -> FooBar
  foo_bar-baz -> FooBar::Baz

=head2 C<decamelize>

  decamelize $string;

Convert camel case string to snake case and replace C<::> with C<-> in-place.

  FooBar      -> foo_bar
  FooBar::Baz -> foo_bar-baz

=head2 C<decode>

  decode 'UTF-8', $octets;

Decode octets in-place.

=head2 C<encode>

  encode 'UTF-8', $chars;

Encode characters in-place.

=head2 C<get_line>

  my $line = get_line $chunk;

Extract a whole line from chunk or return undef.
Lines are expected to end with C<0x0d 0x0a> or C<0x0a>.

=head2 C<hmac_md5_sum>

  my $checksum = hmac_md5_sum $string, $secret;

Generate HMAC-MD5 checksum for string.

=head2 C<hmac_sha1_sum>

  my $checksum = hmac_sha1_sum $string, $secret;

Generate HMAC-SHA1 checksum for string.
Note that Perl 5.10 or L<Digest::SHA> are required for C<SHA1> support.

=head2 C<html_escape>

  html_escape $string;

HTML escape string in-place.

=head2 C<html_unescape>

  html_unescape $string;

HTML unescape string in-place.

=head2 C<md5_bytes>

  my $checksum = md5_bytes $string;

Generate binary MD5 checksum.

=head2 C<md5_sum>

  my $checksum = md5_sum $string;

Generate MD5 checksum.

=head2 C<punycode_decode>

  punycode_decode $string;

Punycode decode string in-place, as described in RFC 3492.

=head2 C<punycode_encode>

  punycode_encode $string;

Punycode encode string in-place, as described in RFC 3492.

=head2 C<quote>

  quote $string;

Quote string in-place.

=head2 C<qp_decode>

  qp_decode $string;

Quoted Printable decode in-place.

=head2 C<qp_encode>

  qp_encode $string;

Quoted Printable encode in-place.

=head2 C<secure_compare>

  my $success = secure_compare $string1, $string2;

Constant time comparison algorithm to prevent timing attacks.

=head2 C<sha1_bytes>

  my $checksum = sha1_bytes $string;

Generate binary SHA1 checksum.
Note that Perl 5.10 or L<Digest::SHA> are required for C<SHA1> support.

=head2 C<sha1_sum>

  my $checksum = sha1_sum $string;

Generate SHA1 checksum.
Note that Perl 5.10 or L<Digest::SHA> are required for C<SHA1> support.

=head2 C<trim>

  trim $string;

Trim whitespace characters from both ends of string in-place.

=head2 C<unquote>

  unquote $string;

Unquote string in-place.

=head2 C<url_escape>

  url_escape $string;
  url_escape $string, 'A-Za-z0-9\-\.\_\~';

URL escape in-place.

=head2 C<url_unescape>

  url_unescape $string;

URL unescape in-place.

=head2 C<xml_escape>

  xml_escape $string;

XML escape string in-place, this is a much faster version of C<html_escape>
escaping only the characters C<&>, C<E<lt>>, C<E<gt>>, C<"> and C<'>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
