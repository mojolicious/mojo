package Mojo::Parameters;
use Mojo::Base -base;
use overload
  '@{}'    => sub { shift->params },
  bool     => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

use Mojo::Util qw(decode encode url_escape url_unescape);

has charset => 'UTF-8';

sub append {
  my $self = shift;

  my $params = $self->params;
  my @pairs = @_ == 1 ? @{shift->params} : @_;
  while (my ($name, $value) = splice @pairs, 0, 2) {

    # Multiple values
    if (ref $value eq 'ARRAY') { push @$params, $name => $_ // '' for @$value }

    # Single value
    else { push @$params, $name => $value }
  }

  return $self;
}

sub clone {
  my $self = shift;

  my $clone = $self->new;
  if   (exists $self->{charset}) { $clone->{charset} = $self->{charset} }
  if   (defined $self->{string}) { $clone->{string}  = $self->{string} }
  else                           { $clone->{params}  = [@{$self->params}] }

  return $clone;
}

sub every_param {
  my ($self, $name) = @_;

  my @values;
  my $params = $self->params;
  for (my $i = 0; $i < @$params; $i += 2) {
    push @values, $params->[$i + 1] if $params->[$i] eq $name;
  }

  return \@values;
}

sub merge {
  my $self = shift;

  my @pairs = @_ == 1 ? @{shift->params} : @_;
  while (my ($name, $value) = splice @pairs, 0, 2) {
    defined $value ? $self->param($name => $value) : $self->remove($name);
  }

  return $self;
}

sub new { @_ > 1 ? shift->SUPER::new->parse(@_) : shift->SUPER::new }

sub param {
  my ($self, $name) = (shift, shift);

  # Multiple names
  return map { $self->param($_) } @$name if ref $name eq 'ARRAY';

  # List names
  return sort keys %{$self->to_hash} unless defined $name;

  # Last value
  return $self->every_param($name)->[-1] unless @_;

  # Replace values
  $self->remove($name);
  return $self->append($name => ref $_[0] eq 'ARRAY' ? $_[0] : [@_]);
}

sub params {
  my $self = shift;

  # Replace parameters
  if (@_) {
    $self->{params} = shift;
    delete $self->{string};
    return $self;
  }

  # Parse string
  if (defined(my $str = delete $self->{string})) {
    my $params = $self->{params} = [];
    return $params unless length $str;

    my $charset = $self->charset;
    for my $pair (split '&', $str) {
      next unless $pair =~ /^([^=]+)(?:=(.*))?$/;
      my ($name, $value) = ($1, $2 // '');

      # Replace "+" with whitespace, unescape and decode
      s/\+/ /g for $name, $value;
      $name  = url_unescape $name;
      $name  = decode($charset, $name) // $name if $charset;
      $value = url_unescape $value;
      $value = decode($charset, $value) // $value if $charset;

      push @$params, $name, $value;
    }
  }

  return $self->{params} ||= [];
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

  my $params = $self->params;
  my $i      = 0;
  $params->[$i] eq $name ? splice @$params, $i, 2 : ($i += 2)
    while $i < @$params;

  return $self;
}

sub to_hash {
  my $self = shift;

  my %hash;
  my $params = $self->params;
  for (my $i = 0; $i < @$params; $i += 2) {
    my ($name, $value) = @{$params}[$i, $i + 1];

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

  # String
  my $charset = $self->charset;
  if (defined(my $str = $self->{string})) {
    $str = encode $charset, $str if $charset;
    return url_escape $str, '^A-Za-z0-9\-._~!$&\'()*+,;=%:@/?';
  }

  # Build pairs
  my $params = $self->params;
  return '' unless @$params;
  my @pairs;
  for (my $i = 0; $i < @$params; $i += 2) {
    my ($name, $value) = @{$params}[$i, $i + 1];

    # Escape and replace whitespace with "+"
    $name  = encode $charset,   $name if $charset;
    $name  = url_escape $name,  '^A-Za-z0-9\-._~!$\'()*,:@/?';
    $value = encode $charset,   $value if $charset;
    $value = url_escape $value, '^A-Za-z0-9\-._~!$\'()*,:@/?';
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

L<Mojo::Parameters> is a container for form parameters used by L<Mojo::URL>
and based on L<RFC 3986|http://tools.ietf.org/html/rfc3986> as well as the
L<HTML Living Standard|https://html.spec.whatwg.org>.

=head1 ATTRIBUTES

L<Mojo::Parameters> implements the following attributes.

=head2 charset

  my $charset = $params->charset;
  $params     = $params->charset('UTF-8');

Charset used for encoding and decoding parameters, defaults to C<UTF-8>.

  # Disable encoding and decoding
  $params->charset(undef);

=head1 METHODS

L<Mojo::Parameters> inherits all methods from L<Mojo::Base> and implements the
following new ones.

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

Clone parameters.

=head2 every_param

  my $values = $params->every_param('foo');

Similar to L</"param">, but returns all values sharing the same name as an
array reference. Note that this method will normalize the parameters.

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

=head2 new

  my $params = Mojo::Parameters->new;
  my $params = Mojo::Parameters->new('foo=b%3Bar&baz=23');
  my $params = Mojo::Parameters->new(foo => 'b&ar');
  my $params = Mojo::Parameters->new(foo => ['ba&r', 'baz']);
  my $params = Mojo::Parameters->new(foo => ['bar', 'baz'], bar => 23);

Construct a new L<Mojo::Parameters> object and L</"parse"> parameters if
necessary.

=head2 param

  my @names       = $params->param;
  my $value       = $params->param('foo');
  my ($foo, $bar) = $params->param(['foo', 'bar']);
  $params         = $params->param(foo => 'ba&r');
  $params         = $params->param(foo => qw(ba&r baz));
  $params         = $params->param(foo => ['ba;r', 'baz']);

Access parameter values. If there are multiple values sharing the same name,
and you want to access more than just the last one, you can use
L</"every_param">. Note that this method will normalize the parameters.

=head2 params

  my $array = $params->params;
  $params   = $params->params([foo => 'b&ar', baz => 23]);

Parsed parameters. Note that this method will normalize the parameters.

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

Turn parameters into a hash reference. Note that this method will normalize
the parameters.

  # "baz"
  Mojo::Parameters->new('foo=bar&foo=baz')->to_hash->{foo}[1];

=head2 to_string

  my $str = $params->to_string;

Turn parameters into a string.

=head1 OPERATORS

L<Mojo::Parameters> overloads the following operators.

=head2 array

  my @params = @$params;

Alias for L</"params">. Note that this will normalize the parameters.

  say $params->[0];
  say for @$params;

=head2 bool

  my $bool = !!$params;

Always true.

=head2 stringify

  my $str = "$params";

Alias for L</"to_string">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
