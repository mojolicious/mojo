# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::ByteStream;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;
use bytes;

# These are core modules since 5.8, no need for pure-Perl implementations
# (even though they would be simple)
require Digest::MD5;
require Encode;
require MIME::Base64;
require MIME::QuotedPrint;

# XHTML 1.0 entities for html_unescape
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
    apos     => 39,
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
my %REVERSE_ENTITIES;
while (my ($name, $value) = each %ENTITIES) {
    $REVERSE_ENTITIES{$value} = $name;
}

# Unreserved character map for url_sanitize
my %UNRESERVED;
{
    my @unreserved;

    # 0-9 and special unresereved chars
    push @unreserved, ord($_) for 0 .. 9, '-', '.', '_', '~';

    # A-Za-z
    push @unreserved, $_ for ord 'A' .. ord 'Z', ord 'a' .. ord 'z';

    $UNRESERVED{$_}++ for @unreserved;
}

# Do we have any food that wasn't brutally slaughtered?
# Well, I think the veal died of loneliness.
sub import {
    my ($class, $name) = @_;

    # Shortcut
    return unless $name;

    # Export
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::$name"} = sub { Mojo::ByteStream->new(@_) };
}

sub new {
    my $self = shift->SUPER::new();
    $self->{bytestream} = defined $_[0] ? $_[0] : '';
    return $self;
}

sub b64_decode {
    my $self = shift;
    $self->{bytestream} = MIME::Base64::decode_base64($self->{bytestream});
    return $self;
}

sub b64_encode {
    my $self = shift;
    $self->{bytestream} = MIME::Base64::encode_base64($self->{bytestream});
    return $self;
}

sub camelize {
    my $self = shift;

    # Split
    my @words = split /_/, $self->{bytestream};

    # Case
    @words = map {ucfirst} map {lc} @words;

    # Join
    $self->{bytestream} = join '', @words;

    return $self;
}

sub clone {
    my $self = shift;
    return $self->new($self->{bytestream});
}

sub decamelize {
    my $self = shift;

    # Shortcut
    return $self if $self->{bytestream} !~ /^[A-Z]+/;

    # Split
    my @words;
    push @words, $1 while ($self->{bytestream} =~ s/([A-Z]+[^A-Z]*)//);

    # Case
    @words = map {lc} @words;

    # Join
    $self->{bytestream} = join '_', @words;

    return $self;
}

sub decode {
    my ($self, $encoding) = @_;

    # Shortcut
    return $self unless $encoding;

    # Try decoding
    eval {
        $self->{bytestream} =
          Encode::decode($encoding, $self->{bytestream}, 1);
    };

    # Failed
    $self->{bytestream} = '' if $@;

    return $self;
}

sub encode {
    my ($self, $encoding) = @_;

    # Shortcut
    return $self unless $encoding;

    $self->{bytestream} = Encode::encode($encoding, $self->{bytestream});
    return $self;
}

sub html_escape {
    my $self = shift;

    # Character semantics
    no bytes;

    my $escaped = '';
    for (1 .. length $self->{bytestream}) {

        # Escape
        my $char = substr $self->{bytestream}, 0, 1, '';
        my $num = unpack 'U', $char;
        my $named = $REVERSE_ENTITIES{$num};
        $char = "&$named;" if $named;
        $escaped .= $char;
    }
    $self->{bytestream} = $escaped;

    return $self;
}

sub html_unescape {
    my $self = shift;

    # Unescape
    $self->{bytestream} =~ s/
        &(?:
            \#(\d{1,7})              # Number
        |
            ([A-Za-z]{1,8})          # Named
        |
            \#x([0-9A-Fa-f]{1,6}))   # Hex
        ;
    /_unescape($1, $2, $3)/gex;

    return $self;
}

sub md5_sum {
    my $self = shift;
    $self->{bytestream} = Digest::MD5::md5_hex($self->{bytestream});
    return $self;
}

sub qp_decode {
    my $self = shift;
    $self->{bytestream} = MIME::QuotedPrint::decode_qp($self->{bytestream});
    return $self;
}

sub qp_encode {
    my $self = shift;
    $self->{bytestream} = MIME::QuotedPrint::encode_qp($self->{bytestream});
    return $self;
}

sub quote {
    my $self = shift;

    # Escape
    $self->{bytestream} =~ s/([\"\\])/\\$1/g;
    $self->{bytestream} = '"' . $self->{bytestream} . '"';

    return $self;
}

sub size { length shift->{bytestream} }

sub to_string { shift->{bytestream} }

sub unquote {
    my $self = shift;

    # Not quoted
    return $self unless $self->{bytestream} =~ /^\".*\"$/g;

    # Unquote
    $self->{bytestream} =~ s/^\"//g;
    $self->{bytestream} =~ s/\"$//g;
    $self->{bytestream} =~ s/\\\\/\\/g;
    $self->{bytestream} =~ s/\\\"/\"/g;

    return $self;
}

sub url_escape {
    my $self = shift;

    # Default to unreserved characters
    my $pattern = shift || 'A-Za-z0-9\-\.\_\~';

    # Escape
    $self->{bytestream} =~ s/([^$pattern])/sprintf('%%%02X',ord($1))/ge;

    return $self;
}

sub url_sanitize {
    my $self = shift;

    # Uppercase hex values and unescape unreserved characters
    $self->{bytestream} =~ s/%([0-9A-Fa-f]{2})/_sanitize($1)/ge;

    return $self;
}

sub url_unescape {
    my $self = shift;

    # Unescape
    $self->{bytestream} =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;

    return $self;
}

sub xml_escape {
    my $self = shift;

    # Character semantics
    no bytes;

    # Replace "&", "<", ">", """ and "'"
    for ($self->{bytestream}) {
        s/&/&amp;/g;
        s/</&lt;/g;
        s/>/&gt;/g;
        s/"/&quot;/g;
        s/'/&apos;/g;
    }

    return $self;
}

# Helper for url_sanitize
sub _sanitize {
    my $hex = shift;

    my $char = hex $hex;
    return chr $char if $UNRESERVED{$char};

    return '%' . uc $hex;
}

# Helper for html_unescape
sub _unescape {
    my ($num, $entitie, $hex) = @_;

    # Named to number
    if (defined $entitie) { $num = $ENTITIES{$entitie} }

    # Hex to number
    elsif (defined $hex) { $num = hex $hex }

    # Number
    return pack 'U', $num if $num;

    # Unknown entitie
    return "&$entitie;";
}

1;
__END__

=head1 NAME

Mojo::ByteStream - ByteStream

=head1 SYNOPSIS

    use Mojo::ByteStream;

    my $stream = Mojo::ByteStream->new('foobarbaz');

    $stream->camelize;
    $stream->decamelize;
    $stream->b64_encode;
    $stream->b64_decode;
    $stream->encode('UTF-8');
    $stream->decode('UTF-8');
    $stream->html_escape;
    $stream->html_unescape;
    $stream->md5_sum;
    $stream->qp_encode;
    $stream->qp_decode;
    $stream->quote;
    $stream->unquote;
    $stream->url_escape;
    $stream->url_sanitize;
    $stream->url_unescape;
    $stream->xml_escape;

    my $size = $stream->size;

    my $stream2 = $stream->clone;
    print $stream2->to_string;

    # Chained
    my $stream = Mojo::ByteStream->new('foo bar baz')->quote;
    $stream = $stream->unquote->encode('UTF-8)->b64_encode;
    print "$stream";

    # Constructor alias
    use Mojo::ByteStream 'b';

    my $stream = b('foobarbaz')->html_escape;

=head1 DESCRIPTION

L<Mojo::ByteStream> provides portable text and bytestream manipulation
functions.

=head1 METHODS

L<Mojo::ByteStream> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

    my $stream = Mojo::ByteStream->new($string);

=head2 C<b64_decode>

    $stream = $stream->b64_decode;

=head2 C<b64_encode>

    $stream = $stream->b64_encode;

=head2 C<camelize>

    $stream = $stream->camelize;

=head2 C<clone>

    my $stream2 = $stream->clone;

=head2 C<decamelize>

    $stream = $stream->decamelize;

=head2 C<decode>

    $stream = $stream->decode($encoding);

=head2 C<encode>

    $stream = $stream->encode($encoding);

=head2 C<html_escape>

    $stream = $stream->html_escape;

=head2 C<html_unescape>

    $stream = $stream->html_unescape;

=head2 C<md5_sum>

    $stream = $stream->md5_sum;

=head2 C<qp_decode>

    $stream = $stream->qp_decode;

=head2 C<qp_encode>

    $stream = $stream->qp_encode;

=head2 C<quote>

    $stream = $stream->quote;

=head2 C<size>

    my $size = $stream->size;

=head2 C<to_string>

    my $string = $stream->to_string;

=head2 C<unquote>

    $stream = $stream->unquote;

=head2 C<url_escape>

    $stream = $stream->url_escape;
    $stream = $stream->url_escape('A-Za-z0-9\-\.\_\~');

=head2 C<url_sanitize>

    $stream = $stream->url_sanitize;

=head2 C<url_unescape>

    $stream = $stream->url_unescape;

=head2 C<xml_escape>

    $stream = $stream->xml_escape;

=cut
