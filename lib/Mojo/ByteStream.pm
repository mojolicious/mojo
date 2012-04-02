package Mojo::ByteStream;
use Mojo::Base -strict;
use overload '""' => sub { shift->to_string }, fallback => 1;

use Mojo::Collection;
use Mojo::Util;

# Turn most functions from Mojo::Util into methods
my @UTILS = (
  qw/b64_decode b64_encode camelize decamelize hmac_md5_sum hmac_sha1_sum/,
  qw/html_escape html_unescape md5_bytes md5_sum punycode_decode/,
  qw/punycode_encode qp_decode qp_encode quote sha1_bytes sha1_sum trim/,
  qw/unquote url_escape url_unescape xml_escape/
);
{
  no strict 'refs';
  for my $name (@UTILS) {
    my $sub = Mojo::Util->can($name);
    *{__PACKAGE__ . "::$name"} = sub {
      my $self = shift;
      $$self = $sub->($$self, @_);
      return $self;
    };
  }
}

sub import {
  my $class = shift;
  return unless @_ > 0;
  no strict 'refs';
  no warnings 'redefine';
  my $caller = caller;
  *{"${caller}::b"} = sub { $class->new(@_) };
}

# "Do we have any food that wasn't brutally slaughtered?
#  Well, I think the veal died of loneliness."
sub new {
  my $class = shift;
  return bless \(my $dummy = join '', @_), ref $class || $class;
}

sub clone {
  my $self = shift;
  return $self->new($$self);
}

# "I want to share something with you: The three little sentences that will
#  get you through life.
#  Number 1: 'Cover for me.'
#  Number 2: 'Oh, good idea, Boss!'
#  Number 3: 'It was like that when I got here.'"
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

# "Old people don't need companionship.
#  They need to be isolated and studied so it can be determined what
#  nutrients they have that might be extracted for our personal use."
sub say {
  my ($self, $handle) = @_;
  $handle ||= \*STDOUT;
  say $handle $$self;
}

sub secure_compare {
  my ($self, $check) = @_;
  return Mojo::Util::secure_compare $$self, $check;
}

sub size { length ${shift()} }

sub split {
  my ($self, $pattern) = @_;
  return Mojo::Collection->new(map { $self->new($_) } split $pattern, $$self);
}

sub to_string { ${shift()} }

1;
__END__

=head1 NAME

Mojo::ByteStream - ByteStream

=head1 SYNOPSIS

  # Manipulate bytestreams
  use Mojo::ByteStream;
  my $stream = Mojo::ByteStream->new('foo_bar_baz');
  say $stream->camelize;

  # Chain methods
  my $stream = Mojo::ByteStream->new('foo bar baz')->quote;
  $stream = $stream->unquote->encode('UTF-8')->b64_encode;
  say $stream;

  # Use the alternative constructor
  use Mojo::ByteStream 'b';
  my $stream = b('foobarbaz')->html_escape;

=head1 DESCRIPTION

L<Mojo::ByteStream> provides a more friendly API for the bytestream
manipulation functions in L<Mojo::Util>.

=head1 METHODS

L<Mojo::ByteStream> implements the following methods.

=head2 C<new>

  my $stream = Mojo::ByteStream->new('test123');

Construct a new L<Mojo::ByteStream> object.

=head2 C<b64_decode>

  $stream = $stream->b64_decode;

Base64 decode bytestream.

=head2 C<b64_encode>

  $stream = $stream->b64_encode;
  $stream = $stream->b64_encode('');

Base64 encode bytestream.

=head2 C<camelize>

  $stream = $stream->camelize;

Convert snake case bytestream to camel case and replace C<-> with C<::>.

  foo_bar     -> FooBar
  foo_bar-baz -> FooBar::Baz

=head2 C<clone>

  my $stream2 = $stream->clone;

Clone bytestream.

=head2 C<decamelize>

  $stream = $stream->decamelize;

Convert camel case bytestream to snake case and replace C<::> with C<->.

  FooBar      -> foo_bar
  FooBar::Baz -> foo_bar-baz

=head2 C<decode>

  $stream = $stream->decode;
  $stream = $stream->decode($encoding);

Decode bytestream, defaults to C<UTF-8>.

  $stream->decode('UTF-8')->to_string;

=head2 C<encode>

  $stream = $stream->encode;
  $stream = $stream->encode($encoding);

Encode bytestream, defaults to C<UTF-8>.

  $stream->encode('UTF-8')->to_string;

=head2 C<hmac_md5_sum>

  $stream = $stream->hmac_md5_sum($secret);

Turn bytestream into HMAC-MD5 checksum of old content.

=head2 C<hmac_sha1_sum>

  $stream = $stream->hmac_sha1_sum($secret);

Turn bytestream into HMAC-SHA1 checksum of old content.

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

Punycode decode bytestream.

=head2 C<punycode_encode>

  $stream = $stream->punycode_encode;

Punycode encode bytestream.

=head2 C<qp_decode>

  $stream = $stream->qp_decode;

Quoted Printable decode bytestream.

=head2 C<qp_encode>

  $stream = $stream->qp_encode;

Quoted Printable encode bytestream.

=head2 C<quote>

  $stream = $stream->quote;

Quote bytestream.

=head2 C<say>

  $stream->say;
  $stream->say(*STDERR);

Print bytestream to handle or STDOUT and append a newline.

=head2 C<secure_compare>

  my $success = $stream->secure_compare($string);

Constant time comparison algorithm to prevent timing attacks.

=head2 C<sha1_bytes>

  $stream = $stream->sha1_bytes;

Turn bytestream into binary SHA1 checksum of old content.

=head2 C<sha1_sum>

  $stream = $stream->sha1_sum;

Turn bytestream into SHA1 checksum of old content.

=head2 C<size>

  my $size = $stream->size;

Size of bytestream.

=head2 C<split>

  my $collection = $stream->split(',');

Turn bytestream into L<Mojo::Collection>.

  $stream->split(',')->map(sub { $_->quote })->join("\n")->say;

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

=head2 C<url_unescape>

  $stream = $stream->url_unescape;

URL unescape bytestream.

=head2 C<xml_escape>

  $stream = $stream->xml_escape;

XML escape bytestream, this is a much faster version of C<html_escape>
escaping only the characters C<&>, C<E<lt>>, C<E<gt>>, C<"> and C<'>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
