package Mojo::ByteStream;
use Mojo::Base -base;
use overload '""' => sub { shift->to_string }, fallback => 1;

use Exporter 'import';
use Mojo::Collection;
use Mojo::Util;

our @EXPORT_OK = ('b');

# Turn most functions from Mojo::Util into methods
my @UTILS = (
  qw(b64_decode b64_encode camelize decamelize hmac_sha1_sum html_unescape),
  qw(md5_bytes md5_sum punycode_decode punycode_encode quote sha1_bytes),
  qw(sha1_sum slurp spurt squish trim unquote url_escape url_unescape),
  qw(xml_escape xor_encode)
);
for my $name (@UTILS) {
  my $sub = Mojo::Util->can($name);
  Mojo::Util::monkey_patch __PACKAGE__, $name, sub {
    my $self = shift;
    $$self = $sub->($$self, @_);
    return $self;
  };
}

sub new {
  my $class = shift;
  return bless \(my $dummy = join '', @_), ref $class || $class;
}

sub b { __PACKAGE__->new(@_) }

sub clone { $_[0]->new(${$_[0]}) }

sub decode {
  my $self = shift;
  $$self = Mojo::Util::decode shift || 'UTF-8', $$self;
  return $self;
}

sub encode {
  my $self = shift;
  $$self = Mojo::Util::encode shift || 'UTF-8', $$self;
  return $self;
}

sub say {
  my ($self, $handle) = @_;
  $handle ||= \*STDOUT;
  say $handle $$self;
}

sub secure_compare { Mojo::Util::secure_compare ${shift()}, @_ }

sub size { length ${$_[0]} }

sub split {
  my ($self, $pattern) = @_;
  return Mojo::Collection->new(map { $self->new($_) } split $pattern, $$self);
}

sub to_string { ${$_[0]} }

1;

=head1 NAME

Mojo::ByteStream - ByteStream

=head1 SYNOPSIS

  # Manipulate bytestreams
  use Mojo::ByteStream;
  my $stream = Mojo::ByteStream->new('foo_bar_baz');
  say $stream->camelize;

  # Chain methods
  my $stream = Mojo::ByteStream->new('foo bar baz')->quote;
  $stream = $stream->unquote->encode('UTF-8')->b64_encode('');
  say "$stream";

  # Use the alternative constructor
  use Mojo::ByteStream 'b';
  my $stream = b('foobarbaz')->b64_encode('')->say;

=head1 DESCRIPTION

L<Mojo::ByteStream> provides a more friendly API for the bytestream
manipulation functions in L<Mojo::Util>.

=head1 FUNCTIONS

L<Mojo::ByteStream> implements the following functions.

=head2 b

  my $stream = b('test123');

Construct a new scalar-based L<Mojo::ByteStream> object.

=head1 METHODS

L<Mojo::ByteStream> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 new

  my $stream = Mojo::ByteStream->new('test123');

Construct a new scalar-based L<Mojo::ByteStream> object.

=head2 b64_decode

  $stream = $stream->b64_decode;

Base64 decode bytestream with L<Mojo::Util/"b64_decode">.

=head2 b64_encode

  $stream = $stream->b64_encode;
  $stream = $stream->b64_encode("\n");

Base64 encode bytestream with L<Mojo::Util/"b64_encode">.

  b('foo bar baz')->b64_encode('')->say;

=head2 camelize

  $stream = $stream->camelize;

Camelize bytestream with L<Mojo::Util/"camelize">.

=head2 clone

  my $stream2 = $stream->clone;

Clone bytestream.

=head2 decamelize

  $stream = $stream->decamelize;

Decamelize bytestream with L<Mojo::Util/"decamelize">.

=head2 decode

  $stream = $stream->decode;
  $stream = $stream->decode('iso-8859-1');

Decode bytestream with L<Mojo::Util/"decode">, defaults to C<UTF-8>.

  $stream->decode('UTF-16LE')->unquote->trim->say;

=head2 encode

  $stream = $stream->encode;
  $stream = $stream->encode('iso-8859-1');

Encode bytestream with L<Mojo::Util/"encode">, defaults to C<UTF-8>.

  $stream->trim->quote->encode->say;

=head2 hmac_sha1_sum

  $stream = $stream->hmac_sha1_sum('passw0rd');

Generate HMAC-SHA1 checksum for bytestream with L<Mojo::Util/"hmac_sha1_sum">.

  b('foo bar baz')->hmac_sha1_sum('secr3t')->quote->say;

=head2 html_unescape

  $stream = $stream->html_unescape;

Unescape all HTML entities in bytestream with L<Mojo::Util/"html_unescape">.

  b('&lt;html&gt;')->html_unescape->url_escape->say;

=head2 md5_bytes

  $stream = $stream->md5_bytes;

Generate binary MD5 checksum for bytestream with L<Mojo::Util/"md5_bytes">.

=head2 md5_sum

  $stream = $stream->md5_sum;

Generate MD5 checksum for bytestream with L<Mojo::Util/"md5_sum">.

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

  $stream->say;
  $stream->say(*STDERR);

Print bytestream to handle and append a newline, defaults to C<STDOUT>.

=head2 secure_compare

  my $success = $stream->secure_compare($str);

Compare bytestream with L<Mojo::Util/"secure_compare">.

  say 'Match!' if b('foo')->secure_compare('foo');

=head2 sha1_bytes

  $stream = $stream->sha1_bytes;

Generate binary SHA1 checksum for bytestream with L<Mojo::Util/"sha1_bytes">.

=head2 sha1_sum

  $stream = $stream->sha1_sum;

Generate SHA1 checksum for bytestream with L<Mojo::Util/"sha1_sum">.

=head2 size

  my $size = $stream->size;

Size of bytestream.

=head2 slurp

  $stream = $stream->slurp;

Read all data at once from file into bytestream with L<Mojo::Util/"slurp">.

  b('/home/sri/myapp.pl')->slurp->split("\n")->shuffle->join("\n")->say;

=head2 spurt

  $stream = $stream->spurt('/home/sri/myapp.pl');

Write all data from bytestream at once to file with L<Mojo::Util/"spurt">.

  b('/home/sri/foo.txt')->slurp->squish->spurt('/home/sri/bar.txt');

=head2 split

  my $collection = $stream->split(',');

Turn bytestream into L<Mojo::Collection>.

  b('a,b,c')->split(',')->pluck('quote')->join(',')->say;

=head2 squish

  $stream = $stream->squish;

Trim whitespace characters from both ends of bytestream and then change all
consecutive groups of whitespace into one space each with
L<Mojo::Util/"squish">.

=head2 to_string

  my $str = $stream->to_string;
  my $str = "$stream";

Stringify bytestream.

=head2 trim

  $stream = $stream->trim;

Trim whitespace characters from both ends of bytestream with
L<Mojo::Util/"trim">.

=head2 unquote

  $stream = $stream->unquote;

Unquote bytestream with L<Mojo::Util/"unquote">.

=head2 url_escape

  $stream = $stream->url_escape;
  $stream = $stream->url_escape('^A-Za-z0-9\-._~');

Percent encode all unsafe characters in bytestream with
L<Mojo::Util/"url_escape">.

  b('foo bar baz')->url_escape->say;

=head2 url_unescape

  $stream = $stream->url_unescape;

Decode percent encoded characters in bytestream with
L<Mojo::Util/"url_unescape">.

  b('%3Chtml%3E')->url_unescape->xml_escape->say;

=head2 xml_escape

  $stream = $stream->xml_escape;

Escape only the characters C<&>, C<E<lt>>, C<E<gt>>, C<"> and C<'> in
bytestream with L<Mojo::Util/"xml_escape">.

=head2 xor_encode

  $stream = $stream->xor_encode($key);

XOR encode bytestream with L<Mojo::Util/"xor_encode">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
