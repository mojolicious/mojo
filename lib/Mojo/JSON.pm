package Mojo::JSON;
use Mojo::Base -strict;

use Carp 'croak';
use Exporter 'import';
use JSON::PP ();
use Mojo::Util;
use Scalar::Util 'blessed';

our @EXPORT_OK = qw(decode_json encode_json false from_json j to_json true);

# Escaped special character map (with u2028 and u2029)
my %ESCAPE = (
  '"'     => '"',
  '\\'    => '\\',
  '/'     => '/',
  'b'     => "\x08",
  'f'     => "\x0c",
  'n'     => "\x0a",
  'r'     => "\x0d",
  't'     => "\x09",
  'u2028' => "\x{2028}",
  'u2029' => "\x{2029}"
);
my %REVERSE = map { $ESCAPE{$_} => "\\$_" } keys %ESCAPE;
for (0x00 .. 0x1f) { $REVERSE{pack 'C', $_} //= sprintf '\u%.4X', $_ }

sub decode_json {
  my $err = _decode(\my $value, shift);
  return defined $err ? croak $err : $value;
}

sub encode_json { Mojo::Util::encode 'UTF-8', _encode_value(shift) }

sub false () {JSON::PP::false}

sub from_json {
  my $err = _decode(\my $value, shift, 1);
  return defined $err ? croak $err : $value;
}

sub j {
  return encode_json($_[0]) if ref $_[0] eq 'ARRAY' || ref $_[0] eq 'HASH';
  return eval { decode_json($_[0]) };
}

sub to_json { _encode_value(shift) }

sub true () {JSON::PP::true}

sub _decode {
  my $valueref = shift;

  eval {

    # Missing input
    die "Missing or empty input\n" unless length(local $_ = shift);

    # UTF-8
    $_ = Mojo::Util::decode 'UTF-8', $_ unless shift;
    die "Input is not UTF-8 encoded\n" unless defined;

    # Value
    $$valueref = _decode_value();

    # Leftover data
    /\G[\x20\x09\x0a\x0d]*\z/gc or _throw('Unexpected data');
  } ? return undef : chomp $@;

  return $@;
}

sub _decode_array {
  my @array;
  until (m/\G[\x20\x09\x0a\x0d]*\]/gc) {

    # Value
    push @array, _decode_value();

    # Separator
    redo if /\G[\x20\x09\x0a\x0d]*,/gc;

    # End
    last if /\G[\x20\x09\x0a\x0d]*\]/gc;

    # Invalid character
    _throw('Expected comma or right square bracket while parsing array');
  }

  return \@array;
}

sub _decode_object {
  my %hash;
  until (m/\G[\x20\x09\x0a\x0d]*\}/gc) {

    # Quote
    /\G[\x20\x09\x0a\x0d]*"/gc
      or _throw('Expected string while parsing object');

    # Key
    my $key = _decode_string();

    # Colon
    /\G[\x20\x09\x0a\x0d]*:/gc or _throw('Expected colon while parsing object');

    # Value
    $hash{$key} = _decode_value();

    # Separator
    redo if /\G[\x20\x09\x0a\x0d]*,/gc;

    # End
    last if /\G[\x20\x09\x0a\x0d]*\}/gc;

    # Invalid character
    _throw('Expected comma or right curly bracket while parsing object');
  }

  return \%hash;
}

sub _decode_string {
  my $pos = pos;

  # Extract string with escaped characters
  m!\G((?:(?:[^\x00-\x1f\\"]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4})){0,32766})*)!gc;
  my $str = $1;

  # Invalid character
  unless (m/\G"/gc) {
    _throw('Unexpected character or invalid escape while parsing string')
      if /\G[\x00-\x1f\\]/;
    _throw('Unterminated string');
  }

  # Unescape popular characters
  if (index($str, '\\u') < 0) {
    $str =~ s!\\(["\\/bfnrt])!$ESCAPE{$1}!gs;
    return $str;
  }

  # Unescape everything else
  my $buffer = '';
  while ($str =~ /\G([^\\]*)\\(?:([^u])|u(.{4}))/gc) {
    $buffer .= $1;

    # Popular character
    if ($2) { $buffer .= $ESCAPE{$2} }

    # Escaped
    else {
      my $ord = hex $3;

      # Surrogate pair
      if (($ord & 0xf800) == 0xd800) {

        # High surrogate
        ($ord & 0xfc00) == 0xd800
          or pos = $pos + pos($str), _throw('Missing high-surrogate');

        # Low surrogate
        $str =~ /\G\\u([Dd][C-Fc-f]..)/gc
          or pos = $pos + pos($str), _throw('Missing low-surrogate');

        $ord = 0x10000 + ($ord - 0xd800) * 0x400 + (hex($1) - 0xdc00);
      }

      # Character
      $buffer .= pack 'U', $ord;
    }
  }

  # The rest
  return $buffer . substr $str, pos($str), length($str);
}

sub _decode_value {

  # Leading whitespace
  /\G[\x20\x09\x0a\x0d]*/gc;

  # String
  return _decode_string() if /\G"/gc;

  # Object
  return _decode_object() if /\G\{/gc;

  # Array
  return _decode_array() if /\G\[/gc;

  # Number
  return 0 + $1
    if /\G([-]?(?:0|[1-9][0-9]*)(?:\.[0-9]*)?(?:[eE][+-]?[0-9]+)?)/gc;

  # True
  return true() if /\Gtrue/gc;

  # False
  return false() if /\Gfalse/gc;

  # Null
  return undef if /\Gnull/gc;

  # Invalid character
  _throw('Expected string, array, object, number, boolean or null');
}

sub _encode_array {
  '[' . join(',', map { _encode_value($_) } @{$_[0]}) . ']';
}

sub _encode_object {
  my $object = shift;
  my @pairs = map { _encode_string($_) . ':' . _encode_value($object->{$_}) }
    sort keys %$object;
  return '{' . join(',', @pairs) . '}';
}

sub _encode_string {
  my $str = shift;
  $str =~ s!([\x00-\x1f\x{2028}\x{2029}\\"/])!$REVERSE{$1}!gs;
  return "\"$str\"";
}

sub _encode_value {
  my $value = shift;

  # Reference
  if (my $ref = ref $value) {

    # Object
    return _encode_object($value) if $ref eq 'HASH';

    # Array
    return _encode_array($value) if $ref eq 'ARRAY';

    # True or false
    return $$value ? 'true' : 'false' if $ref eq 'SCALAR';
    return $value  ? 'true' : 'false' if $ref eq 'JSON::PP::Boolean';

    # Everything else
    return _encode_string($value)
      unless blessed $value && (my $sub = $value->can('TO_JSON'));
    return _encode_value($value->$sub);
  }

  # Null
  return 'null' unless defined $value;

  # Number
  no warnings 'numeric';
  return $value
    if length((my $dummy = '') & $value)
    && 0 + $value eq $value
    && $value * 0 == 0;

  # String
  return _encode_string($value);
}

sub _throw {

  # Leading whitespace
  /\G[\x20\x09\x0a\x0d]*/gc;

  # Context
  my $context = 'Malformed JSON: ' . shift;
  if (m/\G\z/gc) { $context .= ' before end of data' }
  else {
    my @lines = split "\n", substr($_, 0, pos);
    $context .= ' at line ' . @lines . ', offset ' . length(pop @lines || '');
  }

  die "$context\n";
}

1;

=encoding utf8

=head1 NAME

Mojo::JSON - Minimalistic JSON

=head1 SYNOPSIS

  use Mojo::JSON qw(decode_json encode_json);

  my $bytes = encode_json {foo => [1, 2], bar => 'hello!', baz => \1};
  my $hash  = decode_json $bytes;

=head1 DESCRIPTION

L<Mojo::JSON> is a minimalistic and possibly the fastest pure-Perl
implementation of L<RFC 7159|http://tools.ietf.org/html/rfc7159>.

It supports normal Perl data types like scalar, array reference, hash reference
and will try to call the C<TO_JSON> method on blessed references, or stringify
them if it doesn't exist. Differentiating between strings and numbers in Perl
is hard, depending on how it has been used, a scalar can be both at the same
time. The string value has a higher precedence unless both representations are
equivalent.

  [1, -2, 3]     -> [1, -2, 3]
  {"foo": "bar"} -> {foo => 'bar'}

Literal names will be translated to and from L<Mojo::JSON> constants or a
similar native Perl value.

  true  -> Mojo::JSON->true
  false -> Mojo::JSON->false
  null  -> undef

In addition scalar references will be used to generate booleans, based on if
their values are true or false.

  \1 -> true
  \0 -> false

The two Unicode whitespace characters C<u2028> and C<u2029> will always be
escaped to make JSONP easier, and the character C</> to prevent XSS attacks.

  "\x{2028}\x{2029}</script>" -> "\u2028\u2029<\/script>"

=head1 FUNCTIONS

L<Mojo::JSON> implements the following functions, which can be imported
individually.

=head2 decode_json

  my $value = decode_json $bytes;

Decode JSON to Perl value and die if decoding fails.

=head2 encode_json

  my $bytes = encode_json {i => '♥ mojolicious'};

Encode Perl value to JSON.

=head2 false

  my $false = false;

False value, used because Perl has no native equivalent.

=head2 from_json

  my $value = from_json $chars;

Decode JSON text that is not C<UTF-8> encoded to Perl value and die if decoding
fails.

=head2 j

  my $bytes = j [1, 2, 3];
  my $bytes = j {i => '♥ mojolicious'};
  my $value = j $bytes;

Encode Perl data structure (which may only be an array reference or hash
reference) or decode JSON, an C<undef> return value indicates a bare C<null> or
that decoding failed.

=head2 to_json

  my $chars = to_json {i => '♥ mojolicious'};

Encode Perl value to JSON text without C<UTF-8> encoding it.

=head2 true

  my $true = true;

True value, used because Perl has no native equivalent.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
