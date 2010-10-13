package Mojo::ByteStream;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

# These are core modules since 5.8, no need for pure-Perl implementations
# (even though they would be simple)
require Digest::MD5;
require Encode;
require MIME::Base64;
require MIME::QuotedPrint;

# Punycode bootstring parameters
use constant PUNYCODE_BASE         => 36;
use constant PUNYCODE_TMIN         => 1;
use constant PUNYCODE_TMAX         => 26;
use constant PUNYCODE_SKEW         => 38;
use constant PUNYCODE_DAMP         => 700;
use constant PUNYCODE_INITIAL_BIAS => 72;
use constant PUNYCODE_INITIAL_N    => 128;

# Core module since Perl 5.9.3
use constant SHA1 => eval 'use Digest::SHA (); 1';

# Punycode delimiter
my $DELIMITER = chr 0x2D;

# Encode cache
my %ENCODE;

# XHTML 1.0 entities for html_unescape (without "apos")
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

sub import {
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::b"} = sub {
        bless {
            bytestream => @_ < 2 ? defined $_[0] ? "$_[0]" : '' : join('', @_)
        }, 'Mojo::ByteStream';
      }
      if @_ > 1;
}

# Do we have any food that wasn't brutally slaughtered?
# Well, I think the veal died of loneliness.
sub new {
    my $self = shift->SUPER::new();
    $self->{bytestream} =
      @_ < 2 ? defined $_[0] ? "$_[0]" : '' : join('', @_);
    return $self;
}

sub add_chunk {
    my ($self, $chunk) = @_;

    # Shortcut
    return $self unless defined $chunk;

    # Raw length
    $self->{_raw_size} += length $chunk;

    # Store
    $self->{bytestream} .= $chunk;

    return $self;
}

sub b64_decode {
    my $self = shift;
    $self->{bytestream} = MIME::Base64::decode_base64($self->{bytestream});
    return $self;
}

sub b64_encode {
    my $self = shift;
    utf8::encode $self->{bytestream} if utf8::is_utf8 $self->{bytestream};
    $self->{bytestream} =
      MIME::Base64::encode_base64($self->{bytestream}, shift);
    return $self;
}

sub camelize {
    my $self = shift;

    my @parts;
    for my $part (split /-/, $self->{bytestream}) {

        # Junk
        next unless $part;

        # Split
        my @words = split /_/, $part;

        # Case
        @words = map {ucfirst} map {lc} @words;

        # Camelize
        push @parts, join '', @words;
    }
    $self->{bytestream} = join '::', @parts;

    return $self;
}

# The only monster here is the gambling monster that has enslaved your mother!
# I call him Gamblor, and it's time to snatch your mother from his neon claws!
sub clone {
    my $self = shift;
    return $self->new($self->{bytestream});
}

sub contains { index shift->{bytestream}, shift }

sub decamelize {
    my $self = shift;

    # Shortcut
    return $self if $self->{bytestream} !~ /^[A-Z\:]+/;

    my @parts;
    for my $part (split /\:\:/, $self->{bytestream}) {

        # Split
        my @words;
        push @words, $1 while ($part =~ s/([A-Z]{1}[^A-Z]*)//);

        # Case
        @words = map {lc} @words;

        # Join
        push @parts, join '_', @words;
    }
    $self->{bytestream} = join '-', @parts;

    return $self;
}

# I want to share something with you: The three little sentences that will
# get you through life.
# Number 1: "Cover for me."
# Number 2: "Oh, good idea, Boss!"
# Number 3: "It was like that when I got here."

sub decode {
    my ($self, $encoding) = @_;

    # Shortcut
    return $self unless $encoding;

    # Try decoding
    eval {

        # UTF-8
        if ($encoding eq 'UTF-8') {
            die unless utf8::decode $self->{bytestream};
        }

        # Everything else
        else {
            $self->{bytestream} =
              ($ENCODE{$encoding} ||= Encode::find_encoding($encoding))
              ->decode($self->{bytestream}, 1);
        }
    };

    # Failed
    $self->{bytestream} = undef if $@;

    return $self;
}

sub empty {
    my $self = shift;

    # Cleanup
    my $buffer = $self->{bytestream};
    $self->{bytestream} = '';

    return $buffer;
}

sub encode {
    my ($self, $encoding) = @_;

    # Shortcut
    return $self unless $encoding;

    # UTF-8
    if ($encoding eq 'UTF-8') { utf8::encode $self->{bytestream} }

    # Everything else
    else {
        $self->{bytestream} =
          ($ENCODE{$encoding} ||= Encode::find_encoding($encoding))
          ->encode($self->{bytestream});
    }
    return $self;
}

sub get_line {
    my $self = shift;

    # Locate line ending
    my $pos = index $self->{bytestream}, "\x0a";

    # No full line
    return if $pos == -1;

    # Extract line and ending
    my $line = substr $self->{bytestream}, 0, $pos + 1, '';
    $line =~ s/\x0d?\x0a$//;

    return $line;
}

sub hmac_md5_sum { shift->_hmac(\&_md5, @_) }

sub hmac_sha1_sum { shift->_hmac(\&_sha1, @_) }

sub html_escape {
    my $self = shift;

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

sub md5_bytes {
    my $self = shift;
    utf8::encode $self->{bytestream} if utf8::is_utf8 $self->{bytestream};
    $self->{bytestream} = _md5($self->{bytestream});
    return $self;
}

sub md5_sum {
    my $self = shift;
    utf8::encode $self->{bytestream} if utf8::is_utf8 $self->{bytestream};
    $self->{bytestream} = Digest::MD5::md5_hex($self->{bytestream});
    return $self;
}

sub punycode_decode {
    my $self = shift;

    # Input
    my $input = $self->{bytestream};

    # Defaults
    my $n    = PUNYCODE_INITIAL_N;
    my $i    = 0;
    my $bias = PUNYCODE_INITIAL_BIAS;
    my @output;

    # Delimiter
    if ($input =~ s/(.*)$DELIMITER//os) { push @output, split //, $1 }

    # Decode (direct translation of RFC 3492)
    while (length $input) {
        my $oldi = $i;
        my $w    = 1;

        # Base to infinity in steps of base
        for (my $k = PUNYCODE_BASE; 1; $k += PUNYCODE_BASE) {

            # Digit
            my $digit = ord substr $input, 0, 1, '';
            $digit =
              $digit < 0x40 ? $digit + (26 - 0x30) : ($digit & 0x1f) - 1;

            $i += $digit * $w;
            my $t = $k - $bias;
            $t =
                $t < PUNYCODE_TMIN ? PUNYCODE_TMIN
              : $t > PUNYCODE_TMAX ? PUNYCODE_TMAX
              :                      $t;

            # Break
            last if $digit < $t;

            $w *= (PUNYCODE_BASE - $t);
        }

        # Bias
        $bias = _adapt($i - $oldi, @output + 1, $oldi == 0);

        $n += $i / (@output + 1);
        $i = $i % (@output + 1);

        # Insert
        splice @output, $i, 0, chr($n);

        # Increment
        $i++;
    }

    # Output
    $self->{bytestream} = join '', @output;

    return $self;
}

sub punycode_encode {
    my $self = shift;

    # Input
    my $input  = $self->{bytestream};
    my $output = $input;
    my $length = length $input;

    # Remove non basic characters
    $output =~ s/[^\x00-\x7f]+//ogs;

    # Non basic characters in input
    my $h = my $b = length $output;
    $output .= $DELIMITER if $b > 0;

    # Split input
    my @input = map ord, split //, $input;
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
        for (my $i = 0; $i < $length; $i++) {
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

                    # Break
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

                # Reset delta
                $delta = 0;

                # Increment
                $h++;
            }
        }

        # Increment
        $delta++;
        $n++;
    }

    # Output
    $self->{bytestream} = $output;

    return $self;
}

# Old people don't need companionship.
# They need to be isolated and studied so it can be determined what nutrients
# they have that might be extracted for our personal use.
sub qp_decode {
    my $self = shift;
    $self->{bytestream} = MIME::QuotedPrint::decode_qp($self->{bytestream});
    return $self;
}

sub qp_encode {
    my $self = shift;
    utf8::encode $self->{bytestream} if utf8::is_utf8 $self->{bytestream};
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

sub raw_size { shift->{_raw_size} || 0 }

sub remove {
    my ($self, $length, $chunk) = @_;

    # Chunk to replace
    $chunk = '' unless defined $chunk;

    # Extract and replace
    return substr $self->{bytestream}, 0, $length, $chunk;
}

sub say {
    my ($self, $handle) = @_;
    $handle ||= \*STDOUT;
    utf8::encode $self->{bytestream} if utf8::is_utf8 $self->{bytestream};
    print $handle $self->{bytestream}, "\n";
}

sub sha1_bytes {
    my $self = shift;
    utf8::encode $self->{bytestream} if utf8::is_utf8 $self->{bytestream};
    $self->{bytestream} = _sha1($self->{bytestream});
    return $self;
}

sub sha1_sum {
    my $self = shift;
    die <<'EOF' unless SHA1;
Module "Digest::SHA" not present in this version of Perl.
Please install it manually or upgrade Perl to at least version 5.10.
EOF
    utf8::encode $self->{bytestream} if utf8::is_utf8 $self->{bytestream};
    $self->{bytestream} = Digest::SHA::sha1_hex($self->{bytestream});
    return $self;
}

sub size { length shift->{bytestream} }

sub to_string { shift->{bytestream} }

sub trim {
    my $self = shift;
    $self->{bytestream} =~ s/^\s*//;
    $self->{bytestream} =~ s/\s*$//;
    return $self;
}

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
    utf8::encode $self->{bytestream} if utf8::is_utf8 $self->{bytestream};
    return $self unless $self->{bytestream} =~ /[^$pattern]/;
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

    # Shortcut
    return $self if index($self->{bytestream}, '%') == -1;

    # Unescape
    $self->{bytestream} =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;

    return $self;
}

sub xml_escape {
    my $self = shift;

    # Replace "&", "<", ">", """ and "'"
    for ($self->{bytestream}) {
        s/&/&amp;/g;
        s/</&lt;/g;
        s/>/&gt;/g;
        s/"/&quot;/g;
        s/'/&#39;/g;
    }

    return $self;
}

# Helper for punycode
sub _adapt {
    my ($delta, $numpoints, $firsttime) = @_;

    # Delta
    $delta = $firsttime ? $delta / PUNYCODE_DAMP : $delta / 2;
    $delta += $delta / $numpoints;

    my $k = 0;
    while ($delta > ((PUNYCODE_BASE - PUNYCODE_TMIN) * PUNYCODE_TMAX) / 2) {
        $delta /= PUNYCODE_BASE - PUNYCODE_TMIN;
        $k += PUNYCODE_BASE;
    }

    return $k
      + ( ((PUNYCODE_BASE - PUNYCODE_TMIN + 1) * $delta)
        / ($delta + PUNYCODE_SKEW));
}

sub _hmac {
    my ($self, $cb, $secret) = @_;

    #Secret
    $secret ||= 'Very unsecure!';
    $secret = $cb->($secret) if length $secret > 64;

    # HMAC
    my $ipad = $secret ^ (chr(0x36) x 64);
    my $opad = $secret ^ (chr(0x5c) x 64);
    $self->{bytestream} = unpack 'H*',
      $cb->($opad . $cb->($ipad . $self->{bytestream}));

    return $self;
}

# Helper for md5_bytes
sub _md5 { Digest::MD5::md5(shift) }

# Helper for url_sanitize
sub _sanitize {
    my $hex = shift;

    my $char = hex $hex;
    return chr $char if $UNRESERVED{$char};

    return '%' . uc $hex;
}

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
    $stream->hmac_md5_sum('secret');
    $stream->hmac_sha1_sum('secret');
    $stream->html_escape;
    $stream->html_unescape;
    $stream->md5_bytes;
    $stream->md5_sum;
    $stream->qp_encode;
    $stream->qp_decode;
    $stream->quote;
    $stream->sha1_bytes;
    $stream->sha1_sum;
    $stream->trim;
    $stream->unquote;
    $stream->url_escape;
    $stream->url_sanitize;
    $stream->url_unescape;
    $stream->xml_escape;
    $stream->punycode_encode;
    $stream->punycode_decode;

    my $size = $stream->size;

    my $stream2 = $stream->clone;
    print $stream2->to_string;
    $stream2->say;

    # Chained
    my $stream = Mojo::ByteStream->new('foo bar baz')->quote;
    $stream = $stream->unquote->encode('UTF-8)->b64_encode;
    print "$stream";

    # Alternative constructor
    use Mojo::ByteStream 'b';
    my $stream = b('foobarbaz')->html_escape;

    # Buffering
    my $stream = Mojo::ByteStream->new;
    $stream->add_chunk('bar');
    my $foo = $stream->remove(3);
    my $bar = $stream->empty;

=head1 DESCRIPTION

L<Mojo::ByteStream> provides portable text and bytestream manipulation
functions.

=head1 METHODS

L<Mojo::ByteStream> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

    my $stream = Mojo::ByteStream->new($string);

Construct a new L<Mojo::ByteStream> object.

=head2 C<add_chunk>

    $stream = $stream->add_chunk('foo');

Add chunk of data to bytestream.

=head2 C<b64_decode>

    $stream = $stream->b64_decode;

Base 64 decode bytestream.

=head2 C<b64_encode>

    $stream = $stream->b64_encode;
    $stream = $stream->b64_encode('');

Base 64 encode bytestream.

=head2 C<camelize>

    $stream = $stream->camelize;

Camelize bytestream.

    foo_bar -> FooBar

=head2 C<clone>

    my $stream2 = $stream->clone;

Clone bytestream.

=head2 C<contains>

    my $position = $stream->contains('something');

Check if bytestream contains a specific string.

=head2 C<decamelize>

    $stream = $stream->decamelize;

Decamelize bytestream.

    FooBar -> foo_bar

=head2 C<decode>

    $stream = $stream->decode($encoding);

Decode bytestream.

    $stream->decode('UTF-8')->to_string;

=head2 C<empty>

    my $chunk = $stream->empty;

Empty bytestream.

=head2 C<encode>

    $stream = $stream->encode($encoding);

Encode bytestream.

    $stream->encode('UTF-8')->to_string;

=head2 C<get_line>

    my $line = $stream->get_line;

Extract a whole line from start of bytestream.
Lines are expected to end with C<0x0d 0x0a> or C<0x0a>.

=head2 C<hmac_md5_sum>

    $stream = $stream->hmac_md5_sum($secret);

Turn bytestream into HMAC-MD5 checksum of old content.

=head2 C<hmac_sha1_sum>

    $stream = $stream->hmac_sha1_sum($secret);

Turn bytestream into HMAC-SHA1 checksum of old content.
Note that Perl 5.10 or L<Digest::SHA> are required for C<SHA1> support.

=head2 C<html_escape>

    $stream = $stream->html_escape;

HTML escape bytestream.

=head2 C<html_unescape>

    $stream = $stream->html_unescape;

HTML unescape bytestream.

=head2 C<md5_bytes>

    $stream = $stream->md5_bytes;

Turn bytestream into binary MD5 checksum of old content.

=head2 C<md5_sum>

    $stream = $stream->md5_sum;

Turn bytestream into MD5 checksum of old content.

=head2 C<punycode_decode>

    $stream = $stream->punycode_decode;

Punycode decode bytestream, as described in RFC 3492.

=head2 C<punycode_encode>

    $stream = $stream->punycode_encode;

Punycode encode bytestream, as described in RFC 3492.

=head2 C<qp_decode>

    $stream = $stream->qp_decode;

Quoted Printable decode bytestream.

=head2 C<qp_encode>

    $stream = $stream->qp_encode;

Quoted Printable encode bytestream.

=head2 C<quote>

    $stream = $stream->quote;

Quote bytestream.

=head2 C<raw_size>

    my $size = $stream->raw_size;

Raw size of chunks added to bytestream in bytes.

=head2 C<remove>

    my $chunk = $stream->remove(4);
    my $chunk = $stream->remove(4, 'abcd');

Remove a specific number of bytes from bytestream.

=head2 C<say>

    $stream->say;
    $stream->say(*STDERR);

Print bytestream to handle or STDOUT and append a newline.

=head2 C<sha1_bytes>

    $stream = $stream->sha1_bytes;

Turn bytestream into binary SHA1 checksum of old content.
Note that Perl 5.10 or L<Digest::SHA> are required for C<SHA1> support.

=head2 C<sha1_sum>

    $stream = $stream->sha1_sum;

Turn bytestream into SHA1 checksum of old content.
Note that Perl 5.10 or L<Digest::SHA> are required for C<SHA1> support.

=head2 C<size>

    my $size = $stream->size;

Size of bytestream.

=head2 C<to_string>

    my $string = $stream->to_string;

Stringify bytestream.

=head2 C<trim>

    $stream = $stream->trim;

Trim whitespace characters from both ends of bytestream.

=head2 C<unquote>

    $stream = $stream->unquote;

Unquote bytestream.

=head2 C<url_escape>

    $stream = $stream->url_escape;
    $stream = $stream->url_escape('A-Za-z0-9\-\.\_\~');

URL escape bytestream.

=head2 C<url_sanitize>

    $stream = $stream->url_sanitize;

URL sanitize bytestream.

=head2 C<url_unescape>

    $stream = $stream->url_unescape;

URL unescape bytestream.

=head2 C<xml_escape>

    $stream = $stream->xml_escape;

XML escape bytestream, this is a much faster version of C<html_escape>
escaping only the characters C<&>, C<E<lt>>, C<E<gt>>, C<"> and C<'>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
