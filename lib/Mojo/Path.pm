package Mojo::Path;
use Mojo::Base -base;
use overload
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
      unless (@parts && $parts[-1] ne '..') { push @parts, '..' }
      else                                  { pop @parts }
      next;
    }

    # "."
    next if grep { $_ eq $part } '.', '';

    push @parts, $part;
  }
  $self->trailing_slash(undef) unless @parts;

  return $self->parts(\@parts);
}

sub clone {
  my $self = shift;

  my $clone = Mojo::Path->new->charset($self->charset);
  if (my $parts = $self->{parts}) {
    $clone->{$_} = $self->{$_} for qw(leading_slash trailing_slash);
    $clone->{parts} = [@$parts];
  }
  else { $clone->{path} = $self->{path} }

  return $clone;
}

sub contains {
  my ($self, $path) = @_;
  return $path eq '/' || $self->to_route =~ m!^$path(?:/|$)!;
}

sub leading_slash { shift->_lazy(leading_slash => @_) }

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

sub parts { shift->_lazy(parts => @_) }

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

sub trailing_slash { shift->_lazy(trailing_slash => @_) }

sub _lazy {
  my ($self, $name) = (shift, shift);
  $self->_parse unless $self->{parts};
  return $self->{$name} unless @_;
  $self->{$name} = shift;
  return $self;
}

sub _parse {
  my $self = shift;

  my $path = url_unescape delete($self->{path}) // '';
  my $charset = $self->charset;
  $path = decode($charset, $path) // $path if $charset;
  $self->{leading_slash}  = $path =~ s!^/!! ? 1 : undef;
  $self->{trailing_slash} = $path =~ s!/$!! ? 1 : undef;
  $self->{parts} = [split '/', $path, -1];
}

1;

=encoding utf8

=head1 NAME

Mojo::Path - Path

=head1 SYNOPSIS

  use Mojo::Path;

  my $path = Mojo::Path->new('/foo%2Fbar%3B/baz.html');
  shift @{$path->parts};
  say "$path";

=head1 DESCRIPTION

L<Mojo::Path> is a container for URL paths. Note that C<%2F> will be treated
as C</> for security reasons if the path has to be normalized for an
operation.

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

Construct a new L<Mojo::Path> object.

=head2 canonicalize

  $path = $path->canonicalize;

Canonicalize path.

  # "/foo/baz"
  Mojo::Path->new('/foo/bar/../baz')->canonicalize;

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

Path has a leading slash.

=head2 merge

  $path = $path->merge('/foo/bar');
  $path = $path->merge('foo/bar');
  $path = $path->merge(Mojo::Path->new('foo/bar'));

Merge paths.

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

  my $string = $path->to_abs_string;

Turn path into an absolute string.

  # "/i/%E2%99%A5/mojolicious"
  Mojo::Path->new('i/%E2%99%A5/mojolicious')->to_abs_string;

=head2 parts

  my $parts = $path->parts;
  $path     = $path->parts([qw(foo bar baz)]);

The path parts.

  # Part with slash
  push @{$path->parts}, 'foo/bar';

=head2 to_dir

  my $dir = $route->to_dir;

Clone path and remove everything after the right-most slash.

  # "/i/%E2%99%A5/"
  Mojo::Path->new('i/%E2%99%A5/mojolicious')->to_dir->to_abs_string;

=head2 to_route

  my $route = $path->to_route;

Turn path into a route.

  # "/i/♥/mojolicious"
  Mojo::Path->new('i/%E2%99%A5/mojolicious')->to_route;

=head2 to_string

  my $string = $path->to_string;
  my $string = "$path";

Turn path into a string.

  # "i/%E2%99%A5/mojolicious"
  Mojo::Path->new('i/%E2%99%A5/mojolicious')->to_string;

=head2 trailing_slash

  my $slash = $path->trailing_slash;
  $path     = $path->trailing_slash(1);

Path has a trailing slash.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
