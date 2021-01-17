package Mojo::Parameters;
use Mojo::Base -base;
use overload '@{}' => sub { shift->pairs }, bool => sub {1}, '""' => sub { shift->to_string }, fallback => 1;

use Mojo::Util qw(decode encode url_escape url_unescape);

has charset => 'UTF-8';

sub append {
  my $self = shift;

  my $old = $self->pairs;
  my @new = @_ == 1 ? @{shift->pairs} : @_;
  while (my ($name, $value) = splice @new, 0, 2) {

    # Multiple values
    if (ref $value eq 'ARRAY') { push @$old, $name => $_ // '' for @$value }

    # Single value
    elsif (defined $value) { push @$old, $name => $value }
  }

  return $self;
}

sub clone {
  my $self = shift;

  my $clone = $self->new;
  if   (exists $self->{charset}) { $clone->{charset} = $self->{charset} }
  if   (defined $self->{string}) { $clone->{string}  = $self->{string} }
  else                           { $clone->{pairs}   = [@{$self->pairs}] }

  return $clone;
}

sub every_param {
  my ($self, $name) = @_;

  my @values;
  my $pairs = $self->pairs;
  for (my $i = 0; $i < @$pairs; $i += 2) {
    push @values, $pairs->[$i + 1] if $pairs->[$i] eq $name;
  }

  return \@values;
}

sub merge {
  my $self = shift;

  my $merge = @_ == 1 ? shift->to_hash : {@_};
  for my $name (sort keys %$merge) {
    my $value = $merge->{$name};
    defined $value ? $self->param($name => $value) : $self->remove($name);
  }

  return $self;
}

sub names { [sort keys %{shift->to_hash}] }

sub new { @_ > 1 ? shift->SUPER::new->parse(@_) : shift->SUPER::new }

sub pairs {
  my $self = shift;

  # Replace parameters
  if (@_) {
    $self->{pairs} = shift;
    delete $self->{string};
    return $self;
  }

  # Parse string
  if (defined(my $str = delete $self->{string})) {
    my $pairs = $self->{pairs} = [];
    return $pairs unless length $str;

    my $charset = $self->charset;
    for my $pair (split /&/, $str) {
      next unless $pair =~ /^([^=]+)(?:=(.*))?$/;
      my ($name, $value) = ($1, $2 // '');

      # Replace "+" with whitespace, unescape and decode
      s/\+/ /g for $name, $value;
      $name  = url_unescape $name;
      $name  = decode($charset, $name) // $name if $charset;
      $value = url_unescape $value;
      $value = decode($charset, $value) // $value if $charset;

      push @$pairs, $name, $value;
    }
  }

  return $self->{pairs} //= [];
}

sub param {
  my ($self, $name) = (shift, shift);
  return $self->every_param($name)->[-1] unless @_;
  $self->remove($name);
  return $self->append($name => ref $_[0] eq 'ARRAY' ? $_[0] : [@_]);
}

sub parse {
  my $self = shift;

  # Pairs
  return $self->append(@_) if @_ > 1;

  # String
  $self->{string} = shift;
  return $self;
}

sub remove {
  my ($self, $name) = @_;
  my $pairs = $self->pairs;
  my $i     = 0;
  $pairs->[$i] eq $name ? splice @$pairs, $i, 2 : ($i += 2) while $i < @$pairs;
  return $self;
}

sub to_hash {
  my $self = shift;

  my %hash;
  my $pairs = $self->pairs;
  for (my $i = 0; $i < @$pairs; $i += 2) {
    my ($name, $value) = @{$pairs}[$i, $i + 1];

    # Array
    if (exists $hash{$name}) {
      $hash{$name} = [$hash{$name}] if ref $hash{$name} ne 'ARRAY';
      push @{$hash{$name}}, $value;
    }

    # String
    else { $hash{$name} = $value }
  }

  return \%hash;
}

sub to_string {
  my $self = shift;

  # String (RFC 3986)
  my $charset = $self->charset;
  if (defined(my $str = $self->{string})) {
    $str = encode $charset, $str if $charset;
    return url_escape $str, '^A-Za-z0-9\-._~%!$&\'()*+,;=:@/?';
  }

  # Build pairs (HTML Living Standard)
  my $pairs = $self->pairs;
  return '' unless @$pairs;
  my @pairs;
  for (my $i = 0; $i < @$pairs; $i += 2) {
    my ($name, $value) = @{$pairs}[$i, $i + 1];

    # Escape and replace whitespace with "+"
    $name  = encode $charset,   $name if $charset;
    $name  = url_escape $name,  '^*\-.0-9A-Z_a-z';
    $value = encode $charset,   $value if $charset;
    $value = url_escape $value, '^*\-.0-9A-Z_a-z';
    s/\%20/\+/g for $name, $value;

    push @pairs, "$name=$value";
  }

  return join '&', @pairs;
}

1;

=encoding utf8

=head1 NAME

Mojo::Parameters - Parameters

=head1 SYNOPSIS

  use Mojo::Parameters;

  # Parse
  my $params = Mojo::Parameters->new('foo=bar&baz=23');
  say $params->param('baz');

  # Build
  my $params = Mojo::Parameters->new(foo => 'bar', baz => 23);
  push @$params, i => '♥ mojolicious';
  say "$params";

=head1 DESCRIPTION

L<Mojo::Parameters> is a container for form parameters used by L<Mojo::URL>, based on L<RFC
3986|https://tools.ietf.org/html/rfc3986> and the L<HTML Living Standard|https://html.spec.whatwg.org>.

=head1 ATTRIBUTES

L<Mojo::Parameters> implements the following attributes.

=head2 charset

  my $charset = $params->charset;
  $params     = $params->charset('UTF-8');

Charset used for encoding and decoding parameters, defaults to C<UTF-8>.

  # Disable encoding and decoding
  $params->charset(undef);

=head1 METHODS

L<Mojo::Parameters> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 append

  $params = $params->append(foo => 'ba&r');
  $params = $params->append(foo => ['ba&r', 'baz']);
  $params = $params->append(foo => ['bar', 'baz'], bar => 23);
  $params = $params->append(Mojo::Parameters->new);

Append parameters. Note that this method will normalize the parameters.

  # "foo=bar&foo=baz"
  Mojo::Parameters->new('foo=bar')->append(Mojo::Parameters->new('foo=baz'));

  # "foo=bar&foo=baz"
  Mojo::Parameters->new('foo=bar')->append(foo => 'baz');

  # "foo=bar&foo=baz&foo=yada"
  Mojo::Parameters->new('foo=bar')->append(foo => ['baz', 'yada']);

  # "foo=bar&foo=baz&foo=yada&bar=23"
  Mojo::Parameters->new('foo=bar')->append(foo => ['baz', 'yada'], bar => 23);

=head2 clone

  my $params2 = $params->clone;

Return a new L<Mojo::Parameters> object cloned from these parameters.

=head2 every_param

  my $values = $params->every_param('foo');

Similar to L</"param">, but returns all values sharing the same name as an array reference. Note that this method will
normalize the parameters.

  # Get first value
  say $params->every_param('foo')->[0];

=head2 merge

  $params = $params->merge(foo => 'ba&r');
  $params = $params->merge(foo => ['ba&r', 'baz']);
  $params = $params->merge(foo => ['bar', 'baz'], bar => 23);
  $params = $params->merge(Mojo::Parameters->new);

Merge parameters. Note that this method will normalize the parameters.

  # "foo=baz"
  Mojo::Parameters->new('foo=bar')->merge(Mojo::Parameters->new('foo=baz'));

  # "yada=yada&foo=baz"
  Mojo::Parameters->new('foo=bar&yada=yada')->merge(foo => 'baz');

  # "yada=yada"
  Mojo::Parameters->new('foo=bar&yada=yada')->merge(foo => undef);

=head2 names

  my $names = $params->names;

Return an array reference with all parameter names.

  # Names of all parameters
  say for @{$params->names};

=head2 new

  my $params = Mojo::Parameters->new;
  my $params = Mojo::Parameters->new('foo=b%3Bar&baz=23');
  my $params = Mojo::Parameters->new(foo => 'b&ar');
  my $params = Mojo::Parameters->new(foo => ['ba&r', 'baz']);
  my $params = Mojo::Parameters->new(foo => ['bar', 'baz'], bar => 23);

Construct a new L<Mojo::Parameters> object and L</"parse"> parameters if necessary.

=head2 pairs

  my $array = $params->pairs;
  $params   = $params->pairs([foo => 'b&ar', baz => 23]);

Parsed parameter pairs. Note that this method will normalize the parameters.

  # Remove all parameters
  $params->pairs([]);

=head2 param

  my $value = $params->param('foo');
  $params   = $params->param(foo => 'ba&r');
  $params   = $params->param(foo => qw(ba&r baz));
  $params   = $params->param(foo => ['ba;r', 'baz']);

Access parameter values. If there are multiple values sharing the same name, and you want to access more than just the
last one, you can use L</"every_param">. Note that this method will normalize the parameters.

=head2 parse

  $params = $params->parse('foo=b%3Bar&baz=23');

Parse parameters.

=head2 remove

  $params = $params->remove('foo');

Remove parameters. Note that this method will normalize the parameters.

  # "bar=yada"
  Mojo::Parameters->new('foo=bar&foo=baz&bar=yada')->remove('foo');

=head2 to_hash

  my $hash = $params->to_hash;

Turn parameters into a hash reference. Note that this method will normalize the parameters.

  # "baz"
  Mojo::Parameters->new('foo=bar&foo=baz')->to_hash->{foo}[1];

=head2 to_string

  my $str = $params->to_string;

Turn parameters into a string.

  # "foo=bar&baz=23"
  Mojo::Parameters->new->pairs([foo => 'bar', baz => 23])->to_string;

=head1 OPERATORS

L<Mojo::Parameters> overloads the following operators.

=head2 array

  my @pairs = @$params;

Alias for L</"pairs">. Note that this will normalize the parameters.

  say $params->[0];
  say for @$params;

=head2 bool

  my $bool = !!$params;

Always true.

=head2 stringify

  my $str = "$params";

Alias for L</"to_string">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
