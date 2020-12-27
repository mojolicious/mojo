package Mojo::ByteStream;
use Mojo::Base -strict;
use overload bool => sub {1}, '""' => sub { ${$_[0]} }, fallback => 1;

use Exporter qw(import);
use Mojo::Collection;
use Mojo::Util;

our @EXPORT_OK = ('b');

# Turn most functions from Mojo::Util into methods
my @UTILS = (
  qw(b64_decode b64_encode camelize decamelize gunzip gzip hmac_sha1_sum html_unescape humanize_bytes md5_bytes),
  qw(md5_sum punycode_decode punycode_encode quote sha1_bytes sha1_sum slugify term_escape trim unindent unquote),
  qw(url_escape url_unescape xml_escape xor_encode)
);
for my $name (@UTILS) {
  my $sub = Mojo::Util->can($name);
  Mojo::Util::monkey_patch __PACKAGE__, $name, sub {
    my $self = shift;
    $$self = $sub->($$self, @_);
    return $self;
  };
}

sub b { __PACKAGE__->new(@_) }

sub clone { $_[0]->new(${$_[0]}) }

sub decode { shift->_delegate(\&Mojo::Util::decode, @_) }
sub encode { shift->_delegate(\&Mojo::Util::encode, @_) }

sub new {
  my $class = shift;
  return bless \(my $dummy = join '', @_), ref $class || $class;
}

sub say {
  my ($self, $handle) = @_;
  $handle ||= \*STDOUT;
  say $handle $$self;
  return $self;
}

sub secure_compare { Mojo::Util::secure_compare ${shift()}, shift }

sub size { length ${$_[0]} }

sub split {
  my ($self, $pat, $lim) = (shift, shift, shift // 0);
  return Mojo::Collection->new(map { $self->new($_) } split $pat, $$self, $lim);
}

sub tap { shift->Mojo::Base::tap(@_) }

sub to_string { ${$_[0]} }

sub with_roles { shift->Mojo::Base::with_roles(@_) }

sub _delegate {
  my ($self, $sub) = (shift, shift);
  $$self = $sub->(shift || 'UTF-8', $$self);
  return $self;
}

1;

=encoding utf8

=head1 NAME

Mojo::ByteStream - ByteStream

=head1 SYNOPSIS

  use Mojo::ByteStream;

  # Manipulate bytestream
  my $stream = Mojo::ByteStream->new('foo_bar_baz');
  say $stream->camelize;

  # Chain methods
  my $stream = Mojo::ByteStream->new('foo bar baz')->quote;
  $stream = $stream->unquote->encode('UTF-8')->b64_encode('');
  say "$stream";

  # Use the alternative constructor
  use Mojo::ByteStream qw(b);
  my $stream = b('foobarbaz')->b64_encode('')->say;

=head1 DESCRIPTION

L<Mojo::ByteStream> is a scalar-based container for bytestreams that provides a more friendly API for many of the
functions in L<Mojo::Util>.

  # Access scalar directly to manipulate bytestream
  my $stream = Mojo::ByteStream->new('foo');
  $$stream .= 'bar';

=head1 FUNCTIONS

L<Mojo::ByteStream> implements the following functions, which can be imported individually.

=head2 b

  my $stream = b('test123');

Construct a new scalar-based L<Mojo::ByteStream> object.

=head1 METHODS

L<Mojo::ByteStream> implements the following methods.

=head2 b64_decode

  $stream = $stream->b64_decode;

Base64 decode bytestream with L<Mojo::Util/"b64_decode">.

=head2 b64_encode

  $stream = $stream->b64_encode;
  $stream = $stream->b64_encode("\n");

Base64 encode bytestream with L<Mojo::Util/"b64_encode">.

  # "Zm9vIGJhciBiYXo="
  b('foo bar baz')->b64_encode('');

=head2 camelize

  $stream = $stream->camelize;

Camelize bytestream with L<Mojo::Util/"camelize">.

=head2 clone

  my $stream2 = $stream->clone;

Return a new L<Mojo::ByteStream> object cloned from this bytestream.

=head2 decamelize

  $stream = $stream->decamelize;

Decamelize bytestream with L<Mojo::Util/"decamelize">.

=head2 decode

  $stream = $stream->decode;
  $stream = $stream->decode('iso-8859-1');

Decode bytestream with L<Mojo::Util/"decode">, defaults to using C<UTF-8>.

  # "♥"
  b('%E2%99%A5')->url_unescape->decode;

=head2 encode

  $stream = $stream->encode;
  $stream = $stream->encode('iso-8859-1');

Encode bytestream with L<Mojo::Util/"encode">, defaults to using C<UTF-8>.

  # "%E2%99%A5"
  b('♥')->encode->url_escape;

=head2 gunzip

  $stream = $stream->gunzip;

Uncompress bytestream with L<Mojo::Util/"gunzip">.

=head2 gzip

  stream = $stream->gzip;

Compress bytestream with L<Mojo::Util/"gzip">.

=head2 hmac_sha1_sum

  $stream = $stream->hmac_sha1_sum('passw0rd');

Generate HMAC-SHA1 checksum for bytestream with L<Mojo::Util/"hmac_sha1_sum">.

  # "7fbdc89263974a89210ea71f171c77d3f8c21471"
  b('foo bar baz')->hmac_sha1_sum('secr3t');

=head2 html_unescape

  $stream = $stream->html_unescape;

Unescape all HTML entities in bytestream with L<Mojo::Util/"html_unescape">.

  # "%3Chtml%3E"
  b('&lt;html&gt;')->html_unescape->url_escape;

=head2 humanize_bytes

  $stream = $stream->humanize_bytes;

Turn number of bytes into a simplified human readable format for bytestream with L<Mojo::Util/"humanize_bytes">.

=head2 md5_bytes

  $stream = $stream->md5_bytes;

Generate binary MD5 checksum for bytestream with L<Mojo::Util/"md5_bytes">.

=head2 md5_sum

  $stream = $stream->md5_sum;

Generate MD5 checksum for bytestream with L<Mojo::Util/"md5_sum">.

=head2 new

  my $stream = Mojo::ByteStream->new('test123');

Construct a new scalar-based L<Mojo::ByteStream> object.

=head2 punycode_decode

  $stream = $stream->punycode_decode;

Punycode decode bytestream with L<Mojo::Util/"punycode_decode">.

=head2 punycode_encode

  $stream = $stream->punycode_encode;

Punycode encode bytestream with L<Mojo::Util/"punycode_encode">.

=head2 quote

  $stream = $stream->quote;

Quote bytestream with L<Mojo::Util/"quote">.

=head2 say

  $stream = $stream->say;
  $stream = $stream->say(*STDERR);

Print bytestream to handle and append a newline, defaults to using C<STDOUT>.

=head2 secure_compare

  my $bool = $stream->secure_compare($str);

Compare bytestream with L<Mojo::Util/"secure_compare">.

=head2 sha1_bytes

  $stream = $stream->sha1_bytes;

Generate binary SHA1 checksum for bytestream with L<Mojo::Util/"sha1_bytes">.

=head2 sha1_sum

  $stream = $stream->sha1_sum;

Generate SHA1 checksum for bytestream with L<Mojo::Util/"sha1_sum">.

=head2 size

  my $size = $stream->size;

Size of bytestream.

=head2 slugify

  $stream = $stream->slugify;
  $stream = $stream->slugify($bool);

Generate URL slug for bytestream with L<Mojo::Util/"slugify">.

=head2 split

  my $collection = $stream->split(',');
  my $collection = $stream->split(',', -1);

Turn bytestream into L<Mojo::Collection> object containing L<Mojo::ByteStream> objects.

  # "One,Two,Three"
  b("one,two,three")->split(',')->map('camelize')->join(',');

  # "One,Two,Three,,,"
  b("one,two,three,,,")->split(',', -1)->map('camelize')->join(',');

=head2 tap

  $stream = $stream->tap(sub {...});

Alias for L<Mojo::Base/"tap">.

=head2 term_escape

  $stream = $stream->term_escape;

Escape POSIX control characters in bytestream with L<Mojo::Util/"term_escape">.

  # Print binary checksum to terminal
  b('foo')->sha1_bytes->term_escape->say;

=head2 to_string

  my $str = $stream->to_string;

Stringify bytestream.

=head2 trim

  $stream = $stream->trim;

Trim whitespace characters from both ends of bytestream with L<Mojo::Util/"trim">.

=head2 unindent

  $stream = $stream->unindent;

Unindent bytestream with L<Mojo::Util/"unindent">.

=head2 unquote

  $stream = $stream->unquote;

Unquote bytestream with L<Mojo::Util/"unquote">.

=head2 url_escape

  $stream = $stream->url_escape;
  $stream = $stream->url_escape('^A-Za-z0-9\-._~');

Percent encode all unsafe characters in bytestream with L<Mojo::Util/"url_escape">.

  # "%E2%98%83"
  b('☃')->encode->url_escape;

=head2 url_unescape

  $stream = $stream->url_unescape;

Decode percent encoded characters in bytestream with L<Mojo::Util/"url_unescape">.

  # "&lt;html&gt;"
  b('%3Chtml%3E')->url_unescape->xml_escape;

=head2 with_roles

  my $new_class = Mojo::ByteStream->with_roles('Mojo::ByteStream::Role::One');
  my $new_class = Mojo::ByteStream->with_roles('+One', '+Two');
  $stream       = $stream->with_roles('+One', '+Two');

Alias for L<Mojo::Base/"with_roles">.

=head2 xml_escape

  $stream = $stream->xml_escape;

Escape only the characters C<&>, C<E<lt>>, C<E<gt>>, C<"> and C<'> in bytestream with L<Mojo::Util/"xml_escape">.

=head2 xor_encode

  $stream = $stream->xor_encode($key);

XOR encode bytestream with L<Mojo::Util/"xor_encode">.

  # "%04%0E%15B%03%1B%10"
  b('foo bar')->xor_encode('baz')->url_escape;

=head1 OPERATORS

L<Mojo::ByteStream> overloads the following operators.

=head2 bool

  my $bool = !!$bytestream;

Always true.

=head2 stringify

  my $str = "$bytestream";

Alias for L</"to_string">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
