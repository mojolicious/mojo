# Copyright (C) 2008, Sebastian Riedel.

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
sub new {
    my $self = shift->SUPER::new();
    $self->{bytestream} = $_[0] if defined $_[0];
    return $self;
}

sub b64_decode {
    my $self = shift;

    # Shortcut
    return $self unless defined $self->{bytestream};

    $self->{bytestream} = MIME::Base64::decode_base64($self->{bytestream});
    return $self;
}

sub b64_encode {
    my $self = shift;

    # Shortcut
    return $self unless defined $self->{bytestream};

    $self->{bytestream} = MIME::Base64::encode_base64($self->{bytestream});
    return $self;
}

sub camelize {
    my $self = shift;

    # Shortcut
    return $self unless defined $self->{bytestream};

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
    return $self
      if !defined $self->{bytestream}
          || $self->{bytestream} !~ /^[A-Z]+/;

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
    return $self unless defined $self->{bytestream};
    return $self unless $encoding;

    $self->{bytestream} = Encode::decode($encoding, $self->{bytestream});
    return $self;
}

sub encode {
    my ($self, $encoding) = @_;

    # Shortcut
    return $self unless defined $self->{bytestream};
    return $self unless $encoding;

    $self->{bytestream} = Encode::encode($encoding, $self->{bytestream});
    return $self;
}

sub length {
    my $self = shift;
    $self->{bytestream} = '' unless defined $self->{bytestream};
    return length $self->{bytestream};
}

sub md5_sum {
    my $self = shift;

    # Shortcut
    return $self unless defined $self->{bytestream};

    $self->{bytestream} = Digest::MD5::md5_hex($self->{bytestream});
    return $self;
}

sub qp_decode {
    my $self = shift;

    # Shortcut
    return $self unless defined $self->{bytestream};

    $self->{bytestream} = MIME::QuotedPrint::decode_qp($self->{bytestream});
    return $self;
}

sub qp_encode {
    my $self = shift;

    # Shortcut
    return $self unless defined $self->{bytestream};

    $self->{bytestream} = MIME::QuotedPrint::encode_qp($self->{bytestream});
    return $self;
}

sub quote {
    my $self = shift;

    $self->{bytestream} = '' unless defined $self->{bytestream};

    # Escape
    $self->{bytestream} =~ s/([\"\\])/\\$1/g;
    $self->{bytestream} = '"' . $self->{bytestream} . '"';

    return $self;
}

sub to_string { return shift->{bytestream} }

sub unquote {
    my $self = shift;

    # Not quoted
    return $self unless defined $self->{bytestream};
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

    # Shortcut
    return $self unless defined $self->{bytestream};

    # Default to unreserved characters
    my $pattern = shift || 'A-Za-z0-9\-\.\_\~';

    # Escape
    $self->{bytestream} =~ s/([^$pattern])/sprintf('%%%02X',ord($1))/ge;

    return $self;
}

sub url_sanitize {
    my $self = shift;

    # Shortcut
    return $self unless defined $self->{bytestream};

    # Uppercase hex values and unescape unreserved characters
    $self->{bytestream} =~ s/%([0-9A-Fa-f]{2})/_sanitize($1)/ge;

    return $self;
}

sub url_unescape {
    my $self = shift;

    # Shortcut
    return $self unless defined $self->{bytestream};

    # Unescape
    $self->{bytestream} =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;

    return $self;
}

# Helper for url_sanitize
sub _sanitize {
    my $hex = shift;

    my $char = hex $hex;
    return chr $char if $UNRESERVED{$char};

    return '%' . uc $hex;
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
    $stream->encode('utf8');
    $stream->decode('utf8');
    $stream->md5_sum;
    $stream->qp_decode;
    $stream->qp_encode;
    $stream->quote;
    $stream->unquote;
    $stream->url_escape;
    $stream->url_sanitize;
    $stream->url_unescape;

    my $length = $stream->length;

    my $stream2 = $stream->clone;
    print $stream2->to_string;

    # Chained
    my $stream = Mojo::ByteStream->new('foo bar baz')->quote;
    $stream = $stream->unquote->encode('utf8)->b64_encode;
    print "$stream";

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

=head2 C<length>

    my $length = $stream->length;

=head2 C<md5_sum>

    $stream = $stream->md5_sum;

=head2 C<qp_decode>

    $stream = $stream->qp_decode;

=head2 C<qp_encode>

    $stream = $stream->qp_encode;

=head2 C<quote>

    $stream = $stream->quote;

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

=head1 SEE ALSO

L<Digest::MD5>, L<Encode>, L<MIME::Base64>, L<MIME::QuotedPrint>

=cut
