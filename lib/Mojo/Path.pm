package Mojo::Path;
use Mojo::Base -base;
use overload
  'bool'   => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

use Mojo::Util qw(decode encode url_escape url_unescape);

has [qw(leading_slash trailing_slash)];

sub new { shift->SUPER::new->parse(@_) }

sub canonicalize {
  my $self = shift;

  # Resolve path
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

    # Part
    push @parts, $part;
  }
  $self->trailing_slash(undef) unless @parts;

  return $self->parts(\@parts);
}

sub clone {
  my $self = shift;

  my $clone = Mojo::Path->new;
  $clone->{string} = $self->{string};
  $clone->leading_slash($self->leading_slash);
  $clone->trailing_slash($self->trailing_slash);

  return $clone;
}

sub contains {
  my ($self, $path) = @_;

  my $parts = $self->new($path)->parts;
  for my $part (@{$self->parts}) {
    return 1 unless defined(my $try = shift @$parts);
    return undef unless $part eq $try;
  }

  return !@$parts;
}

sub merge {
  my ($self, $path) = @_;

  # Replace
  return $self->parse($path) if $path =~ m!^/!;

  # Merge
  my $parts = $self->parts;
  pop @$parts unless $self->trailing_slash;
  $path = $self->new($path);
  $self->parts([@$parts, @{$path->parts}]);
  return $self->trailing_slash($path->trailing_slash);
}

sub normalize {
  my $self = shift;
  $self->{string} = _parts_to_string(_string_to_parts($self->{string}));
  return $self;
}

sub parse {
  my ($self, $path) = @_;

  $path //= '';
  $self->leading_slash($path  =~ s!^(?:%2F|/)!!i ? 1 : undef);
  $self->trailing_slash($path =~ s!(?:%2F|/)$!!i ? 1 : undef);
  $self->{string} = $path;

  return $self;
}

sub parts {
  my ($self, $parts) = @_;
  return [_string_to_parts($self->{string})] unless $parts;
  $self->{string} = _parts_to_string(@$parts);
  return $self;
}

sub to_abs_string {
  my $self = shift;
  return $self->leading_slash ? "$self" : "/$self";
}

sub to_string {
  my $self = shift;

  my $path = url_escape encode('UTF-8', $self->{string}),
    '^A-Za-z0-9\-._~!$&\'()*+,;=%:@/';
  $path = "/$path" if $self->leading_slash;
  $path = "$path/" if $self->trailing_slash;

  return $path;
}

sub _parts_to_string {
  my $chars = '^A-Za-z0-9\-._~!$&\'()*+,;=:@';
  return join '/', map { url_escape(encode('UTF-8', $_), $chars) } @_;
}

sub _string_to_parts {
  my $path = url_unescape shift;
  $path = decode('UTF-8', $path) // $path;
  return split '/', $path, -1;
}

1;

=head1 NAME

Mojo::Path - Path

=head1 SYNOPSIS

  use Mojo::Path;

  my $path = Mojo::Path->new('/foo%2Fbar%3B/../baz.html');
  $path->canonicalize;
  say "$path";

=head1 DESCRIPTION

L<Mojo::Path> is a container for URL paths.

=head1 ATTRIBUTES

L<Mojo::Path> implements the following attributes.

=head2 C<leading_slash>

  my $leading_slash = $path->leading_slash;
  $path             = $path->leading_slash(1);

Path has a leading slash.

=head2 C<trailing_slash>

  my $trailing_slash = $path->trailing_slash;
  $path              = $path->trailing_slash(1);

Path has a trailing slash.

=head1 METHODS

L<Mojo::Path> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $path = Mojo::Path->new;
  my $path = Mojo::Path->new('/foo%2Fbar%3B/baz.html');

Construct a new L<Mojo::Path> object.

=head2 C<canonicalize>

  $path = $path->canonicalize;

Canonicalize path.

  # "/foo/baz"
  Mojo::Path->new('/foo/bar/../baz')->canonicalize;

=head2 C<clone>

  my $clone = $path->clone;

Clone path.

=head2 C<contains>

  my $success = $path->contains('/foo');

Check if path contains given prefix.

  # True
  Mojo::Path->new('/foo/bar')->contains('/');
  Mojo::Path->new('/foo/bar')->contains('/foo');
  Mojo::Path->new('/foo/bar')->contains('/foo/bar');

  # False
  Mojo::Path->new('/foo/bar')->contains('/f');
  Mojo::Path->new('/foo/bar')->contains('/bar');
  Mojo::Path->new('/foo/bar')->contains('/whatever');

=head2 C<merge>

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

=head2 C<normalize>

  $path = $path->normalize;

Normalize path.

=head2 C<parse>

  $path = $path->parse('/foo%2Fbar%3B/baz.html');

Parse path. Note that C<%2F> will be treated as C</> for security reasons.

=head2 C<parts>

  my $parts = $path->parts;
  $path     = $path->parts([qw(foo bar baz)]);

The path parts.

=head2 C<to_abs_string>

  my $string = $path->to_abs_string;

Turn path into an absolute string.

=head2 C<to_string>

  my $string = $path->to_string;
  my $string = "$path";

Turn path into a string.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
