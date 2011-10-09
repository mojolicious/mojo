package Mojo::Path;
use Mojo::Base -base;
use overload
  'bool'   => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

use Mojo::Util qw/url_escape url_unescape/;
use Mojo::URL;

has [qw/leading_slash trailing_slash/];
has parts => sub { [] };

sub new {
  my $self = shift->SUPER::new();
  $self->parse(@_);
  return $self;
}

# DEPRECATED in Smiling Face With Sunglasses!
sub append {
  warn <<EOF;
Mojo::Path->append is DEPRECATED in favor of using Mojo::Path->parts
directly!!!
EOF
  my $self = shift;
  push @{$self->parts}, @_;
  return $self;
}

sub canonicalize {
  my $self = shift;

  # Resolve path
  my @path;
  for my $part (@{$self->parts}) {

    # ".."
    if ($part eq '..') {

      # Leading '..' can't be resolved
      unless (@path && $path[-1] ne '..') { push @path, '..' }

      # Uplevel
      else { pop @path }
      next;
    }

    # "."
    next if $part eq '.';

    push @path, $part;
  }
  $self->parts(\@path);

  return $self;
}

# "Homer, the plant called.
#  They said if you don't show up tomorrow don't bother showing up on Monday.
#  Woo-hoo. Four-day weekend."
sub clone {
  my $self = shift;

  my $clone = Mojo::Path->new;
  $clone->parts([@{$self->parts}]);
  $clone->leading_slash($self->leading_slash);
  $clone->trailing_slash($self->trailing_slash);

  return $clone;
}

sub contains {
  my ($self, $path) = @_;

  my $parts = $self->new($path)->parts;
  for my $part (@{$self->parts}) {
    return 1 unless defined(my $try = shift @$parts);
    return unless $part eq $try;
  }

  return @$parts ? undef : 1;
}

sub parse {
  my ($self, $path) = @_;
  $path //= '';

  # Leading and trailing slash
  $path =~ /^\// ? $self->leading_slash(1)  : $self->leading_slash(undef);
  $path =~ /\/$/ ? $self->trailing_slash(1) : $self->trailing_slash(undef);

  # Parse
  url_unescape $path;
  utf8::decode $path;
  my @parts;
  for my $part (split '/', $path) {

    # Empty parts before the first are garbage
    next unless length $part or @parts;
    push @parts, $part;
  }
  $self->parts(\@parts);

  return $self;
}

sub to_abs_string {
  my $self = shift;
  return $self->to_string if $self->leading_slash;
  return '/' . $self->to_string;
}

sub to_string {
  my $self = shift;

  # Escape
  my @path;
  for my $part (@{$self->parts}) {
    my $escaped = $part;
    utf8::encode $escaped;
    url_escape $escaped, "$Mojo::URL::UNRESERVED$Mojo::URL::SUBDELIM\:\@";
    push @path, $escaped;
  }

  # Format
  my $path = join '/', @path;
  $path = "/$path" if $self->leading_slash;
  $path = "$path/" if @path && $self->trailing_slash;

  return $path;
}

1;
__END__

=head1 NAME

Mojo::Path - Path

=head1 SYNOPSIS

  use Mojo::Path;

  my $path = Mojo::Path->new('/foo/bar%3B/baz.html');
  shift @{$path->parts};
  say $path;

=head1 DESCRIPTION

L<Mojo::Path> is a container for URL paths.

=head1 ATTRIBUTES

L<Mojo::Path> implements the following attributes.

=head2 C<leading_slash>

  my $leading_slash = $path->leading_slash;
  $path             = $path->leading_slash(1);

Path has a leading slash.

=head2 C<parts>

  my $parts = $path->parts;
  $path     = $path->parts([qw/foo bar baz/]);

The path parts.

=head2 C<trailing_slash>

  my $trailing_slash = $path->trailing_slash;
  $path              = $path->trailing_slash(1);

Path has a trailing slash.

=head1 METHODS

L<Mojo::Path> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $path = Mojo::Path->new;
  my $path = Mojo::Path->new('/foo/bar%3B/baz.html');

Construct a new L<Mojo::Path> object.

=head2 C<canonicalize>

  $path = $path->canonicalize;

Canonicalize path.

=head2 C<clone>

  my $clone = $path->clone;

Clone path.

=head2 C<contains>

  my $success = $path->contains('/foo');

Check if path contains given prefix.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<parse>

  $path = $path->parse('/foo/bar%3B/baz.html');

Parse path.

=head2 C<to_abs_string>

  my $string = $path->to_abs_string;

Turn path into an absolute string.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<to_string>

  my $string = $path->to_string;

Turn path into a string.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
