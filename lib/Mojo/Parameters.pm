package Mojo::Parameters;
use Mojo::Base -base;
use overload
  '@{}'    => sub { shift->params },
  'bool'   => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

use Mojo::Util qw(decode encode url_escape url_unescape);

has charset => 'UTF-8';

sub new { shift->SUPER::new->parse(@_) }

sub append {
  my ($self, @pairs) = @_;

  my $params = $self->params;
  for (my $i = 0; $i < @pairs; $i += 2) {
    my $key   = $pairs[$i]     // '';
    my $value = $pairs[$i + 1] // '';

    # Single value
    if (ref $value ne 'ARRAY') { push @$params, $key => $value }

    # Multiple values
    else { push @$params, $key => (defined $_ ? "$_" : '') for @$value }
  }

  return $self;
}

sub clone {
  my $self = shift;

  my $clone = $self->new->charset($self->charset);
  if (defined $self->{string}) { $clone->{string} = $self->{string} }
  else                         { $clone->params([@{$self->params}]) }

  return $clone;
}

sub merge {
  my $self = shift;
  push @{$self->params}, @{$_->params} for @_;
  return $self;
}

sub param {
  my ($self, $name) = (shift, shift);

  # List names
  return sort keys %{$self->to_hash} unless $name;

  # Replace values
  $self->remove($name) if defined $_[0];
  $self->append($name, $_) for @_;

  # List values
  my @values;
  my $params = $self->params;
  for (my $i = 0; $i < @$params; $i += 2) {
    push @values, $params->[$i + 1] if $params->[$i] eq $name;
  }

  return wantarray ? @values : $values[0];
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

    # W3C suggests to also accept ";" as a separator
    my $charset = $self->charset;
    for my $pair (split /&|;/, $str) {
      next unless $pair =~ /^([^=]+)(?:=(.*))?$/;
      my $name = $1;
      my $value = $2 // '';

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
  if (@_ > 1) { $self->append(@_) }

  # String
  else { $self->{string} = $_[0] }

  return $self;
}

sub remove {
  my $self = shift;
  my $name = shift // '';

  my $params = $self->params;
  for (my $i = 0; $i < @$params;) {
    if ($params->[$i] eq $name) { splice @$params, $i, 2 }
    else                        { $i += 2 }
  }

  return $self->params($params);
}

sub to_hash {
  my $self = shift;

  my $params = $self->params;
  my %hash;
  for (my $i = 0; $i < @$params; $i += 2) {
    my ($name, $value) = @{$params}[$i, $i + 1];

    # Array
    if (exists $hash{$name}) {
      $hash{$name} = [$hash{$name}] unless ref $hash{$name} eq 'ARRAY';
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

L<Mojo::Parameters> is a container for form parameters used by L<Mojo::URL>.

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

=head2 new

  my $params = Mojo::Parameters->new;
  my $params = Mojo::Parameters->new('foo=b%3Bar&baz=23');
  my $params = Mojo::Parameters->new(foo => 'b;ar');
  my $params = Mojo::Parameters->new(foo => ['ba;r', 'b;az']);
  my $params = Mojo::Parameters->new(foo => ['ba;r', 'b;az'], bar => 23);

Construct a new L<Mojo::Parameters> object and C<parse> parameters if
necessary.

=head2 append

  $params = $params->append(foo => 'ba;r');
  $params = $params->append(foo => ['ba;r', 'b;az']);
  $params = $params->append(foo => ['ba;r', 'b;az'], bar => 23);

Append parameters. Note that this method will normalize the parameters.

  # "foo=bar&foo=baz"
  Mojo::Parameters->new('foo=bar')->append(foo => 'baz');

  # "foo=bar&foo=baz&foo=yada"
  Mojo::Parameters->new('foo=bar')->append(foo => ['baz', 'yada']);

  # "foo=bar&foo=baz&foo=yada&bar=23"
  Mojo::Parameters->new('foo=bar')->append(foo => ['baz', 'yada'], bar => 23);

=head2 clone

  my $params2 = $params->clone;

Clone parameters.

=head2 merge

  $params = $params->merge(Mojo::Parameters->new(foo => 'b;ar', baz => 23));

Merge L<Mojo::Parameters> objects. Note that this method will normalize the
parameters.

=head2 param

  my @names = $params->param;
  my $foo   = $params->param('foo');
  my @foo   = $params->param('foo');
  my $foo   = $params->param(foo => 'ba;r');
  my @foo   = $params->param(foo => qw(ba;r ba;z));

Check and replace parameter value. Be aware that if you request a parameter by
name in scalar context, you will receive only the I<first> value for that
parameter, if there are multiple values for that name. In list context you
will receive I<all> of the values for that name. Note that this method will
normalize the parameters.

=head2 params

  my $array = $params->params;
  $params   = $params->params([foo => 'b;ar', baz => 23]);

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
  my $str = "$params";

Turn parameters into a string.

=head1 PARAMETERS

Direct array reference access to the parsed parameters is also possible. Note
that this will normalize the parameters.

  say $params->[0];
  say for @$params;

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
