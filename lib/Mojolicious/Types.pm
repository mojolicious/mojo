package Mojolicious::Types;
use Mojo::Base -base;

# "Once again, the conservative, sandwich-heavy portfolio pays off for the
#  hungry investor."
has types => sub {
  return {
    atom => 'application/atom+xml',
    bin  => 'application/octet-stream',
    css  => 'text/css',
    gif  => 'image/gif',
    gz   => 'application/gzip',
    htm  => 'text/html',
    html => 'text/html;charset=UTF-8',
    ico  => 'image/x-icon',
    jpeg => 'image/jpeg',
    jpg  => 'image/jpeg',
    js   => 'application/x-javascript',
    json => 'application/json',
    mp3  => 'audio/mpeg',
    pdf  => 'application/pdf',
    png  => 'image/png',
    rss  => 'application/rss+xml',
    svg  => 'image/svg+xml',
    tar  => 'application/x-tar',
    txt  => 'text/plain',
    woff => 'application/x-font-woff',
    xml  => 'text/xml',
    xsl  => 'text/xml',
    zip  => 'application/zip'
  };
};

# "Magic. Got it."
sub detect {
  my ($self, $accept) = @_;

  # Detect extensions from MIME type
  return [] unless (($accept || '') =~ /^([^,]+?)(?:\;[^,]*)*$/);
  my $type = lc $1;
  my @exts;
  my $types = $self->types;
  for my $ext (sort keys %$types) {
    my @types = ref $types->{$ext} ? @{$types->{$ext}} : ($types->{$ext});
    $type eq $_ and push @exts, $ext for map { s/\;.*$//; lc $_ } @types;
  }

  return \@exts;
}

sub type {
  my ($self, $ext) = (shift, shift);
  my $types = $self->types;
  return ref $types->{$ext} ? $types->{$ext}[0] : $types->{$ext} unless @_;
  $types->{$ext} = shift;
  return $self;
}

1;
__END__

=head1 NAME

Mojolicious::Types - MIME types

=head1 SYNOPSIS

  use Mojolicious::Types;

  my $types = Mojolicious::Types->new;

=head1 DESCRIPTION

L<Mojolicious::Types> is a container for MIME types.

=head1 ATTRIBUTES

L<Mojolicious::Types> implements the following attributes.

=head2 C<types>

  my $map = $types->types;
  $types  = $types->types({png => 'image/png'});

List of MIME types.

=head1 METHODS

L<Mojolicious::Types> inherits all methods from L<Mojo::Base> and implements
the following ones.

=head2 C<detect>

  my $ext = $types->detect('application/json;q=9');

Detect file extensions from C<Accept> header value. Unspecific values that
contain more than one MIME type are currently ignored, since browsers often
don't really know what they actually want.

=head2 C<type>

  my $type = $types->type('png');
  $types   = $types->type(png => 'image/png');
  $types   = $types->type(json => ['application/json', 'text/x-json']);

Get or set MIME types for file extension, alternatives are only used for
detection.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
