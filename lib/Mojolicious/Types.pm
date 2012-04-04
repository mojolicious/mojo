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
  my ($self, $accept, $all) = @_;
  $accept ||= '';

  # First MIME type only
  return [] unless $all || $accept =~ /^[^,]+?(?:\;[^,]*)*$/;

  # Detect extensions from MIME type
  my %results;
  my $reverse = $self->_reverse;
  for my $type (split /,/, $accept) {
    next unless $type =~ /^\s*([^;]+?)\s*(?:\;.*)*?$/;
    next unless my $exts = $reverse->{lc $1};
    my $quality = $type =~ /\;\s*q=(\d+(?:\.\d+)?)/ ? $1 : 1;
    $results{$_} = $quality for @$exts;
  }

  return [sort { $results{$b} <=> $results{$a} } sort keys %results];
}

sub type {
  my ($self, $ext, $type) = @_;
  return $self->types->{$ext || ''} unless $type;
  $self->types->{$ext} = $type;
  return $self;
}

sub _reverse {
  my $self = shift;

  # Index types
  unless ($self->{reverse}) {
    my $types = $self->types;
    for my $ext (keys %$types) {
      my $type = lc $types->{$ext};
      $type =~ s/\;.*$//;
      push @{$self->{reverse}->{$type}}, $ext;
    }
  }

  return $self->{reverse};
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

  my $first = $types->detect('application/json;q=9');
  my $all   = $types->detect('application/json;q=9,text/plain', 1);

Detect file extensions from C<Accept> header value, detection of more than
one MIME type is disabled by default.

=head2 C<type>

  my $type = $types->type('png');
  $types   = $types->type(png => 'image/png');

Get or set MIME type for file extension.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
