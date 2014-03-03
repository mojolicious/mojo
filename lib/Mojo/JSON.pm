package Mojo::JSON;
use Mojo::Base -base;

use B;
use Carp 'croak';
use Exporter 'import';
use Mojo::Util;
use Scalar::Util 'blessed';

has 'error';

our @EXPORT_OK = qw(decode_json encode_json j);

# Literal names
my $FALSE = bless \(my $false = 0), 'Mojo::JSON::_Bool';
my $TRUE  = bless \(my $true  = 1), 'Mojo::JSON::_Bool';

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

my $WHITESPACE_RE = qr/[\x20\x09\x0a\x0d]*/;

sub decode {
  my $self = shift->error(undef);
  my $value;
  return $value if eval { $value = _decode(shift); 1 };
  $self->error(_chomp($@));
  return undef;
}

sub decode_json {
  eval { _decode(shift) } // croak _chomp($@);
}

sub encode { encode_json($_[1]) }

sub encode_json { Mojo::Util::encode 'UTF-8', _encode_value(shift) }

sub false {$FALSE}

sub j {
  return encode_json($_[0]) if ref $_[0] eq 'ARRAY' || ref $_[0] eq 'HASH';
  return eval { _decode($_[0]) };
}

sub true {$TRUE}

sub _chomp { chomp $_[0] ? $_[0] : $_[0] }

sub _decode {

  # Missing input
  die "Missing or empty input\n" unless length(my $bytes = shift);

  # Wide characters
  die "Wide character in input\n" unless utf8::downgrade($bytes, 1);

  # UTF-8
  die "Input is not UTF-8 encoded\n"
    unless defined(local $_ = Mojo::Util::decode('UTF-8', $bytes));

  # Leading whitespace
  m/\G$WHITESPACE_RE/gc;

  # Value
  my $value = _decode_value();

  # Leftover data
  _exception('Unexpected data') unless m/\G$WHITESPACE_RE\z/gc;

  return $value;
}

sub _decode_array {
  my @array;
  until (m/\G$WHITESPACE_RE\]/gc) {

    # Value
    push @array, _decode_value();

    # Separator
    redo if m/\G$WHITESPACE_RE,/gc;

    # End
    last if m/\G$WHITESPACE_RE\]/gc;

    # Invalid character
    _exception('Expected comma or right square bracket while parsing array');
  }

  return \@array;
}

sub _decode_object {
  my %hash;
  until (m/\G$WHITESPACE_RE\}/gc) {

    # Quote
    m/\G$WHITESPACE_RE"/gc
      or _exception('Expected string while parsing object');

    # Key
    my $key = _decode_string();

    # Colon
    m/\G$WHITESPACE_RE:/gc
      or _exception('Expected colon while parsing object');

    # Value
    $hash{$key} = _decode_value();

    # Separator
    redo if m/\G$WHITESPACE_RE,/gc;

    # End
    last if m/\G$WHITESPACE_RE\}/gc;

    # Invalid character
    _exception('Expected comma or right curly bracket while parsing object');
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
    _exception('Unexpected character or invalid escape while parsing string')
      if m/\G[\x00-\x1f\\]/;
    _exception('Unterminated string');
  }

  # Unescape popular characters
  if (index($str, '\\u') < 0) {
    $str =~ s!\\(["\\/bfnrt])!$ESCAPE{$1}!gs;
    return $str;
  }

  # Unescape everything else
  my $buffer = '';
  while ($str =~ m/\G([^\\]*)\\(?:([^u])|u(.{4}))/gc) {
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
          or pos($_) = $pos + pos($str), _exception('Missing high-surrogate');

        # Low surrogate
        $str =~ m/\G\\u([Dd][C-Fc-f]..)/gc
          or pos($_) = $pos + pos($str), _exception('Missing low-surrogate');

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
  m/\G$WHITESPACE_RE/gc;

  # String
  return _decode_string() if m/\G"/gc;

  # Array
  return _decode_array() if m/\G\[/gc;

  # Object
  return _decode_object() if m/\G\{/gc;

  # Number
  return 0 + $1
    if m/\G([-]?(?:0|[1-9][0-9]*)(?:\.[0-9]*)?(?:[eE][+-]?[0-9]+)?)/gc;

  # True
  return $TRUE if m/\Gtrue/gc;

  # False
  return $FALSE if m/\Gfalse/gc;

  # Null
  return undef if m/\Gnull/gc;

  # Invalid character
  _exception('Expected string, array, object, number, boolean or null');
}

sub _encode_array {
  my $array = shift;
  return '[' . join(',', map { _encode_value($_) } @$array) . ']';
}

sub _encode_object {
  my $object = shift;
  my @pairs = map { _encode_string($_) . ':' . _encode_value($object->{$_}) }
    keys %$object;
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

    # Array
    return _encode_array($value) if $ref eq 'ARRAY';

    # Object
    return _encode_object($value) if $ref eq 'HASH';

    # True or false
    return $$value ? 'true' : 'false' if $ref eq 'SCALAR';
    return $value  ? 'true' : 'false' if $ref eq 'Mojo::JSON::_Bool';

    # Blessed reference with TO_JSON method
    if (blessed $value && (my $sub = $value->can('TO_JSON'))) {
      return _encode_value($value->$sub);
    }
  }

  # Null
  return 'null' unless defined $value;

  # Number
  my $flags = B::svref_2object(\$value)->FLAGS;
  return 0 + $value if $flags & (B::SVp_IOK | B::SVp_NOK) && $value * 0 == 0;

  # String
  return _encode_string($value);
}

sub _exception {

  # Leading whitespace
  m/\G$WHITESPACE_RE/gc;

  # Context
  my $context = 'Malformed JSON: ' . shift;
  if (m/\G\z/gc) { $context .= ' before end of data' }
  else {
    my @lines = split "\n", substr($_, 0, pos);
    $context .= ' at line ' . @lines . ', offset ' . length(pop @lines || '');
  }

  die "$context\n";
}

# Emulate boolean type
package Mojo::JSON::_Bool;
use overload '0+' => sub { ${$_[0]} }, '""' => sub { ${$_[0]} }, fallback => 1;

1;

=encoding utf8

=head1 NAME

Mojo::JSON - Minimalistic JSON

=head1 SYNOPSIS

  use Mojo::JSON qw(decode_json encode_json);

  # Encode and decode JSON (die on errors)
  my $bytes = encode_json({foo => [1, 2], bar => 'hello!', baz => \1});
  my $hash  = decode_json($bytes);

  # Handle errors
  my $json = Mojo::JSON->new;
  if (defined(my $hash = $json->decode($bytes))) { say $hash->{message} }
  elsif (my $err = $json->error) { say "Error: $err" }

=head1 DESCRIPTION

L<Mojo::JSON> is a minimalistic and possibly the fastest pure-Perl
implementation of L<RFC 7159|http://tools.ietf.org/html/rfc7159>.

It supports normal Perl data types like C<Scalar>, C<Array> reference, C<Hash>
reference and will try to call the C<TO_JSON> method on blessed references, or
stringify them if it doesn't exist. Differentiating between strings and
numbers in Perl is hard, depending on how it has been used, a C<Scalar> can be
both at the same time. Since numeric comparisons on strings are very unlikely
to happen intentionally, the numeric value always gets priority, so any
C<Scalar> that has been used in numeric context is considered a number.

  [1, -2, 3]     -> [1, -2, 3]
  {"foo": "bar"} -> {foo => 'bar'}

Literal names will be translated to and from L<Mojo::JSON> constants or a
similar native Perl value.

  true  -> Mojo::JSON->true
  false -> Mojo::JSON->false
  null  -> undef

In addition C<Scalar> references will be used to generate booleans, based on
if their values are true or false.

  \1 -> true
  \0 -> false

The two Unicode whitespace characters C<u2028> and C<u2029> will always be
escaped to make JSONP easier.

=head1 FUNCTIONS

L<Mojo::JSON> implements the following functions, which can be imported
individually.

=head2 decode_json

  my $value = decode_json($bytes);

Decode JSON to Perl value and die if decoding fails.

=head2 encode_json

  my $bytes = encode_json({foo => 'bar'});

Encode Perl value to JSON.

=head2 j

  my $bytes = j([1, 2, 3]);
  my $bytes = j({foo => 'bar'});
  my $value = j($bytes);

Encode Perl data structure, which may only be an C<Array> reference or C<Hash>
reference, to JSON or decode JSON and return C<undef> if decoding fails.

=head1 ATTRIBUTES

L<Mojo::JSON> implements the following attributes.

=head2 error

  my $err = $json->error;
  $json   = $json->error('Parser error');

Parser errors.

=head1 METHODS

L<Mojo::JSON> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 decode

  my $value = $json->decode($bytes);

Decode JSON to Perl value and return C<undef> if decoding fails.

=head2 encode

  my $bytes = $json->encode({foo => 'bar'});

Encode Perl value to JSON.

=head2 false

  my $false = Mojo::JSON->false;
  my $false = $json->false;

False value, used because Perl has no native equivalent.

=head2 true

  my $true = Mojo::JSON->true;
  my $true = $json->true;

True value, used because Perl has no native equivalent.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
