package Mojo::Util;
use Mojo::Base -strict;

use Carp qw(carp croak);
use Data::Dumper ();
use Digest::MD5 qw(md5 md5_hex);
use Digest::SHA qw(hmac_sha1_hex sha1 sha1_hex);
use Encode qw(find_encoding);
use Exporter qw(import);
use File::Basename qw(dirname);
use Getopt::Long qw(GetOptionsFromArray);
use IO::Compress::Gzip;
use IO::Poll qw(POLLIN POLLPRI);
use IO::Uncompress::Gunzip;
use List::Util qw(min);
use MIME::Base64 qw(decode_base64 encode_base64);
use Pod::Usage qw(pod2usage);
use Sub::Util qw(set_subname);
use Symbol qw(delete_package);
use Time::HiRes        ();
use Unicode::Normalize ();

# Check for monotonic clock support
use constant MONOTONIC => eval { !!Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC()) };

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

# To generate a new HTML entity table run this command
# perl examples/entities.pl > lib/Mojo/resources/html_entities.txt
my %ENTITIES;
{
  # Don't use Mojo::File here due to circular dependencies
  my $path = File::Spec->catfile(dirname(__FILE__), 'resources', 'html_entities.txt');

  open my $file, '<', $path or croak "Unable to open html entities file ($path): $!";
  my $lines = do { local $/; <$file> };

  for my $line (split "\n", $lines) {
    next unless $line =~ /^(\S+)\s+U\+(\S+)(?:\s+U\+(\S+))?/;
    $ENTITIES{$1} = defined $3 ? (chr(hex $2) . chr(hex $3)) : chr(hex $2);
  }
}

# Characters that should be escaped in XML
my %XML = ('&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;', '\'' => '&#39;');

# "Sun, 06 Nov 1994 08:49:37 GMT" and "Sunday, 06-Nov-94 08:49:37 GMT"
my $EXPIRES_RE = qr/(\w+\W+\d+\W+\w+\W+\d+\W+\d+:\d+:\d+\W*\w+)/;

# HTML entities
my $ENTITY_RE = qr/&(?:\#((?:[0-9]{1,7}|x[0-9a-fA-F]{1,6}));|(\w+[;=]?))/;

# Encoding and pattern cache
my (%ENCODING, %PATTERN);

our @EXPORT_OK = (
  qw(b64_decode b64_encode camelize class_to_file class_to_path decamelize),
  qw(decode deprecated dumper encode extract_usage getopt gunzip gzip),
  qw(hmac_sha1_sum html_attr_unescape html_unescape humanize_bytes md5_bytes),
  qw(md5_sum monkey_patch punycode_decode punycode_encode quote scope_guard),
  qw(secure_compare sha1_bytes sha1_sum slugify split_cookie_header),
  qw(split_header steady_time tablify term_escape trim unindent unquote),
  qw(url_escape url_unescape xml_escape xor_encode)
);

# Aliases
monkey_patch(__PACKAGE__, 'b64_decode',    \&decode_base64);
monkey_patch(__PACKAGE__, 'b64_encode',    \&encode_base64);
monkey_patch(__PACKAGE__, 'hmac_sha1_sum', \&hmac_sha1_hex);
monkey_patch(__PACKAGE__, 'md5_bytes',     \&md5);
monkey_patch(__PACKAGE__, 'md5_sum',       \&md5_hex);
monkey_patch(__PACKAGE__, 'sha1_bytes',    \&sha1);
monkey_patch(__PACKAGE__, 'sha1_sum',      \&sha1_hex);

# Use a monotonic clock if possible
monkey_patch(__PACKAGE__, 'steady_time',
  MONOTONIC ? sub () { Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC()) } : \&Time::HiRes::time);

sub camelize {
  my $str = shift;
  return $str if $str =~ /^[A-Z]/;

  # CamelCase words
  return join '::', map {
    join('', map { ucfirst lc } split '_')
  } split '-', $str;
}

sub class_to_file {
  my $class = shift;
  $class =~ s/::|'//g;
  $class =~ s/([A-Z])([A-Z]*)/$1 . lc $2/ge;
  return decamelize($class);
}

sub class_to_path { join '.', join('/', split(/::|'/, shift)), 'pm' }

sub decamelize {
  my $str = shift;
  return $str if $str !~ /^[A-Z]/;

  # snake_case words
  return join '-', map {
    join('_', map {lc} grep {length} split /([A-Z]{1}[^A-Z]*)/)
  } split '::', $str;
}

sub decode {
  my ($encoding, $bytes) = @_;
  return undef unless eval { $bytes = _encoding($encoding)->decode("$bytes", 1); 1 };
  return $bytes;
}

sub deprecated {
  local $Carp::CarpLevel = 1;
  $ENV{MOJO_FATAL_DEPRECATIONS} ? croak @_ : carp @_;
}

sub dumper { Data::Dumper->new([@_])->Indent(1)->Sortkeys(1)->Terse(1)->Useqq(1)->Dump }

sub encode { _encoding($_[0])->encode("$_[1]", 0) }

sub extract_usage {
  my $file = @_ ? "$_[0]" : (caller)[1];

  open my $handle, '>', \my $output;
  pod2usage -exitval => 'noexit', -input => $file, -output => $handle;
  $output =~ s/^.*\n|\n$//;
  $output =~ s/\n$//;

  return unindent($output);
}

sub getopt {
  my ($array, $opts) = map { ref $_[0] eq 'ARRAY' ? shift : $_ } \@ARGV, [];

  my $save   = Getopt::Long::Configure(qw(default no_auto_abbrev no_ignore_case), @$opts);
  my $result = GetOptionsFromArray $array, @_;
  Getopt::Long::Configure($save);

  return $result;
}

sub gunzip {
  my $compressed = shift;
  IO::Uncompress::Gunzip::gunzip \$compressed, \my $uncompressed
    or croak "Couldn't gunzip: $IO::Uncompress::Gunzip::GzipError";
  return $uncompressed;
}

sub gzip {
  my $uncompressed = shift;
  IO::Compress::Gzip::gzip \$uncompressed, \my $compressed or croak "Couldn't gzip: $IO::Compress::Gzip::GzipError";
  return $compressed;
}

sub html_attr_unescape { _html(shift, 1) }
sub html_unescape      { _html(shift, 0) }

sub humanize_bytes {
  my $size = shift;

  my $prefix = $size < 0 ? '-' : '';

  return "$prefix${size}B" if ($size = abs $size) < 1024;
  return $prefix . _round($size) . 'KiB' if ($size /= 1024) < 1024;
  return $prefix . _round($size) . 'MiB' if ($size /= 1024) < 1024;
  return $prefix . _round($size) . 'GiB' if ($size /= 1024) < 1024;
  return $prefix . _round($size /= 1024) . 'TiB';
}

sub monkey_patch {
  my ($class, %patch) = @_;
  no strict 'refs';
  no warnings 'redefine';
  *{"${class}::$_"} = set_subname("${class}::$_", $patch{$_}) for keys %patch;
}

# Direct translation of RFC 3492
sub punycode_decode {
  my $input = shift;
  use integer;

  my ($n, $i, $bias, @output) = (PC_INITIAL_N, 0, PC_INITIAL_BIAS);

  # Consume all code points before the last delimiter
  push @output, split('', $1) if $input =~ s/(.*)\x2d//s;

  while (length $input) {
    my ($oldi, $w) = ($i, 1);

    # Base to infinity in steps of base
    for (my $k = PC_BASE; 1; $k += PC_BASE) {
      my $digit = ord substr $input, 0, 1, '';
      $digit = $digit < 0x40 ? $digit + (26 - 0x30) : ($digit & 0x1f) - 1;
      $i += $digit * $w;
      my $t = $k - $bias;
      $t = $t < PC_TMIN ? PC_TMIN : $t > PC_TMAX ? PC_TMAX : $t;
      last if $digit < $t;
      $w *= PC_BASE - $t;
    }

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

  my ($n, $delta, $bias) = (PC_INITIAL_N, 0, PC_INITIAL_BIAS);

  # Extract basic code points
  my @input = map {ord} split '', $output;
  $output =~ s/[^\x00-\x7f]+//gs;
  my $h = my $basic = length $output;
  $output .= "\x2d" if $basic > 0;

  for my $m (sort grep { $_ >= PC_INITIAL_N } @input) {
    next if $m < $n;
    $delta += ($m - $n) * ($h + 1);
    $n = $m;

    for my $c (@input) {

      if ($c < $n) { $delta++ }
      elsif ($c == $n) {
        my $q = $delta;

        # Base to infinity in steps of base
        for (my $k = PC_BASE; 1; $k += PC_BASE) {
          my $t = $k - $bias;
          $t = $t < PC_TMIN ? PC_TMIN : $t > PC_TMAX ? PC_TMAX : $t;
          last if $q < $t;
          my $o = $t + (($q - $t) % (PC_BASE - $t));
          $output .= chr $o + ($o < 26 ? 0x61 : 0x30 - 26);
          $q = ($q - $t) / (PC_BASE - $t);
        }

        $output .= chr $q + ($q < 26 ? 0x61 : 0x30 - 26);
        $bias  = _adapt($delta, $h + 1, $h == $basic);
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

sub scope_guard { Mojo::Util::_Guard->new(cb => shift) }

sub secure_compare {
  my ($one, $two) = @_;
  return undef if length $one != length $two;
  my $r = 0;
  $r |= ord(substr $one, $_) ^ ord(substr $two, $_) for 0 .. length($one) - 1;
  return $r == 0;
}

sub slugify {
  my ($value, $allow_unicode) = @_;

  if ($allow_unicode) {

    # Force unicode semantics by upgrading string
    utf8::upgrade($value = Unicode::Normalize::NFKC($value));
    $value =~ s/[^\w\s-]+//g;
  }
  else {
    $value = Unicode::Normalize::NFKD($value);
    $value =~ s/[^a-zA-Z0-9_\p{PosixSpace}-]+//g;
  }
  (my $new = lc trim($value)) =~ s/[-\s]+/-/g;

  return $new;
}

sub split_cookie_header { _header(shift, 1) }
sub split_header        { _header(shift, 0) }

sub tablify {
  my $rows = shift;

  my @spec;
  for my $row (@$rows) {
    for my $i (0 .. $#$row) {
      ($row->[$i] //= '') =~ y/\r\n//d;
      my $len = length $row->[$i];
      $spec[$i] = $len if $len >= ($spec[$i] // 0);
    }
  }

  my @fm = (map({"\%-${_}s"} @spec[0 .. $#spec - 1]), '%s');
  return join '', map { sprintf join('  ', @fm[0 .. $#$_]) . "\n", @$_ } @$rows;
}

sub term_escape {
  my $str = shift;
  $str =~ s/([\x00-\x09\x0b-\x1f\x7f\x80-\x9f])/sprintf '\\x%02x', ord $1/ge;
  return $str;
}

sub trim {
  my $str = shift;
  $str =~ s/^\s+//;
  $str =~ s/\s+$//;
  return $str;
}

sub unindent {
  my $str = shift;
  my $min = min map { m/^([ \t]*)/; length $1 || () } split "\n", $str;
  $str =~ s/^[ \t]{0,$min}//gm if $min;
  return $str;
}

sub unquote {
  my $str = shift;
  return $str unless $str =~ s/^"(.*)"$/$1/g;
  $str                    =~ s/\\\\/\\/g;
  $str                    =~ s/\\"/"/g;
  return $str;
}

sub url_escape {
  my ($str, $pattern) = @_;

  if ($pattern) {
    unless (exists $PATTERN{$pattern}) {
      (my $quoted = $pattern) =~ s!([/\$\[])!\\$1!g;
      $PATTERN{$pattern} = eval "sub { \$_[0] =~ s/([$quoted])/sprintf '%%%02X', ord \$1/ge }" or croak $@;
    }
    $PATTERN{$pattern}->($str);
  }
  else { $str =~ s/([^A-Za-z0-9\-._~])/sprintf '%%%02X', ord $1/ge }

  return $str;
}

sub url_unescape {
  my $str = shift;
  $str =~ s/%([0-9a-fA-F]{2})/chr hex $1/ge;
  return $str;
}

sub xml_escape {
  return $_[0] if ref $_[0] && ref $_[0] eq 'Mojo::ByteStream';
  my $str = shift // '';
  $str =~ s/([&<>"'])/$XML{$1}/ge;
  return $str;
}

sub xor_encode {
  my ($input, $key) = @_;

  # Encode with variable key length
  my $len    = length $key;
  my $buffer = my $output = '';
  $output .= $buffer ^ $key while length($buffer = substr($input, 0, $len, '')) == $len;
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
    $k     += PC_BASE;
  }

  return $k + (((PC_BASE - PC_TMIN + 1) * $delta) / ($delta + PC_SKEW));
}

sub _encoding { $ENCODING{$_[0]} //= find_encoding($_[0]) // croak "Unknown encoding '$_[0]'" }

sub _entity {
  my ($point, $name, $attr) = @_;

  # Code point
  return chr($point !~ /^x/ ? $point : hex $point) unless defined $name;

  # Named character reference
  my $rest = my $last = '';
  while (length $name) {
    return $ENTITIES{$name} . reverse $rest
      if exists $ENTITIES{$name} && (!$attr || $name =~ /;$/ || $last !~ /[A-Za-z0-9=]/);
    $rest .= $last = chop $name;
  }
  return '&' . reverse $rest;
}

# Supported on Perl 5.14+
sub _global_destruction { defined ${^GLOBAL_PHASE} && ${^GLOBAL_PHASE} eq 'DESTRUCT' }

sub _header {
  my ($str, $cookie) = @_;

  my (@tree, @part);
  while ($str =~ /\G[,;\s]*([^=;, ]+)\s*/gc) {
    push @part, $1, undef;
    my $expires = $cookie && @part > 2 && lc $1 eq 'expires';

    # Special "expires" value
    if ($expires && $str =~ /\G=\s*$EXPIRES_RE/gco) { $part[-1] = $1 }

    # Quoted value
    elsif ($str =~ /\G=\s*("(?:\\\\|\\"|[^"])*")/gc) { $part[-1] = unquote $1 }

    # Unquoted value
    elsif ($str =~ /\G=\s*([^;, ]*)/gc) { $part[-1] = $1 }

    # Separator
    next unless $str =~ /\G[;\s]*,\s*/gc;
    push @tree, [@part];
    @part = ();
  }

  # Take care of final part
  return [@part ? (@tree, \@part) : @tree];
}

sub _html {
  my ($str, $attr) = @_;
  $str =~ s/$ENTITY_RE/_entity($1, $2, $attr)/geo;
  return $str;
}

sub _options {

  # Hash or name (one)
  return ref $_[0] eq 'HASH' ? (undef, %{shift()}) : @_ if @_ == 1;

  # Name and values (odd)
  return shift, @_ if @_ % 2;

  # Name and hash or just values (even)
  return ref $_[1] eq 'HASH' ? (shift, %{shift()}) : (undef, @_);
}

# This may break in the future, but is worth it for performance
sub _readable { !!(IO::Poll::_poll(@_[0, 1], my $m = POLLIN | POLLPRI) > 0) }

sub _round { $_[0] < 10 ? int($_[0] * 10 + 0.5) / 10 : int($_[0] + 0.5) }

sub _stash {
  my ($name, $object) = (shift, shift);

  # Hash
  return $object->{$name} ||= {} unless @_;

  # Get
  return $object->{$name}{$_[0]} unless @_ > 1 || ref $_[0];

  # Set
  my $values = ref $_[0] ? $_[0] : {@_};
  @{$object->{$name}}{keys %$values} = values %$values;

  return $object;
}

sub _teardown {
  return unless my $class = shift;

  # @ISA has to be cleared first because of circular references
  no strict 'refs';
  @{"${class}::ISA"} = ();
  delete_package $class;
}

package Mojo::Util::_Guard;
use Mojo::Base -base;

sub DESTROY { shift->{cb}() }

1;

=encoding utf8

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

L<Mojo::Util> implements the following functions, which can be imported individually.

=head2 b64_decode

  my $bytes = b64_decode $b64;

Base64 decode bytes with L<MIME::Base64>.

=head2 b64_encode

  my $b64 = b64_encode $bytes;
  my $b64 = b64_encode $bytes, "\n";

Base64 encode bytes with L<MIME::Base64>, the line ending defaults to a newline.

=head2 camelize

  my $camelcase = camelize $snakecase;

Convert C<snake_case> string to C<CamelCase> and replace C<-> with C<::>.

  # "FooBar"
  camelize 'foo_bar';

  # "FooBar::Baz"
  camelize 'foo_bar-baz';

  # "FooBar::Baz"
  camelize 'FooBar::Baz';

=head2 class_to_file

  my $file = class_to_file 'Foo::Bar';

Convert a class name to a file.

  # "foo_bar"
  class_to_file 'Foo::Bar';

  # "foobar"
  class_to_file 'FOO::Bar';

  # "foo_bar"
  class_to_file 'FooBar';

  # "foobar"
  class_to_file 'FOOBar';

=head2 class_to_path

  my $path = class_to_path 'Foo::Bar';

Convert class name to path, as used by C<%INC>.

  # "Foo/Bar.pm"
  class_to_path 'Foo::Bar';

  # "FooBar.pm"
  class_to_path 'FooBar';

=head2 decamelize

  my $snakecase = decamelize $camelcase;

Convert C<CamelCase> string to C<snake_case> and replace C<::> with C<->.

  # "foo_bar"
  decamelize 'FooBar';

  # "foo_bar-baz"
  decamelize 'FooBar::Baz';

  # "foo_bar-baz"
  decamelize 'foo_bar-baz';

=head2 decode

  my $chars = decode 'UTF-8', $bytes;

Decode bytes to characters with L<Encode>, or return C<undef> if decoding failed.

=head2 deprecated

  deprecated 'foo is DEPRECATED in favor of bar';

Warn about deprecated feature from perspective of caller. You can also set the C<MOJO_FATAL_DEPRECATIONS> environment
variable to make them die instead with L<Carp>.

=head2 dumper

  my $perl = dumper {some => 'data'};

Dump a Perl data structure with L<Data::Dumper>.

=head2 encode

  my $bytes = encode 'UTF-8', $chars;

Encode characters to bytes with L<Encode>.

=head2 extract_usage

  my $usage = extract_usage;
  my $usage = extract_usage '/home/sri/foo.pod';

Extract usage message from the SYNOPSIS section of a file containing POD documentation, defaults to using the file this
function was called from.

  # "Usage: APPLICATION test [OPTIONS]\n"
  extract_usage;

  =head1 SYNOPSIS

    Usage: APPLICATION test [OPTIONS]

  =cut

=head2 getopt

  getopt
    'H|headers=s' => \my @headers,
    't|timeout=i' => \my $timeout,
    'v|verbose'   => \my $verbose;
  getopt $array,
    'H|headers=s' => \my @headers,
    't|timeout=i' => \my $timeout,
    'v|verbose'   => \my $verbose;
  getopt $array, ['pass_through'],
    'H|headers=s' => \my @headers,
    't|timeout=i' => \my $timeout,
    'v|verbose'   => \my $verbose;

Extract options from an array reference with L<Getopt::Long>, but without changing its global configuration, defaults
to using C<@ARGV>. The configuration options C<no_auto_abbrev> and C<no_ignore_case> are enabled by default.

  # Extract "charset" option
  getopt ['--charset', 'UTF-8'], 'charset=s' => \my $charset;
  say $charset;

=head2 gunzip

  my $uncompressed = gunzip $compressed;

Uncompress bytes with L<IO::Compress::Gunzip>.

=head2 gzip

  my $compressed = gzip $uncompressed;

Compress bytes with L<IO::Compress::Gzip>.

=head2 hmac_sha1_sum

  my $checksum = hmac_sha1_sum $bytes, 'passw0rd';

Generate HMAC-SHA1 checksum for bytes with L<Digest::SHA>.

  # "11cedfd5ec11adc0ec234466d8a0f2a83736aa68"
  hmac_sha1_sum 'foo', 'passw0rd';

=head2 html_attr_unescape

  my $str = html_attr_unescape $escaped;

Same as L</"html_unescape">, but handles special rules from the L<HTML Living Standard|https://html.spec.whatwg.org>
for HTML attributes.

  # "foo=bar&ltest=baz"
  html_attr_unescape 'foo=bar&ltest=baz';

  # "foo=bar<est=baz"
  html_attr_unescape 'foo=bar&lt;est=baz';

=head2 html_unescape

  my $str = html_unescape $escaped;

Unescape all HTML entities in string.

  # "<div>"
  html_unescape '&lt;div&gt;';

=head2 humanize_bytes

  my $str = humanize_bytes 1234;

Turn number of bytes into a simplified human readable format. Note that this function is B<EXPERIMENTAL> and might
change without warning!

  # "1B"
  humanize_bytes 1;

  # "7.5GiB"
  humanize_bytes 8007188480;

  # "13GiB"
  humanize_bytes 13443399680;

  # "-685MiB"
  humanize_bytes -717946880;

=head2 md5_bytes

  my $checksum = md5_bytes $bytes;

Generate binary MD5 checksum for bytes with L<Digest::MD5>.

=head2 md5_sum

  my $checksum = md5_sum $bytes;

Generate MD5 checksum for bytes with L<Digest::MD5>.

  # "acbd18db4cc2f85cedef654fccc4a4d8"
  md5_sum 'foo';

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

Punycode decode string as described in L<RFC 3492|http://tools.ietf.org/html/rfc3492>.

  # "bücher"
  punycode_decode 'bcher-kva';

=head2 punycode_encode

  my $punycode = punycode_encode $str;

Punycode encode string as described in L<RFC 3492|http://tools.ietf.org/html/rfc3492>.

  # "bcher-kva"
  punycode_encode 'bücher';

=head2 quote

  my $quoted = quote $str;

Quote string.

=head2 scope_guard

  my $guard = scope_guard sub {...};

Create anonymous scope guard object that will execute the passed callback when the object is destroyed.

  # Execute closure at end of scope
  {
    my $guard = scope_guard sub { say "Mojo!" };
    say "Hello";
  }

=head2 secure_compare

  my $bool = secure_compare $str1, $str2;

Constant time comparison algorithm to prevent timing attacks.

=head2 sha1_bytes

  my $checksum = sha1_bytes $bytes;

Generate binary SHA1 checksum for bytes with L<Digest::SHA>.

=head2 sha1_sum

  my $checksum = sha1_sum $bytes;

Generate SHA1 checksum for bytes with L<Digest::SHA>.

  # "0beec7b5ea3f0fdbc95d0dd47f3c5bc275da8a33"
  sha1_sum 'foo';

=head2 slugify

  my $slug = slugify $string;
  my $slug = slugify $string, $bool;

Returns a URL slug generated from the input string. Non-word characters are removed, the string is trimmed and
lowercased, and whitespace characters are replaced by a dash. By default, non-ASCII characters are normalized to ASCII
word characters or removed, but if a true value is passed as the second parameter, all word characters will be allowed
in the result according to unicode semantics.

  # "joel-is-a-slug"
  slugify 'Joel is a slug';

  # "this-is-my-resume"
  slugify 'This is: my - résumé! ☃ ';

  # "this-is-my-résumé"
  slugify 'This is: my - résumé! ☃ ', 1;

=head2 split_cookie_header

  my $tree = split_cookie_header 'a=b; expires=Thu, 07 Aug 2008 07:07:59 GMT';

Same as L</"split_header">, but handles C<expires> values from L<RFC 6265|http://tools.ietf.org/html/rfc6265>.

=head2 split_header

   my $tree = split_header 'foo="bar baz"; test=123, yada';

Split HTTP header value into key/value pairs, each comma separated part gets its own array reference, and keys without
a value get C<undef> assigned.

  # "one"
  split_header('one; two="three four", five=six')->[0][0];

  # "two"
  split_header('one; two="three four", five=six')->[0][2];

  # "three four"
  split_header('one; two="three four", five=six')->[0][3];

  # "five"
  split_header('one; two="three four", five=six')->[1][0];

  # "six"
  split_header('one; two="three four", five=six')->[1][1];

=head2 steady_time

  my $time = steady_time;

High resolution time elapsed from an arbitrary fixed point in the past, resilient to time jumps if a monotonic clock is
available through L<Time::HiRes>.

=head2 tablify

  my $table = tablify [['foo', 'bar'], ['baz', 'yada']];

Row-oriented generator for text tables.

  # "foo   bar\nyada  yada\nbaz   yada\n"
  tablify [['foo', 'bar'], ['yada', 'yada'], ['baz', 'yada']];

=head2 term_escape

  my $escaped = term_escape $str;

Escape all POSIX control characters except for C<\n>.

  # "foo\\x09bar\\x0d\n"
  term_escape "foo\tbar\r\n";

=head2 trim

  my $trimmed = trim $str;

Trim whitespace characters from both ends of string.

  # "foo bar"
  trim '  foo bar  ';

=head2 unindent

  my $unindented = unindent $str;

Unindent multi-line string.

  # "foo\nbar\nbaz\n"
  unindent "  foo\n  bar\n  baz\n";

=head2 unquote

  my $str = unquote $quoted;

Unquote string.

=head2 url_escape

  my $escaped = url_escape $str;
  my $escaped = url_escape $str, '^A-Za-z0-9\-._~';

Percent encode unsafe characters in string as described in L<RFC 3986|http://tools.ietf.org/html/rfc3986>, the pattern
used defaults to C<^A-Za-z0-9\-._~>.

  # "foo%3Bbar"
  url_escape 'foo;bar';

=head2 url_unescape

  my $str = url_unescape $escaped;

Decode percent encoded characters in string as described in L<RFC 3986|http://tools.ietf.org/html/rfc3986>.

  # "foo;bar"
  url_unescape 'foo%3Bbar';

=head2 xml_escape

  my $escaped = xml_escape $str;

Escape unsafe characters C<&>, C<E<lt>>, C<E<gt>>, C<"> and C<'> in string, but do not escape L<Mojo::ByteStream>
objects.

  # "&lt;div&gt;"
  xml_escape '<div>';

  # "<div>"
  use Mojo::ByteStream qw(b);
  xml_escape b('<div>');

=head2 xor_encode

  my $encoded = xor_encode $str, $key;

XOR encode string with variable length key.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
