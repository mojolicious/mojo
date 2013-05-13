package Mojo::Path;
use Mojo::Base -base;
use overload
  '@{}'    => sub { shift->parts },
  'bool'   => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

use Mojo::Util qw(decode encode url_escape url_unescape);

has charset => 'UTF-8';

sub new { shift->SUPER::new->parse(@_) }

sub canonicalize {
  my $self = shift;

  my @parts;
  for my $part (@{$self->parts}) {

    # ".."
    if ($part eq '..') {
      (@parts && $parts[-1] ne '..') ? pop @parts : push @parts, '..';
    }

    # Something else than "."
    elsif ($part ne '.' && $part ne '') { push @parts, $part }
  }
  $self->trailing_slash(undef) unless @parts;

  return $self->parts(\@parts);
}

sub clone {
  my $self = shift;

  my $clone = $self->new->charset($self->charset);
  if (my $parts = $self->{parts}) {
    $clone->{$_} = $self->{$_} for qw(leading_slash trailing_slash);
    $clone->{parts} = [@$parts];
  }
  else { $clone->{path} = $self->{path} }

  return $clone;
}

sub contains {
  my ($self, $path) = @_;
  return $path eq '/' || $self->to_route =~ m!^\Q$path\E(?:/|$)!;
}

sub leading_slash { shift->_parse(leading_slash => @_) }

sub merge {
  my ($self, $path) = @_;

  # Replace
  return $self->parse($path) if $path =~ m!^/!;

  # Merge
  pop @{$self->parts} unless $self->trailing_slash;
  $path = $self->new($path);
  push @{$self->parts}, @{$path->parts};
  return $self->trailing_slash($path->trailing_slash);
}

sub parse {
  my $self = shift;
  $self->{path} = shift;
  delete $self->{$_} for qw(leading_slash parts trailing_slash);
  return $self;
}

sub parts { shift->_parse(parts => @_) }

sub to_abs_string {
  my $path = shift->to_string;
  return $path =~ m!^/! ? $path : "/$path";
}

sub to_dir {
  my $clone = shift->clone;
  pop @{$clone->parts} unless $clone->trailing_slash;
  return $clone->trailing_slash(@{$clone->parts} ? 1 : 0);
}

sub to_route {
  my $clone = shift->clone;
  my $route = join '/', @{$clone->parts};
  return "/$route" . ($clone->trailing_slash ? '/' : '');
}

sub to_string {
  my $self = shift;

  # Path
  my $charset = $self->charset;
  if (defined(my $path = $self->{path})) {
    $path = encode $charset, $path if $charset;
    return url_escape $path, '^A-Za-z0-9\-._~!$&\'()*+,;=%:@/';
  }

  # Build path
  my @parts = @{$self->parts};
  @parts = map { encode $charset, $_ } @parts if $charset;
  my $path = join '/',
    map { url_escape $_, '^A-Za-z0-9\-._~!$&\'()*+,;=:@' } @parts;
  $path = "/$path" if $self->leading_slash;
  $path = "$path/" if $self->trailing_slash;
  return $path;
}

sub trailing_slash { shift->_parse(trailing_slash => @_) }

sub _parse {
  my ($self, $name) = (shift, shift);

  unless ($self->{parts}) {
    my $path = url_unescape delete($self->{path}) // '';
    my $charset = $self->charset;
    $path = decode($charset, $path) // $path if $charset;
    $self->{leading_slash}  = $path =~ s!^/!! ? 1 : undef;
    $self->{trailing_slash} = $path =~ s!/$!! ? 1 : undef;
    $self->{parts} = [split '/', $path, -1];
  }

  return $self->{$name} unless @_;
  $self->{$name} = shift;
  return $self;
}

1;

=encoding utf8

=head1 NAME

Mojo::Path - Path

=head1 SYNOPSIS

  use Mojo::Path;

  # Parse
  my $path = Mojo::Path->new('/foo%2Fbar%3B/baz.html');
  say $path->[0];

  # Build
  my $path = Mojo::Path->new('/i/♥');
  push @$path, 'mojolicious';
  say "$path";

=head1 DESCRIPTION

L<Mojo::Path> is a container for paths used by L<Mojo::URL>.

=head1 ATTRIBUTES

L<Mojo::Path> implements the following attributes.

=head2 charset

  my $charset = $path->charset;
  $path       = $path->charset('UTF-8');

Charset used for encoding and decoding, defaults to C<UTF-8>.

  # Disable encoding and decoding
  $path->charset(undef);

=head1 METHODS

L<Mojo::Path> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 new

  my $path = Mojo::Path->new;
  my $path = Mojo::Path->new('/foo%2Fbar%3B/baz.html');

Construct a new L<Mojo::Path> object and C<parse> path if necessary.

=head2 canonicalize

  $path = $path->canonicalize;

Canonicalize path.

  # "/foo/baz"
  Mojo::Path->new('/foo/./bar/../baz')->canonicalize;

=head2 clone

  my $clone = $path->clone;

Clone path.

=head2 contains

  my $success = $path->contains('/i/♥/mojolicious');

Check if path contains given prefix.

  # True
  Mojo::Path->new('/foo/bar')->contains('/');
  Mojo::Path->new('/foo/bar')->contains('/foo');
  Mojo::Path->new('/foo/bar')->contains('/foo/bar');

  # False
  Mojo::Path->new('/foo/bar')->contains('/f');
  Mojo::Path->new('/foo/bar')->contains('/bar');
  Mojo::Path->new('/foo/bar')->contains('/whatever');

=head2 leading_slash

  my $slash = $path->leading_slash;
  $path     = $path->leading_slash(1);

Path has a leading slash. Note that this method will normalize the path and
that C<%2F> will be treated as C</> for security reasons.

=head2 merge

  $path = $path->merge('/foo/bar');
  $path = $path->merge('foo/bar');
  $path = $path->merge(Mojo::Path->new('foo/bar'));

Merge paths. Note that this method will normalize both paths if necessary and
that C<%2F> will be treated as C</> for security reasons.

  # "/baz/yada"
  Mojo::Path->new('/foo/bar')->merge('/baz/yada');

  # "/foo/baz/yada"
  Mojo::Path->new('/foo/bar')->merge('baz/yada');

  # "/foo/bar/baz/yada"
  Mojo::Path->new('/foo/bar/')->merge('baz/yada');

=head2 parse

  $path = $path->parse('/foo%2Fbar%3B/baz.html');

Parse path.

=head2 to_abs_string

  my $str = $path->to_abs_string;

Turn path into an absolute string.

  # "/i/%E2%99%A5/mojolicious"
  Mojo::Path->new('/i/%E2%99%A5/mojolicious')->to_abs_string;
  Mojo::Path->new('i/%E2%99%A5/mojolicious')->to_abs_string;

=head2 parts

  my $parts = $path->parts;
  $path     = $path->parts([qw(foo bar baz)]);

The path parts. Note that this method will normalize the path and that C<%2F>
will be treated as C</> for security reasons.

  # Part with slash
  push @{$path->parts}, 'foo/bar';

=head2 to_dir

  my $dir = $route->to_dir;

Clone path and remove everything after the right-most slash.

  # "/i/%E2%99%A5/"
  Mojo::Path->new('/i/%E2%99%A5/mojolicious')->to_dir->to_abs_string;

  # "i/%E2%99%A5/"
  Mojo::Path->new('i/%E2%99%A5/mojolicious')->to_dir->to_abs_string;

=head2 to_route

  my $route = $path->to_route;

Turn path into a route.

  # "/i/♥/mojolicious"
  Mojo::Path->new('/i/%E2%99%A5/mojolicious')->to_route;
  Mojo::Path->new('i/%E2%99%A5/mojolicious')->to_route;

=head2 to_string

  my $str = $path->to_string;
  my $str = "$path";

Turn path into a string.

  # "/i/%E2%99%A5/mojolicious"
  Mojo::Path->new('/i/%E2%99%A5/mojolicious')->to_string;

  # "i/%E2%99%A5/mojolicious"
  Mojo::Path->new('i/%E2%99%A5/mojolicious')->to_string;

=head2 trailing_slash

  my $slash = $path->trailing_slash;
  $path     = $path->trailing_slash(1);

Path has a trailing slash. Note that this method will normalize the path and
that C<%2F> will be treated as C</> for security reasons.

=head1 PATH PARTS

Direct array reference access to path parts is also possible. Note that this
will normalize the path and that C<%2F> will be treated as C</> for security
reasons.

  say $path->[0];
  say for @$path;

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
