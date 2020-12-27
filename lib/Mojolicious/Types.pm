package Mojolicious::Types;
use Mojo::Base -base;

use Mojo::File qw(path);

has mapping => sub {
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
    json     => ['application/json;charset=UTF-8'],
    mp3      => ['audio/mpeg'],
    mp4      => ['video/mp4'],
    ogg      => ['audio/ogg'],
    ogv      => ['video/ogg'],
    pdf      => ['application/pdf'],
    png      => ['image/png'],
    rss      => ['application/rss+xml'],
    svg      => ['image/svg+xml'],
    ttf      => ['font/ttf'],
    txt      => ['text/plain;charset=UTF-8'],
    webm     => ['video/webm'],
    woff     => ['font/woff'],
    woff2    => ['font/woff2'],
    xml      => ['application/xml', 'text/xml'],
    zip      => ['application/zip']
  };
};

sub content_type {
  my ($self, $c, $o) = (shift, shift, shift // {});

  my $headers = $c->res->headers;
  return undef if $headers->content_type;

  my $type = $o->{file} ? $self->file_type($o->{file}) : $self->type($o->{ext});
  $headers->content_type($type // 'application/octet-stream');
}

sub detect {
  my ($self, $accept) = @_;

  # Extract and prioritize MIME types
  my %types;
  /^\s*([^,; ]+)(?:\s*\;\s*q\s*=\s*(\d+(?:\.\d+)?))?\s*$/i and $types{lc $1} = $2 // 1 for split /,/, $accept // '';
  my @detected = sort { $types{$b} <=> $types{$a} } sort keys %types;

  # Detect extensions from MIME types
  my %reverse;
  my $mapping = $self->mapping;
  for my $ext (sort keys %$mapping) {
    my @types = @{$mapping->{$ext}};
    push @{$reverse{$_}}, $ext for map { s/\;.*$//; lc $_ } @types;
  }

  return [map { @{$reverse{$_} // []} } @detected];
}

sub file_type { $_[0]->type(path($_[1])->extname) }

sub type {
  my ($self, $ext, $type) = @_;
  return $self->mapping->{lc $ext}[0] unless $type;
  $self->mapping->{lc $ext} = ref $type ? $type : [$type];
  return $self;
}

1;

=encoding utf8

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
  json     -> application/json;charset=UTF-8
  mp3      -> audio/mpeg
  mp4      -> video/mp4
  ogg      -> audio/ogg
  ogv      -> video/ogg
  pdf      -> application/pdf
  png      -> image/png
  rss      -> application/rss+xml
  svg      -> image/svg+xml
  ttf      -> font/ttf
  txt      -> text/plain;charset=UTF-8
  webm     -> video/webm
  woff     -> font/woff
  woff2    -> font/woff2
  xml      -> application/xml,text/xml
  zip      -> application/zip

The most common ones are already defined.

=head1 ATTRIBUTES

L<Mojolicious::Types> implements the following attributes.

=head2 mapping

  my $mapping = $types->mapping;
  $types      = $types->mapping({png => ['image/png']});

MIME type mapping.

=head1 METHODS

L<Mojolicious::Types> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 content_type

  $types->content_type(Mojolicious::Controller->new, {ext => 'json'});

Detect MIME type for L<Mojolicious::Controller> object unless a C<Content-Type> response header has already been set,
defaults to using C<application/octet-stream> if no better alternative could be found. These options are currently
available:

=over 2

=item ext

  ext => 'json'

File extension to get MIME type for.

=item file

  file => 'foo/bar.png'

File path to get MIME type for.

=back

=head2 detect

  my $exts = $types->detect('text/html, application/json;q=9');

Detect file extensions from C<Accept> header value.

  # List detected extensions prioritized
  say for @{$types->detect('application/json, text/xml;q=0.1', 1)};

=head2 file_type

  my $type = $types->file_type('foo/bar.png');

Get MIME type for file path.

=head2 type

  my $type = $types->type('png');
  $types   = $types->type(png => 'image/png');
  $types   = $types->type(json => ['application/json', 'text/x-json']);

Get or set MIME types for file extension, alternatives are only used for detection.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
