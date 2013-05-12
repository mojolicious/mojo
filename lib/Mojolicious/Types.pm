package Mojolicious::Types;
use Mojo::Base -base;

has types => sub {
  {
    appcache => ['text/cache-manifest'],
    atom     => ['application/atom+xml'],
    bin      => ['application/octet-stream'],
    css      => ['text/css'],
    gif      => ['image/gif'],
    gz       => ['application/x-gzip'],
    htm      => ['text/html'],
    html     => ['text/html;charset=UTF-8'],
    ico      => ['image/x-icon'],
    jpeg     => ['image/jpeg'],
    jpg      => ['image/jpeg'],
    js       => ['application/javascript'],
    json     => ['application/json'],
    mp3      => ['audio/mpeg'],
    mp4      => ['video/mp4'],
    ogg      => ['audio/ogg'],
    ogv      => ['video/ogg'],
    pdf      => ['application/pdf'],
    png      => ['image/png'],
    rss      => ['application/rss+xml'],
    svg      => ['image/svg+xml'],
    txt      => ['text/plain'],
    webm     => ['video/webm'],
    woff     => ['application/font-woff'],
    xml      => ['application/xml', 'text/xml'],
    zip      => ['application/zip']
  };
};

sub detect {
  my ($self, $accept, $prioritize) = @_;

  # Extract and prioritize MIME types
  my %types;
  /^\s*([^,; ]+)(?:\s*\;\s*q=(\d+(?:\.\d+)?))?\s*$/i
    and $types{lc $1} = $2 // 1
    for split /,/, $accept // '';
  my @detected = sort { $types{$b} <=> $types{$a} } sort keys %types;
  return [] if !$prioritize && @detected > 1;

  # Detect extensions from MIME types
  my %reverse;
  my $types = $self->types;
  for my $ext (sort keys %$types) {
    my @types = @{$types->{$ext}};
    push @{$reverse{$_}}, $ext for map { s/\;.*$//; lc $_ } @types;
  }
  return [map { @{$reverse{$_} // []} } @detected];
}

sub type {
  my ($self, $ext, $type) = @_;
  return $self->types->{$ext}[0] unless $type;
  $self->types->{$ext} = ref $type ? $type : [$type];
  return $self;
}

1;

=head1 NAME

Mojolicious::Types - MIME types

=head1 SYNOPSIS

  use Mojolicious::Types;

  my $types = Mojolicious::Types->new;
  $types->type(foo => 'text/foo');
  say $types->type('foo');

=head1 DESCRIPTION

L<Mojolicious::Types> manages MIME types for L<Mojolicious>.

  appcache -> text/cache-manifest
  atom     -> application/atom+xml
  bin      -> application/octet-stream
  css      -> text/css
  gif      -> image/gif
  gz       -> application/x-gzip
  htm      -> text/html
  html     -> text/html;charset=UTF-8
  ico      -> image/x-icon
  jpeg     -> image/jpeg
  jpg      -> image/jpeg
  js       -> application/javascript
  json     -> application/json
  mp3      -> audio/mpeg
  mp4      -> video/mp4
  ogg      -> audio/ogg
  ogv      -> video/ogg
  pdf      -> application/pdf
  png      -> image/png
  rss      -> application/rss+xml
  svg      -> image/svg+xml
  txt      -> text/plain
  webm     -> video/webm
  woff     -> application/font-woff
  xml      -> application/xml,text/xml
  zip      -> application/zip

The most common ones are already defined.

=head1 ATTRIBUTES

L<Mojolicious::Types> implements the following attributes.

=head2 types

  my $map = $types->types;
  $types  = $types->types({png => ['image/png']});

List of MIME types.

=head1 METHODS

L<Mojolicious::Types> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 detect

  my $exts = $types->detect('application/json;q=9');
  my $exts = $types->detect('text/html, application/json;q=9', 1);

Detect file extensions from C<Accept> header value, prioritization of
unspecific values that contain more than one MIME type is disabled by default.

  # List detected extensions prioritized
  say for @{$types->detect('application/json, text/xml;q=0.1', 1)};

=head2 type

  my $type = $types->type('png');
  $types   = $types->type(png => 'image/png');
  $types   = $types->type(json => [qw(application/json text/x-json)]);

Get or set MIME types for file extension, alternatives are only used for
detection.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
