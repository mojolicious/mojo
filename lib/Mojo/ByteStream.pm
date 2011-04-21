package Mojo::ByteStream;
use Mojo::Base -base;
use overload '""' => sub { shift->to_string }, fallback => 1;

use Mojo::Util;

sub import {
  return unless @_ > 1;

  # Alternative constructor
  no strict 'refs';
  no warnings 'redefine';
  my $caller = caller;
  *{"${caller}::b"} =
    sub { bless {bytestream => join('', @_)}, 'Mojo::ByteStream' };
}

# "Do we have any food that wasn't brutally slaughtered?
#  Well, I think the veal died of loneliness."
sub new {
  my $self = shift->SUPER::new();
  $self->{bytestream} = join '', @_;
  return $self;
}

sub b64_decode {
  my $self = shift;
  $self->{bytestream} = Mojo::Util::b64_decode($self->{bytestream});
  return $self;
}

sub b64_encode {
  my $self = shift;
  $self->{bytestream} = Mojo::Util::b64_encode($self->{bytestream}, @_);
  return $self;
}

sub camelize {
  my $self = shift;
  Mojo::Util::camelize $self->{bytestream};
  return $self;
}

sub clone {
  my $self = shift;
  return $self->new($self->{bytestream});
}

sub decamelize {
  my $self = shift;
  Mojo::Util::decamelize $self->{bytestream};
  return $self;
}

# "I want to share something with you: The three little sentences that will
#  get you through life.
#  Number 1: 'Cover for me.'
#  Number 2: 'Oh, good idea, Boss!'
#  Number 3: 'It was like that when I got here.'"
sub decode {
  my $self = shift;
  Mojo::Util::decode shift || 'UTF-8', $self->{bytestream};
  return $self;
}

sub encode {
  my $self = shift;
  Mojo::Util::encode shift || 'UTF-8', $self->{bytestream};
  return $self;
}

sub hmac_md5_sum {
  my $self = shift;
  $self->{bytestream} = Mojo::Util::hmac_md5_sum $self->{bytestream}, @_;
  return $self;
}

sub hmac_sha1_sum {
  my $self = shift;
  $self->{bytestream} = Mojo::Util::hmac_sha1_sum $self->{bytestream}, @_;
  return $self;
}

sub html_escape {
  my $self = shift;
  Mojo::Util::html_escape $self->{bytestream};
  return $self;
}

sub html_unescape {
  my $self = shift;
  Mojo::Util::html_unescape $self->{bytestream};
  return $self;
}

sub md5_bytes {
  my $self = shift;
  $self->{bytestream} = Mojo::Util::md5_bytes $self->{bytestream};
  return $self;
}

sub md5_sum {
  my $self = shift;
  $self->{bytestream} = Mojo::Util::md5_sum $self->{bytestream};
  return $self;
}

sub punycode_decode {
  my $self = shift;
  Mojo::Util::punycode_decode $self->{bytestream};
  return $self;
}

sub punycode_encode {
  my $self = shift;
  Mojo::Util::punycode_encode $self->{bytestream};
  return $self;
}

# "Old people don't need companionship.
#  They need to be isolated and studied so it can be determined what
#  nutrients they have that might be extracted for our personal use."
sub qp_decode {
  my $self = shift;
  Mojo::Util::qp_decode $self->{bytestream};
  return $self;
}

sub qp_encode {
  my $self = shift;
  Mojo::Util::qp_encode $self->{bytestream};
  return $self;
}

sub quote {
  my $self = shift;
  Mojo::Util::quote $self->{bytestream};
  return $self;
}

sub say {
  my ($self, $handle) = @_;
  $handle ||= \*STDOUT;
  utf8::encode $self->{bytestream} if utf8::is_utf8 $self->{bytestream};
  print $handle $self->{bytestream}, "\n";
}

sub sha1_bytes {
  my $self = shift;
  $self->{bytestream} = Mojo::Util::sha1_bytes $self->{bytestream};
  return $self;
}

sub sha1_sum {
  my $self = shift;
  $self->{bytestream} = Mojo::Util::sha1_sum $self->{bytestream};
  return $self;
}

sub size { length shift->{bytestream} }

sub to_string { shift->{bytestream} }

sub trim {
  my $self = shift;
  Mojo::Util::trim $self->{bytestream}, @_;
  return $self;
}

sub unquote {
  my $self = shift;
  Mojo::Util::unquote $self->{bytestream}, @_;
  return $self;
}

sub url_escape {
  my $self = shift;
  Mojo::Util::url_escape $self->{bytestream}, @_;
  return $self;
}

sub url_unescape {
  my $self = shift;
  Mojo::Util::url_unescape $self->{bytestream};
  return $self;
}

sub xml_escape {
  my $self = shift;
  Mojo::Util::xml_escape $self->{bytestream};
  return $self;
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

=head1 DESCRIPTION

L<Mojo::ByteStream> provides a more friendly API for the bytestream
manipulation functions in L<Mojo::Util>.

=head1 METHODS

L<Mojo::ByteStream> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

  my $stream = Mojo::ByteStream->new($string);

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

Camelize bytestream.

  foo_bar -> FooBar

=head2 C<clone>

  my $stream2 = $stream->clone;

Clone bytestream.

=head2 C<decamelize>

  $stream = $stream->decamelize;

Decamelize bytestream.

  FooBar -> foo_bar

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
