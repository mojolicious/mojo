package Mojo::Util;
use Mojo::Base 'Exporter';

use Carp qw(carp croak);
use Digest::MD5 qw(md5 md5_hex);
use Digest::SHA qw(sha1 sha1_hex);
use Encode 'find_encoding';
use File::Basename 'dirname';
use File::Spec::Functions 'catfile';
use MIME::Base64 qw(decode_base64 encode_base64);
use Time::HiRes ();

# Check for monotonic clock support
use constant MONOTONIC => eval
  '!!Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC())';

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

# To update HTML5 entities run this command
# perl examples/entities.pl > lib/Mojo/entities.txt
my %ENTITIES;
for my $line (split "\x0a", slurp(catfile dirname(__FILE__), 'entities.txt')) {
  next unless $line =~ /^(\S+)\s+U\+(\S+)(?:\s+U\+(\S+))?/;
  $ENTITIES{$1} = defined $3 ? (chr(hex $2) . chr(hex $3)) : chr(hex $2);
}

# Encoding cache
my %CACHE;

our @EXPORT_OK = (
  qw(b64_decode b64_encode camelize class_to_file class_to_path decamelize),
  qw(decode deprecated encode get_line hmac_sha1_sum html_unescape md5_bytes),
  qw(md5_sum monkey_patch punycode_decode punycode_encode quote),
  qw(secure_compare sha1_bytes sha1_sum slurp spurt squish steady_time trim),
  qw(unquote url_escape url_unescape xml_escape xor_encode)
);

sub b64_decode { decode_base64($_[0]) }
sub b64_encode { encode_base64($_[0], $_[1]) }

sub camelize {
  my $str = shift;
  return $str if $str =~ /^[A-Z]/;

  # Camel case words
  return join '::', map {
    join '', map { ucfirst lc } split /_/, $_
  } split /-/, $str;
}

sub class_to_file {
  my $class = shift;
  $class =~ s/::|'//g;
  $class =~ s/([A-Z])([A-Z]*)/$1.lc($2)/ge;
  return decamelize($class);
}

sub class_to_path { join '.', join('/', split /::|'/, shift), 'pm' }

sub decamelize {
  my $str = shift;
  return $str if $str !~ /^[A-Z]/;

  # Module parts
  my @parts;
  for my $part (split /::/, $str) {

    # Snake case words
    my @words;
    push @words, lc $1 while $part =~ s/([A-Z]{1}[^A-Z]*)//;
    push @parts, join '_', @words;
  }

  return join '-', @parts;
}

sub decode {
  my ($encoding, $bytes) = @_;
  return undef
    unless eval { $bytes = _encoding($encoding)->decode("$bytes", 1); 1 };
  return $bytes;
}

sub deprecated {
  local $Carp::CarpLevel = 1;
  $ENV{MOJO_FATAL_DEPRECATIONS} ? croak(@_) : carp(@_);
}

sub encode { _encoding($_[0])->encode("$_[1]") }

sub get_line {

  # Locate line ending
  return undef if (my $pos = index ${$_[0]}, "\x0a") == -1;

  # Extract line and ending
  my $line = substr ${$_[0]}, 0, $pos + 1, '';
  $line =~ s/\x0d?\x0a$//;

  return $line;
}

sub hmac_sha1_sum {
  my ($str, $secret) = @_;
  $secret = $secret ? "$secret" : 'Very insecure!';
  $secret = sha1 $secret if length $secret > 64;

  my $ipad = $secret ^ (chr(0x36) x 64);
  my $opad = $secret ^ (chr(0x5c) x 64);
  return unpack 'H*', sha1($opad . sha1($ipad . $str));
}

sub html_unescape {
  my $str = shift;
  return $str if index($str, '&') == -1;
  $str
    =~ s/&(?:\#((?:\d{1,7}|x[[:xdigit:]]{1,6}));|(\w+;?))/_decode($1, $2)/ge;
  return $str;
}

sub md5_bytes { md5(@_) }
sub md5_sum   { md5_hex(@_) }

sub monkey_patch {
  my ($class, %patch) = @_;
  no strict 'refs';
  no warnings 'redefine';
  *{"${class}::$_"} = $patch{$_} for keys %patch;
}

# Direct translation of RFC 3492
sub punycode_decode {
  my $input = shift;
  use integer;

  # Delimiter
  my @output;
  push @output, split //, $1 if $input =~ s/(.*)\x2d//s;

  my $n    = PC_INITIAL_N;
  my $i    = 0;
  my $bias = PC_INITIAL_BIAS;
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

    splice @output, $i++, 0, chr $n;
  }

  return join '', @output;
}

# Direct translation of RFC 3492
sub punycode_encode {
  my $output = shift;
  use integer;

  # Split input
  my $len   = length $output;
  my @input = map {ord} split //, $output;
  my @chars = sort grep { $_ >= PC_INITIAL_N } @input;

  # Handle non-basic characters
  $output =~ s/[^\x00-\x7f]+//gs;
  my $h = my $b = length $output;
  $output .= "\x2d" if $b > 0;

  my $n     = PC_INITIAL_N;
  my $delta = 0;
  my $bias  = PC_INITIAL_BIAS;
  for my $m (@chars) {

    # Basic character
    next if $m < $n;

    # Walk all code points in order
    $delta += ($m - $n) * ($h + 1);
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

sub quote {
  my $str = shift;
  $str =~ s/(["\\])/\\$1/g;
  return qq{"$str"};
}

sub secure_compare {
  my ($a, $b) = @_;
  return undef if length $a != length $b;
  my $r = 0;
  $r |= ord(substr $a, $_) ^ ord(substr $b, $_) for 0 .. length($a) - 1;
  return $r == 0;
}

sub sha1_bytes { sha1(@_) }
sub sha1_sum   { sha1_hex(@_) }

sub slurp {
  my $path = shift;
  croak qq{Can't open file "$path": $!} unless open my $file, '<', $path;
  my $content = '';
  while ($file->sysread(my $buffer, 131072, 0)) { $content .= $buffer }
  return $content;
}

sub spurt {
  my ($content, $path) = @_;
  croak qq{Can't open file "$path": $!} unless open my $file, '>', $path;
  croak qq{Can't write to file "$path": $!}
    unless defined $file->syswrite($content);
  return $content;
}

sub squish {
  my $str = trim(@_);
  $str =~ s/\s+/ /g;
  return $str;
}

sub steady_time () {
  MONOTONIC
    ? Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC())
    : Time::HiRes::time;
}

sub trim {
  my $str = shift;
  $str =~ s/^\s+|\s+$//g;
  return $str;
}

sub unquote {
  my $str = shift;
  return $str unless $str =~ s/^"(.*)"$/$1/g;
  $str =~ s/\\\\/\\/g;
  $str =~ s/\\"/"/g;
  return $str;
}

sub url_escape {
  my ($str, $pattern) = @_;
  $pattern ||= '^A-Za-z0-9\-._~';
  $str =~ s/([$pattern])/sprintf('%%%02X',ord($1))/ge;
  return $str;
}

sub url_unescape {
  my $str = shift;
  return $str if index($str, '%') == -1;
  $str =~ s/%([[:xdigit:]]{2})/chr(hex($1))/ge;
  return $str;
}

sub xml_escape {
  my $str = shift;

  $str =~ s/&/&amp;/g;
  $str =~ s/</&lt;/g;
  $str =~ s/>/&gt;/g;
  $str =~ s/"/&quot;/g;
  $str =~ s/'/&#39;/g;

  return $str;
}

sub xor_encode {
  my ($input, $key) = @_;

  # Encode with variable key length
  my $len = length $key;
  my $buffer = my $output = '';
  $output .= $buffer ^ $key
    while length($buffer = substr($input, 0, $len, '')) == $len;
  return $output .= $buffer ^ substr($key, 0, length $buffer, '');
}

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

sub _decode {
  my ($point, $name) = @_;

  # Code point
  return chr($point !~ /^x/ ? $point : hex $point) unless defined $name;

  # Find entity name
  my $rest = '';
  while (length $name) {
    return "$ENTITIES{$name}$rest" if exists $ENTITIES{$name};
    $rest = chop($name) . $rest;
  }
  return "&$rest";
}

sub _encoding {
  $CACHE{$_[0]} //= find_encoding($_[0]) // croak "Unknown encoding '$_[0]'";
}

1;

=head1 NAME

Mojo::Util - Portable utility functions

=head1 SYNOPSIS

  use Mojo::Util qw(b64_encode url_escape url_unescape);

  my $str = 'test=23';
  my $escaped = url_escape $str;
  say url_unescape $escaped;
  say b64_encode $escaped, '';

=head1 DESCRIPTION

L<Mojo::Util> provides portable utility functions for L<Mojo>.

=head1 FUNCTIONS

L<Mojo::Util> implements the following functions.

=head2 b64_decode

  my $str = b64_decode $b64;

Base64 decode string.

=head2 b64_encode

  my $b64 = b64_encode $str;
  my $b64 = b64_encode $str, "\n";

Base64 encode string, the line ending defaults to a newline.

=head2 camelize

  my $camelcase = camelize $snakecase;

Convert snake case string to camel case and replace C<-> with C<::>.

  # "FooBar"
  camelize 'foo_bar';

  # "FooBar::Baz"
  camelize 'foo_bar-baz';

  # "FooBar::Baz"
  camelize 'FooBar::Baz';

=head2 class_to_file

  my $file = class_to_file 'Foo::Bar';

Convert a class name to a file.

  Foo::Bar -> foo_bar
  FOO::Bar -> foobar
  FooBar   -> foo_bar
  FOOBar   -> foobar

=head2 class_to_path

  my $path = class_to_path 'Foo::Bar';

Convert class name to path.

  Foo::Bar -> Foo/Bar.pm
  FooBar   -> FooBar.pm

=head2 decamelize

  my $snakecase = decamelize $camelcase;

Convert camel case string to snake case and replace C<::> with C<->.

  # "foo_bar"
  decamelize 'FooBar';

  # "foo_bar-baz"
  decamelize 'FooBar::Baz';

  # "foo_bar-baz"
  decamelize 'foo_bar-baz';

=head2 decode

  my $chars = decode 'UTF-8', $bytes;

Decode bytes to characters and return C<undef> if decoding failed.

=head2 deprecated

  deprecated 'foo is DEPRECATED in favor of bar';

Warn about deprecated feature from perspective of caller. You can also set the
MOJO_FATAL_DEPRECATIONS environment variable to make them die instead.

=head2 encode

  my $bytes = encode 'UTF-8', $chars;

Encode characters to bytes.

=head2 get_line

  my $line = get_line \$str;

Extract whole line from string or return C<undef>. Lines are expected to end
with C<0x0d 0x0a> or C<0x0a>.

=head2 hmac_sha1_sum

  my $checksum = hmac_sha1_sum $str, 'passw0rd';

Generate HMAC-SHA1 checksum for string.

=head2 html_unescape

  my $str = html_unescape $escaped;

Unescape all HTML entities in string.

=head2 md5_bytes

  my $checksum = md5_bytes $str;

Generate binary MD5 checksum for string.

=head2 md5_sum

  my $checksum = md5_sum $str;

Generate MD5 checksum for string.

=head2 monkey_patch

  monkey_patch $package, foo => sub {...};
  monkey_patch $package, foo => sub {...}, bar => sub {...};

Monkey patch functions into package.

  monkey_patch 'MyApp',
    one   => sub { say 'One!' },
    two   => sub { say 'Two!' },
    three => sub { say 'Three!' };

=head2 punycode_decode

  my $str = punycode_decode $punycode;

Punycode decode string.

=head2 punycode_encode

  my $punycode = punycode_encode $str;

Punycode encode string.

=head2 quote

  my $quoted = quote $str;

Quote string.

=head2 secure_compare

  my $success = secure_compare $str1, $str2;

Constant time comparison algorithm to prevent timing attacks.

=head2 sha1_bytes

  my $checksum = sha1_bytes $str;

Generate binary SHA1 checksum for string.

=head2 sha1_sum

  my $checksum = sha1_sum $str;

Generate SHA1 checksum for string.

=head2 slurp

  my $content = slurp '/etc/passwd';

Read all data at once from file.

=head2 spurt

  $content = spurt $content, '/etc/passwd';

Write all data at once to file.

=head2 squish

  my $squished = squish $str;

Trim whitespace characters from both ends of string and then change all
consecutive groups of whitespace into one space each.

=head2 steady_time

  my $time = steady_time;

High resolution time, resilient to time jumps if a monotonic clock is
available through L<Time::HiRes>.

=head2 trim

  my $trimmed = trim $str;

Trim whitespace characters from both ends of string.

=head2 unquote

  my $str = unquote $quoted;

Unquote string.

=head2 url_escape

  my $escaped = url_escape $str;
  my $escaped = url_escape $str, '^A-Za-z0-9\-._~';

Percent encode unsafe characters in string, the pattern used defaults to
C<^A-Za-z0-9\-._~>.

=head2 url_unescape

  my $str = url_unescape $escaped;

Decode percent encoded characters in string.

=head2 xml_escape

  my $escaped = xml_escape $str;

Escape unsafe characters C<&>, C<E<lt>>, C<E<gt>>, C<"> and C<'> in string.

=head2 xor_encode

  my $encoded = xor_encode $str, $key;

XOR encode string with variable length key.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
