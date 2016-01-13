package Mojo::Content::Single;
use Mojo::Base 'Mojo::Content';

use Mojo::Asset::Memory;
use Mojo::Content::MultiPart;

has asset => sub { Mojo::Asset::Memory->new(auto_upgrade => 1) };
has auto_upgrade => 1;

sub body_contains { shift->asset->contains(shift) >= 0 }

sub body_size {
  my $self = shift;
  return ($self->headers->content_length || 0) if $self->{dynamic};
  return $self->asset->size;
}

sub clone {
  my $self = shift;
  return undef unless my $clone = $self->SUPER::clone();
  return $clone->asset($self->asset);
}

sub get_body_chunk {
  my ($self, $offset) = @_;
  return $self->generate_body_chunk($offset) if $self->{dynamic};
  return $self->asset->get_chunk($offset);
}

sub new {
  my $self = shift->SUPER::new(@_);
  $self->{read}
    = $self->on(read => sub { $_[0]->asset($_[0]->asset->add_chunk($_[1])) });
  return $self;
}

sub parse {
  my $self = shift;

  # Parse headers
  $self->_parse_until_body(@_);

  # Parse body
  return $self->SUPER::parse
    unless $self->auto_upgrade && defined $self->boundary;

  # Content needs to be upgraded to multipart
  $self->unsubscribe(read => $self->{read});
  my $multi = Mojo::Content::MultiPart->new(%$self);
  $self->emit(upgrade => $multi);
  return $multi->parse;
}

1;

=encoding utf8

=head1 NAME

Mojo::Content::Single - HTTP content

=head1 SYNOPSIS

  use Mojo::Content::Single;

  my $single = Mojo::Content::Single->new;
  $single->parse("Content-Length: 12\x0d\x0a\x0d\x0aHello World!");
  say $single->headers->content_length;

=head1 DESCRIPTION

L<Mojo::Content::Single> is a container for HTTP content, based on
L<RFC 7230|http://tools.ietf.org/html/rfc7230> and
L<RFC 7231|http://tools.ietf.org/html/rfc7231>.

=head1 EVENTS

L<Mojo::Content::Single> inherits all events from L<Mojo::Content> and can emit
the following new ones.

=head2 upgrade

  $single->on(upgrade => sub {
    my ($single, $multi) = @_;
    ...
  });

Emitted when content gets upgraded to a L<Mojo::Content::MultiPart> object.

  $single->on(upgrade => sub {
    my ($single, $multi) = @_;
    return unless $multi->headers->content_type =~ /multipart\/([^;]+)/i;
    say "Multipart: $1";
  });

=head1 ATTRIBUTES

L<Mojo::Content::Single> inherits all attributes from L<Mojo::Content> and
implements the following new ones.

=head2 asset

  my $asset = $single->asset;
  $single   = $single->asset(Mojo::Asset::Memory->new);

The actual content, defaults to a L<Mojo::Asset::Memory> object with
L<Mojo::Asset::Memory/"auto_upgrade"> enabled.

=head2 auto_upgrade

  my $bool = $single->auto_upgrade;
  $single  = $single->auto_upgrade($bool);

Try to detect multipart content and automatically upgrade to a
L<Mojo::Content::MultiPart> object, defaults to a true value.

=head1 METHODS

L<Mojo::Content::Single> inherits all methods from L<Mojo::Content> and
implements the following new ones.

=head2 body_contains

  my $bool = $single->body_contains('1234567');

Check if content contains a specific string.

=head2 body_size

  my $size = $single->body_size;

Content size in bytes.

=head2 clone

  my $clone = $single->clone;

Clone content if possible, otherwise return C<undef>.

=head2 get_body_chunk

  my $bytes = $single->get_body_chunk(0);

Get a chunk of content starting from a specific position. Note that it might
not be possible to get the same chunk twice if content was generated
dynamically.

=head2 new

  my $single = Mojo::Content::Single->new;
  my $single = Mojo::Content::Single->new(asset => Mojo::Asset::File->new);
  my $single = Mojo::Content::Single->new({asset => Mojo::Asset::File->new});

Construct a new L<Mojo::Content::Single> object and subscribe to L</"read">
event with default content parser.

=head2 parse

  $single = $single->parse("Content-Length: 12\x0d\x0a\x0d\x0aHello World!");
  my $multi
    = $single->parse("Content-Type: multipart/form-data\x0d\x0a\x0d\x0a");

Parse content chunk and upgrade to L<Mojo::Content::MultiPart> object if
necessary.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
