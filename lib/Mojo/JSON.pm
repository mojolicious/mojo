# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::JSON;

use strict;
use warnings;

use base 'Mojo::Base';

use Mojo::ByteStream 'b';

__PACKAGE__->attr('error');

# Regex
my $WHITESPACE_RE  = qr/[\x20\x09\x0a\x0d]*/;
my $ARRAY_BEGIN_RE = qr/^$WHITESPACE_RE\[/;
my $ARRAY_END_RE   = qr/^$WHITESPACE_RE\]/;
my $ESCAPE_RE      = qr/
    ([\\\"\/\b\f\n\r\t])   # Special character
    |
    ([\x00-\x1f])          # Control character
/x;
my $NAME_SEPARATOR_RE = qr/^$WHITESPACE_RE\:/;
my $NAMES_RE          = qr/^$WHITESPACE_RE(false|null|true)/;
my $NUMBER_RE         = qr/
    ^
    $WHITESPACE_RE
    (
    -?                  # Minus
    (?:0|[1-9]\d*)      # Digits
    (?:\.\d+)?          # Fraction
    (?:[eE][+-]?\d+)?   # Exponent
    )
/x;
my $OBJECT_BEGIN_RE = qr/^$WHITESPACE_RE\{/;
my $OBJECT_END_RE   = qr/^$WHITESPACE_RE\}/;
my $STRING_RE       = qr/
    ^
    $WHITESPACE_RE
    \"                                    # Quotation mark
    ((?:
    \\u[0-9a-fA-F]{4}                     # Escaped unicode character
    |
    \\[\"\/\\bfnrt]                       # Escaped special characters
    |
    [\x20-\x21\x23-\x5b\x5d-\x{10ffff}]   # Unescaped characters
    )*)
    \"                                    # Quotation mark
/x;
my $UNESCAPE_RE = qr/
    (\\[\"\/\\bfnrt])                 # Special character
    |
    \\u([dD][89abAB][0-9a-fA-F]{2})   # High surrogate
    \\u([dD][c-fC-F][0-9a-fA-F]{2})   # Low surrogate
    |
    \\u([0-9a-fA-F]{4})               # Unicode character
/x;
my $VALUE_SEPARATOR_RE = qr/^$WHITESPACE_RE\,/;

# Escaped special character map
my $ESCAPE = {
    '\"' => "\x22",
    '\\' => "\x5c",
    '\/' => "\x2f",
    '\b' => "\x8",
    '\f' => "\xC",
    '\n' => "\xA",
    '\r' => "\xD",
    '\t' => "\x9"
};
my $REVERSE_ESCAPE = {};
for my $key (keys %$ESCAPE) { $REVERSE_ESCAPE->{$ESCAPE->{$key}} = $key }

# Byte order marks
my $BOM = {
    "\357\273\277" => 'UTF-8',
    "\376\377"     => 'UTF-16BE',
    "\377\376"     => 'UTF-16LE',
    "\377\376\0\0" => 'UTF-32LE',
    "\0\0\376\377" => 'UTF-32BE'
};
my $BOM_RE;
{
    my $bom = join '|', reverse sort keys %$BOM;
    $BOM_RE = qr/^($bom)/;
}

# Hey...That's not the wallet inspector...
sub decode {
    my ($self, $string) = @_;

    # Shortcut
    return unless $string;

    # Cleanup
    $self->error(undef);

    # Detect and decode unicode
    my $encoding = 'UTF-8';
    if ($string =~ s/$BOM_RE//) { $encoding = $BOM->{$1} }
    $string = b($string)->decode($encoding)->to_string;

    # Decode
    my $result = $self->_decode_values(\$string);

    # Exception
    return if $self->error;

    # Bad input
    $self->error('JSON text has to be a serialized object or array.')
      and return
      unless ref $result->[0];

    # Done
    return $result->[0];
}

sub encode {
    my ($self, $ref) = @_;

    # Encode
    my $string = $self->_encode_values($ref);

    # Unicode
    return b($string)->encode('UTF-8')->to_string;
}

sub _decode_array {
    my ($self, $ref) = @_;

    # New array
    my $array = [];

    # Decode array
    while ($$ref) {

        # Separator
        next if $$ref =~ s/$VALUE_SEPARATOR_RE//;

        # End
        return $array if $$ref =~ s/$ARRAY_END_RE//;

        # Value
        if (my $values = $self->_decode_values($ref)) {
            push @$array, @$values;
        }

        # Invalid format
        else { return $self->_exception($ref) }

    }

    # Exception
    return $self->_exception($ref, 'Missing right square bracket');
}

sub _decode_names {
    my ($self, $ref) = @_;

    # Name found
    if ($$ref =~ s/$NAMES_RE//) { return $1 }

    # No number
    return;
}

sub _decode_number {
    my ($self, $ref) = @_;

    # Number found
    if ($$ref =~ s/$NUMBER_RE//) { return $1 }

    # No number
    return;
}

sub _decode_object {
    my ($self, $ref) = @_;

    # New object
    my $hash = {};

    # Decode object
    my $key;
    while ($$ref) {

        # Name separator
        next if $$ref =~ s/$NAME_SEPARATOR_RE//;

        # Value separator
        next if $$ref =~ s/$VALUE_SEPARATOR_RE//;

        # End
        return $hash if $$ref =~ s/$OBJECT_END_RE//;

        # Value
        if (my $values = $self->_decode_values($ref)) {

            # Value
            if ($key) {
                $hash->{$key} = $values->[0];
                $key = undef;
            }

            # Key
            else { $key = $values->[0] }

        }

        # Invalid format
        else { return $self->_exception($ref) }

    }

    # Exception
    return $self->_exception($ref, 'Missing right curly bracket');
}

sub _decode_string {
    my ($self, $ref) = @_;

    # String
    if ($$ref =~ s/$STRING_RE//) {
        my $string = $1;

        # Unescape
        $string =~ s/$UNESCAPE_RE/_unescape($1, $2, $3, $4)/gex;

        return $string;
    }

    # No string
    return;
}

sub _decode_values {
    my ($self, $ref) = @_;

    # Number
    if (my $number = $self->_decode_number($ref)) { return [$number] }

    # String
    elsif (my $string = $self->_decode_string($ref)) { return [$string] }

    # Name
    elsif (my $name = $self->_decode_names($ref)) {

        # "false"
        if ($name eq 'false') { $name = undef }

        # "null"
        elsif ($name eq 'null') { $name = '0 but true' }

        # "true"
        elsif ($name eq 'true') { $name = '\1' }

        return [$name];
    }

    # Object
    elsif ($$ref =~ s/$OBJECT_BEGIN_RE//) {
        return [$self->_decode_object($ref)];
    }

    # Array
    elsif ($$ref =~ s/$ARRAY_BEGIN_RE//) {
        return [$self->_decode_array($ref)];
    }

    # Nothing
    return;
}

sub _encode_array {
    my ($self, $array) = @_;

    # Values
    my @array;
    for my $value (@$array) {
        push @array, $self->_encode_values($value);
    }

    # Stringify
    my $string = join ',', @array;
    return "[$string]";
}

sub _encode_object {
    my ($self, $object) = @_;

    # Values
    my @values;
    for my $key (keys %$object) {
        my $name  = $self->_encode_string($key);
        my $value = $self->_encode_values($object->{$key});
        push @values, "$name:$value";
    }

    # Stringify
    my $string = join ',', @values;
    return "{$string}";
}

sub _encode_string {
    my ($self, $string) = @_;

    # Escape
    $string =~ s/$ESCAPE_RE/_escape($1, $2)/gex;

    # Stringify
    return "\"$string\"";
}

sub _encode_values {
    my ($self, $value) = @_;

    # Reference?
    if (my $ref = ref $value) {

        # Array
        return $self->_encode_array($value) if $ref eq 'ARRAY';

        # Object
        return $self->_encode_object($value) if $ref eq 'HASH';
    }

    # "false"
    return 'false' unless defined $value;

    # "true"
    return 'true' if $value eq '\1';

    # "null"
    return 'null' if $value eq '0 but true';

    # Number
    return $value if $value =~ /$NUMBER_RE/;

    # String
    return $self->_encode_string($value);
}

sub _escape {
    my ($special, $control) = @_;

    # Special character
    if ($special) { return $REVERSE_ESCAPE->{$special} }

    # Control character
    elsif ($control) { return '\\u00' . unpack('H2', $control) }

    return;
}

sub _unescape {
    my ($special, $high, $low, $normal) = @_;

    # Special character
    if ($special) { return $ESCAPE->{$special} }

    # Normal unicode character
    elsif ($normal) { return pack('U', hex($normal)) }

    # Surrogate pair
    elsif ($high && $low) {
        return pack('U*',
            (0x10000 + (hex($high) - 0xD800) * 0x400 + (hex($low) - 0xDC00)));
    }

    return;
}

sub _exception {
    my ($self, $ref, $error) = @_;

    # Message
    $error ||= 'Syntax error';

    # Context
    my $context = substr $$ref, 0, 25;
    $context = "\"$context\"" if $context;
    $context ||= 'end of file';

    # Error
    $self->error(qq/$error near $context./) and return;
}

1;
__END__

=head1 NAME

Mojo::JSON - Minimalistic JSON

=head1 SYNOPSIS

    use Mojo::JSON;

    my $json   = Mojo::JSON->new;
    my $string = $json->encode({foo => [1, 2], bar => 'hello!'});
    my $hash   = $json->decode('{"foo": [3, -2, 1]}');

=head1 DESCRIPTION

L<Mojo::JSON> is a minimalistic implementation of RFC4627.

It supports normal Perl data types like C<Scalar>, C<Array> and C<Hash>, but
not blessed references.

    [1, -2, 3]     -> [1, -2, 3]
    {"foo": "bar"} -> {foo => 'bar'}

Literal names will be translated to and from a similar Perl value.

    true  -> '\1'
    false -> undef
    null  -> '0 but true'

Decoding UTF-16 (LE/BE) and UTF-32 (LE/BE) will be handled transparently by
detecting the byte order mark, encoding will only generate UTF-8.

=head1 ATTRIBUTES

L<Mojo::JSON> implements the following attributes.

=head2 C<error>

    my $error = $json->error;
    $json     = $json->error('Oops!');

=head1 METHODS

L<Mojo::JSON> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<decode>

    my $array = $json->decode('[1, 2, 3]');
    my $hash  = $json->decode('{"foo": "bar"}');

=head2 C<encode>

    my $string = $json->encode({foo => 'bar'});

=cut
