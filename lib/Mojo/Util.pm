package Mojo::Util;
use Mojo::Base 'Exporter';

use Digest::MD5 qw/md5 md5_hex/;
use Digest::SHA qw/sha1 sha1_hex/;
use Encode 'find_encoding';
use MIME::Base64 qw/decode_base64 encode_base64/;
use MIME::QuotedPrint qw/decode_qp encode_qp/;

# Punycode bootstring parameters
use constant {
  PC_BASE         => 36,
  PC_TMIN         => 1,
  PC_TMAX         => 26,
  PC_SKEW         => 38,
  PC_DAMP         => 700,
  PC_INITIAL_BIAS => 72,
  PC_INITIAL_N    => 128
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

# Entities regex for html_unescape
my $ENTITIES_RE = qr/&(?:\#((?:\d{1,7}|x[0-9A-Fa-f]{1,6}))|([A-Za-z]{1,8}));/;

# Encode cache
my %ENCODE;

# "Bart, stop pestering Satan!"
our @EXPORT_OK = (
  qw/b64_decode b64_encode camelize decamelize decode encode get_line/,
  qw/hmac_md5_sum hmac_sha1_sum html_escape html_unescape md5_bytes md5_sum/,
  qw/punycode_decode punycode_encode qp_decode qp_encode quote/,
  qw/secure_compare sha1_bytes sha1_sum trim unquote url_escape/,
  qw/url_unescape xml_escape/
);

sub b64_decode { decode_base64(shift) }

sub b64_encode { encode_base64(shift, shift) }

sub camelize {
  my $string = shift;
  return $string if $string =~ /^[A-Z]/;

  # Camel case words
  return join '::', map {
    join '', map { ucfirst lc } split /_/, $_
  } split /-/, $string;
}

sub decamelize {
  my $string = shift;
  return $string if $string !~ /^[A-Z]/;

  # Module parts
  my @parts;
  for my $part (split /\:\:/, $string) {

    # Snake case words
    my @words;
    push @words, lc $1 while $part =~ s/([A-Z]{1}[^A-Z]*)//;
    push @parts, join '_', @words;
  }

  return join '-', @parts;
}

sub decode {
  my ($encoding, $bytes) = @_;

  # Try decoding
  return unless eval {

    # UTF-8
    if ($encoding eq 'UTF-8') { die unless utf8::decode $bytes }

    # Everything else
    else {
      $bytes =
        ($ENCODE{$encoding} ||= find_encoding($encoding))->decode($bytes, 1);
    }

    1;
  };

  return $bytes;
}

sub encode {
  my ($encoding, $chars) = @_;

  # UTF-8
  if ($encoding eq 'UTF-8') {
    utf8::encode $chars;
    return $chars;
  }

  # Everything else
  return ($ENCODE{$encoding} ||= find_encoding($encoding))->encode($chars);
}

sub get_line {
  my $stringref = shift;

  # Locate line ending
  return if (my $pos = index $$stringref, "\x0a") == -1;

  # Extract line and ending
  my $line = substr $$stringref, 0, $pos + 1, '';
  $line =~ s/\x0d?\x0a$//;

  return $line;
}

sub hmac_md5_sum  { _hmac(0, @_) }
sub hmac_sha1_sum { _hmac(1, @_) }

sub html_escape {
  my $string = shift;

  my $escaped = '';
  for my $i (0 .. (length($string) - 1)) {

    # Escape entities
    my $char = substr $string, $i, 1;
    my $num = unpack 'U', $char;
    if (my $named = $REVERSE_ENTITIES{$num}) { $char = "&$named;" }
    $escaped .= $char;
  }

  return $escaped;
}

# "Daddy, I'm scared. Too scared to even wet my pants.
#  Just relax and it'll come, son."
sub html_unescape {
  my $string = shift;
  $string =~ s/$ENTITIES_RE/_unescape($1, $2)/ge;
  return $string;
}

sub md5_bytes { md5(@_) }
sub md5_sum   { md5_hex(@_) }

sub punycode_decode {
  my $input = shift;
  use integer;

  # Defaults
  my $n    = PC_INITIAL_N;
  my $i    = 0;
  my $bias = PC_INITIAL_BIAS;
  my @output;

  # Delimiter
  if ($input =~ s/(.*)$DELIMITER//s) { push @output, split //, $1 }

  # Decode (direct translation of RFC 3492)
  while (length $input) {
    my $oldi = $i;
    my $w    = 1;

    # Base to infinity in steps of base
    for (my $k = PC_BASE; 1; $k += PC_BASE) {

      # Digit
      my $digit = ord substr $input, 0, 1, '';
      $digit = $digit < 0x40 ? $digit + (26 - 0x30) : ($digit & 0x1f) - 1;
      $i += $digit * $w;
      my $t = $k - $bias;
      $t = $t < PC_TMIN ? PC_TMIN : $t > PC_TMAX ? PC_TMAX : $t;
      last if $digit < $t;

      $w *= (PC_BASE - $t);
    }

    # Bias
    $bias = _adapt($i - $oldi, @output + 1, $oldi == 0);
    $n += $i / (@output + 1);
    $i = $i % (@output + 1);

    # Insert
    splice @output, $i, 0, chr($n);
    $i++;
  }

  return join '', @output;
}

sub punycode_encode {
  use integer;

  # Defaults
  my $output = shift;
  my $len    = length $output;

  # Split input
  my @input = map ord, split //, $output;
  my @chars = sort grep { $_ >= PC_INITIAL_N } @input;

  # Remove non basic characters
  $output =~ s/[^\x00-\x7f]+//gs;

  # Non basic characters in input
  my $h = my $b = length $output;
  $output .= $DELIMITER if $b > 0;

  # Defaults
  my $n     = PC_INITIAL_N;
  my $delta = 0;
  my $bias  = PC_INITIAL_BIAS;

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
        for (my $k = PC_BASE; 1; $k += PC_BASE) {
          my $t = $k - $bias;
          $t = $t < PC_TMIN ? PC_TMIN : $t > PC_TMAX ? PC_TMAX : $t;
          last if $q < $t;

          # Code point for digit "t"
          my $o = $t + (($q - $t) % (PC_BASE - $t));
          $output .= chr $o + ($o < 26 ? 0x61 : 0x30 - 26);

          $q = ($q - $t) / (PC_BASE - $t);
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

  return $output;
}

sub qp_decode { decode_qp(shift) }

sub qp_encode { encode_qp(shift) }

sub quote {
  my $string = shift;
  $string =~ s/(["\\])/\\$1/g;
  return qq/"$string"/;
}

sub secure_compare {
  my ($a, $b) = @_;
  return if length $a != length $b;
  my $r = 0;
  $r |= ord(substr $a, $_) ^ ord(substr $b, $_) for 0 .. length($a) - 1;
  return $r == 0 ? 1 : undef;
}

sub sha1_bytes { sha1(@_) }
sub sha1_sum   { sha1_hex(@_) }

sub trim {
  my $string = shift;
  for ($string) {
    s/^\s*//;
    s/\s*$//;
  }
  return $string;
}

sub unquote {
  my $string = shift;
  return $string unless $string =~ /^".*"$/g;

  # Unquote
  for ($string) {
    s/^"//g;
    s/"$//g;
    s/\\\\/\\/g;
    s/\\"/"/g;
  }

  return $string;
}

sub url_escape {
  my ($string, $pattern) = @_;
  $pattern ||= 'A-Za-z0-9\-\.\_\~';
  return $string unless $string =~ /[^$pattern]/;
  $string =~ s/([^$pattern])/sprintf('%%%02X',ord($1))/ge;
  return $string;
}

# "I've gone back in time to when dinosaurs weren't just confined to zoos."
sub url_unescape {
  my $string = shift;
  return $string if index($string, '%') == -1;
  $string =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
  return $string;
}

sub xml_escape {
  my $string = shift;
  for ($string) {
    s/&/&amp;/g;
    s/</&lt;/g;
    s/>/&gt;/g;
    s/"/&quot;/g;
    s/'/&#39;/g;
  }
  return $string;
}

# Helper for punycode
sub _adapt {
  my ($delta, $numpoints, $firsttime) = @_;

  use integer;
  $delta = $firsttime ? $delta / PC_DAMP : $delta / 2;
  $delta += $delta / $numpoints;
  my $k = 0;
  while ($delta > ((PC_BASE - PC_TMIN) * PC_TMAX) / 2) {
    $delta /= PC_BASE - PC_TMIN;
    $k += PC_BASE;
  }

  return $k + (((PC_BASE - PC_TMIN + 1) * $delta) / ($delta + PC_SKEW));
}

sub _hmac {
  my ($sha, $string, $secret) = @_;

  # Hash function
  my $hash = $sha ? sub { sha1(@_) } : sub { md5(@_) };

  # Secret
  $secret = $secret ? "$secret" : 'Very unsecure!';
  $secret = $hash->($secret) if length $secret > 64;

  # HMAC
  my $ipad = $secret ^ (chr(0x36) x 64);
  my $opad = $secret ^ (chr(0x5c) x 64);
  return unpack 'H*', $hash->($opad . $hash->($ipad . $string));
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

Mojo::Util - Portable utility functions

=head1 SYNOPSIS

  use Mojo::Util qw/url_escape url_unescape/;

  my $string = 'test=23';
  my $escaped = url_escape $string;
  say url_unescape $escaped;

=head1 DESCRIPTION

L<Mojo::Util> provides portable utility functions for L<Mojo>.

=head1 FUNCTIONS

L<Mojo::Util> implements the following functions.

=head2 C<b64_decode>

  my $string = b64_decode $b64;

Base64 decode string.

=head2 C<b64_encode>

  my $b64 = b64_encode $string;

Base64 encode string.

=head2 C<camelize>

  my $camelcase = camelize $snakecase;

Convert snake case string to camel case and replace C<-> with C<::>.

  # "FooBar"
  camelize 'foo_bar';

  # "FooBar::Baz"
  camelize 'foo_bar-baz';

  # "FooBar::Baz"
  camelize 'FooBar::Baz';

=head2 C<decamelize>

  my $snakecase = decamelize $camelcase;

Convert camel case string to snake case and replace C<::> with C<->.

  # "foo_bar"
  decamelize 'FooBar';

  # "foo_bar-baz"
  decamelize 'FooBar::Baz';

  # "foo_bar-baz"
  decamelize 'foo_bar-baz';

=head2 C<decode>

  my $chars = decode 'UTF-8', $bytes;

Decode bytes to characters.

=head2 C<encode>

  my $bytes = encode 'UTF-8', $chars;

Encode characters to bytes.

=head2 C<get_line>

  my $line = get_line \$string;

Extract whole line from string or return C<undef>. Lines are expected to end
with C<0x0d 0x0a> or C<0x0a>.

=head2 C<hmac_md5_sum>

  my $checksum = hmac_md5_sum $string, $secret;

Generate HMAC-MD5 checksum for string.

=head2 C<hmac_sha1_sum>

  my $checksum = hmac_sha1_sum $string, $secret;

Generate HMAC-SHA1 checksum for string.

=head2 C<html_escape>

  my $escaped = html_escape $string;

HTML escape string.

=head2 C<html_unescape>

  my $string = html_unescape $escaped;

HTML unescape string.

=head2 C<md5_bytes>

  my $checksum = md5_bytes $string;

Generate binary MD5 checksum for string.

=head2 C<md5_sum>

  my $checksum = md5_sum $string;

Generate MD5 checksum for string.

=head2 C<punycode_decode>

  my $string = punycode_decode $punycode;

Punycode decode string.

=head2 C<punycode_encode>

  my $punycode = punycode_encode $string;

Punycode encode string.

=head2 C<quote>

  my $quoted = quote $string;

Quote string.

=head2 C<qp_decode>

  my $string = qp_decode $qp;

Quoted Printable decode string.

=head2 C<qp_encode>

  my $qp = qp_encode $string;

Quoted Printable encode string.

=head2 C<secure_compare>

  my $success = secure_compare $string1, $string2;

Constant time comparison algorithm to prevent timing attacks.

=head2 C<sha1_bytes>

  my $checksum = sha1_bytes $string;

Generate binary SHA1 checksum for string.

=head2 C<sha1_sum>

  my $checksum = sha1_sum $string;

Generate SHA1 checksum for string.

=head2 C<trim>

  my $trimmed = trim $string;

Trim whitespace characters from both ends of string.

=head2 C<unquote>

  my $string = unquote $quoted;

Unquote string.

=head2 C<url_escape>

  my $escaped = url_escape $string;
  my $escaped = url_escape $string, 'A-Za-z0-9\-\.\_\~';

URL escape string.

=head2 C<url_unescape>

  my $string = url_unescape $escaped;

URL unescape string.

=head2 C<xml_escape>

  my $escaped = xml_escape $string;

XML escape string, this is a much faster version of C<html_escape> escaping
only the characters C<&>, C<E<lt>>, C<E<gt>>, C<"> and C<'>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
