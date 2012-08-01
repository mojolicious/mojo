package Mojo::ByteStream;
use Mojo::Base 'Exporter';
use overload '""' => sub { shift->to_string }, fallback => 1;

use Mojo::Collection;
use Mojo::Util;

our @EXPORT_OK = ('b');

# Turn most functions from Mojo::Util into methods
my @UTILS = (
  qw(b64_decode b64_encode camelize decamelize hmac_md5_sum hmac_sha1_sum),
  qw(html_escape html_unescape md5_bytes md5_sum punycode_decode),
  qw(punycode_encode quote sha1_bytes sha1_sum slurp spurt trim unquote),
  qw(url_escape url_unescape xml_escape)
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

# "Do we have any food that wasn't brutally slaughtered?
#  Well, I think the veal died of loneliness."
sub new {
  my $class = shift;
  return bless \(my $dummy = join '', @_), ref $class || $class;
}

sub b { __PACKAGE__->new(@_) }

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

sub secure_compare { Mojo::Util::secure_compare ${shift()}, @_ }

sub size { length ${shift()} }

sub split {
  my ($self, $pattern) = @_;
  return Mojo::Collection->new(map { $self->new($_) } split $pattern, $$self);
}

# "My cat's breath smells like cat food."
sub to_string { ${shift()} }

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
  my $stream = b('foobarbaz')->html_escape;

=head1 DESCRIPTION

L<Mojo::ByteStream> provides a more friendly API for the bytestream
manipulation functions in L<Mojo::Util>.

=head1 FUNCTIONS

L<Mojo::ByteStream> implements the following functions.

=head2 C<b>

  my $stream = b('test123');

Construct a new L<Mojo::ByteStream> object.

=head1 METHODS

L<Mojo::ByteStream> implements the following methods.

=head2 C<new>

  my $stream = Mojo::ByteStream->new('test123');

Construct a new L<Mojo::ByteStream> object.

=head2 C<b64_decode>

  $stream = $stream->b64_decode;

Manipulate bytestream with L<Mojo::Util/"b64_decode">.

=head2 C<b64_encode>

  $stream = $stream->b64_encode;
  $stream = $stream->b64_encode("\n");

Manipulate bytestream with L<Mojo::Util/"b64_encode">.

  b('foo bar baz')->b64_encode('')->say;

=head2 C<camelize>

  $stream = $stream->camelize;

Manipulate bytestream with L<Mojo::Util/"camelize">.

=head2 C<clone>

  my $stream2 = $stream->clone;

Clone bytestream.

=head2 C<decamelize>

  $stream = $stream->decamelize;

Manipulate bytestream with L<Mojo::Util/"decamelize">.

=head2 C<decode>

  $stream = $stream->decode;
  $stream = $stream->decode('iso-8859-1');

Manipulate bytestream with L<Mojo::Util/"decode">, defaults to C<UTF-8>.

  $stream->decode('UTF-16LE')->unquote->trim->say;

=head2 C<encode>

  $stream = $stream->encode;
  $stream = $stream->encode('iso-8859-1');

Manipulate bytestream with L<Mojo::Util/"encode">, defaults to C<UTF-8>.

  $stream->trim->quote->encode->say;

=head2 C<hmac_md5_sum>

  $stream = $stream->hmac_md5_sum('passw0rd');

Manipulate bytestream with L<Mojo::Util/"hmac_md5_sum">.

=head2 C<hmac_sha1_sum>

  $stream = $stream->hmac_sha1_sum('passw0rd');

Manipulate bytestream with L<Mojo::Util/"hmac_sha1_sum">.

  b('foo bar baz')->hmac_sha1_sum('secr3t')->quote->say;

=head2 C<html_escape>

  $stream = $stream->html_escape;
  $stream = $stream->html_escape('^\n\r\t !#$%(-;=?-~');

Manipulate bytestream with L<Mojo::Util/"html_escape">.

  b('<html>')->html_escape->say;

=head2 C<html_unescape>

  $stream = $stream->html_unescape;

Manipulate bytestream with L<Mojo::Util/"html_unescape">.

  b('&lt;html&gt;')->html_unescape->url_escape->say;

=head2 C<md5_bytes>

  $stream = $stream->md5_bytes;

Manipulate bytestream with L<Mojo::Util/"md5_bytes">.

=head2 C<md5_sum>

  $stream = $stream->md5_sum;

Manipulate bytestream with L<Mojo::Util/"md5_sum">.

=head2 C<punycode_decode>

  $stream = $stream->punycode_decode;

Manipulate bytestream with L<Mojo::Util/"punycode_decode">.

=head2 C<punycode_encode>

  $stream = $stream->punycode_encode;

Manipulate bytestream with L<Mojo::Util/"punycode_encode">.

=head2 C<quote>

  $stream = $stream->quote;

Manipulate bytestream with L<Mojo::Util/"quote">.

=head2 C<say>

  $stream->say;
  $stream->say(*STDERR);

Print bytestream to handle or STDOUT and append a newline.

=head2 C<secure_compare>

  my $success = $stream->secure_compare($string);

Check bytestream with L<Mojo::Util/"secure_compare">.

  say 'Match!' if b('foo')->secure_compare('foo');

=head2 C<sha1_bytes>

  $stream = $stream->sha1_bytes;

Manipulate bytestream with L<Mojo::Util/"sha1_bytes">.

=head2 C<sha1_sum>

  $stream = $stream->sha1_sum;

Manipulate bytestream with L<Mojo::Util/"sha1_sum">.

=head2 C<size>

  my $size = $stream->size;

Size of bytestream.

=head2 C<slurp>

  $stream = $stream->slurp;

Manipulate bytestream with L<Mojo::Util/"slurp">.

  b('/home/sri/myapp.pl')->slurp->split("\n")->shuffle->join("\n")->say;

=head2 C<spurt>

  $stream = $stream->spurt('/home/sri/myapp.pl');

Write bytestream to file with L<Mojo::Util/"spurt">.

  b('/home/sri/foo.html')->slurp->html_unescape->spurt('/home/sri/bar.html');

=head2 C<split>

  my $collection = $stream->split(',');

Turn bytestream into L<Mojo::Collection>.

  b('a,b,c')->split(',')->pluck('quote')->join(',')->say;

=head2 C<to_string>

  my $string = $stream->to_string;
  my $string = "$stream";

Stringify bytestream.

=head2 C<trim>

  $stream = $stream->trim;

Manipulate bytestream with L<Mojo::Util/"trim">.

=head2 C<unquote>

  $stream = $stream->unquote;

Manipulate bytestream with L<Mojo::Util/"unquote">.

=head2 C<url_escape>

  $stream = $stream->url_escape;
  $stream = $stream->url_escape('^A-Za-z0-9\-._~');

Manipulate bytestream with L<Mojo::Util/"url_escape">.

  b('foo bar baz')->url_escape->say;

=head2 C<url_unescape>

  $stream = $stream->url_unescape;

Manipulate bytestream with L<Mojo::Util/"url_unescape">.

  b('%3Chtml%3E')->url_unescape->html_escape->say;

=head2 C<xml_escape>

  $stream = $stream->xml_escape;

Manipulate bytestream with L<Mojo::Util/"xml_escape">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
