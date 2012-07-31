package Mojo::Parameters;
use Mojo::Base -base;
use overload
  'bool'   => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

use Mojo::Util qw(decode encode url_escape url_unescape);

has charset        => 'UTF-8';
has pair_separator => '&';

# "Yeah, Moe, that team sure did suck last night. They just plain sucked!
#  I've seen teams suck before,
#  but they were the suckiest bunch of sucks that ever sucked!
#  HOMER!
#  I gotta go Moe my damn weiner kids are listening."
sub new {
  my $self = shift->SUPER::new;

  # Pairs
  if (@_ > 1) { $self->append(@_) }

  # String
  else { $self->{string} = $_[0] }

  return $self;
}

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
  my $self  = shift;
  my $clone = Mojo::Parameters->new;
  $clone->pair_separator($self->pair_separator);
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
  my ($self, $params) = @_;
  if ($params) { $self->{params} = $params and return $self }
  elsif (defined $self->{string}) { $self->parse }
  return $self->{params} ||= [];
}

sub parse {
  my $self = shift;
  my $string = shift // $self->{string};

  # Clear
  delete $self->params([])->{string};

  # Detect pair separator for reconstruction
  return $self unless length($string // '');
  $self->pair_separator(';') if $string =~ /;/ && $string !~ /\&/;

  # W3C suggests to also accept ";" as a separator
  my $charset = $self->charset;
  for my $pair (split /[\&\;]+/, $string) {

    # Parse
    $pair =~ /^([^=]*)(?:=(.*))?$/;
    my $name  = $1 // '';
    my $value = $2 // '';

    # Replace "+" with whitespace
    s/\+/\ /g for $name, $value;

    # Unescape
    $name  = url_unescape $name;
    $name  = decode($charset, $name) // $name if $charset;
    $value = url_unescape $value;
    $value = decode($charset, $value) // $value if $charset;

    push @{$self->params}, $name, $value;
  }

  return $self;
}

# "Don't kid yourself, Jimmy. If a cow ever got the chance,
#  he'd eat you and everyone you care about!"
sub remove {
  my $self = shift;
  my $name = shift // '';

  # Remove
  my $params = $self->params;
  for (my $i = 0; $i < @$params;) {
    if ($params->[$i] eq $name) { splice @$params, $i, 2 }
    else                        { $i += 2 }
  }

  return $self->params($params);
}

sub to_hash {
  my $self = shift;

  # Format
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
  if (defined(my $string = $self->{string})) {
    $string = encode $charset, $string if $charset;
    return url_escape $string, '^A-Za-z0-9\-._~!$&\'()*+,;=%:@/?';
  }

  # Build pairs
  my $params = $self->params;
  return '' unless @$params;
  my @pairs;
  for (my $i = 0; $i < @$params; $i += 2) {
    my ($name, $value) = @{$params}[$i, $i + 1];

    # Escape and replace whitespace with "+"
    $name = encode $charset, $name if $charset;
    $name = url_escape $name, '^A-Za-z0-9\-._~!$\'()*,%:@/?';
    $name =~ s/\%20/\+/g;
    if ($value) {
      $value = encode $charset, $value if $charset;
      $value = url_escape $value, '^A-Za-z0-9\-._~!$\'()*,%:@/?';
      $value =~ s/\%20/\+/g;
    }

    push @pairs, defined $value ? "$name=$value" : $name;
  }

  # Concatenate pairs
  return join $self->pair_separator, @pairs;
}

1;

=head1 NAME

Mojo::Parameters - Parameters

=head1 SYNOPSIS

  use Mojo::Parameters;

  # Parse
  my $p = Mojo::Parameters->new('foo=bar&baz=23');
  say $p->param('baz');

  # Build
  my $p = Mojo::Parameters->new(foo => 'bar', baz => 23);
  say "$p";

=head1 DESCRIPTION

L<Mojo::Parameters> is a container for form parameters.

=head1 ATTRIBUTES

L<Mojo::Parameters> implements the following attributes.

=head2 C<charset>

  my $charset = $p->charset;
  $p          = $p->charset('UTF-8');

Charset used for decoding parameters, defaults to C<UTF-8>.

=head2 C<pair_separator>

  my $separator = $p->pair_separator;
  $p            = $p->pair_separator(';');

Separator for parameter pairs, defaults to C<&>.

=head1 METHODS

L<Mojo::Parameters> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $p = Mojo::Parameters->new;
  my $p = Mojo::Parameters->new('foo=b%3Bar&baz=23');
  my $p = Mojo::Parameters->new(foo => 'b;ar');
  my $p = Mojo::Parameters->new(foo => ['ba;r', 'b;az']);
  my $p = Mojo::Parameters->new(foo => ['ba;r', 'b;az'], bar => 23);

Construct a new L<Mojo::Parameters> object.

=head2 C<append>

  $p = $p->append(foo => 'ba;r');
  $p = $p->append(foo => ['ba;r', 'b;az']);
  $p = $p->append(foo => ['ba;r', 'b;az'], bar => 23);

Append parameters.

  # "foo=bar&foo=baz"
  Mojo::Parameters->new('foo=bar')->append(foo => 'baz');

  # "foo=bar&foo=baz&foo=yada"
  Mojo::Parameters->new('foo=bar')->append(foo => ['baz', 'yada']);

  # "foo=bar&foo=baz&foo=yada&bar=23"
  Mojo::Parameters->new('foo=bar')->append(foo => ['baz', 'yada'], bar => 23);

=head2 C<clone>

  my $p2 = $p->clone;

Clone parameters.

=head2 C<merge>

  $p = $p->merge(Mojo::Parameters->new(foo => 'b;ar', baz => 23));

Merge L<Mojo::Parameters> objects.

=head2 C<param>

  my @names = $p->param;
  my $foo   = $p->param('foo');
  my @foo   = $p->param('foo');
  my $foo   = $p->param(foo => 'ba;r');
  my @foo   = $p->param(foo => qw(ba;r ba;z));

Check and replace parameter values.

=head2 C<params>

  my $params = $p->params;
  $p         = $p->params([foo => 'b;ar', baz => 23]);

Parsed parameters.

=head2 C<parse>

  $p = $p->parse('foo=b%3Bar&baz=23');

Parse parameters.

=head2 C<remove>

  $p = $p->remove('foo');

Remove parameters.

  # "bar=yada"
  Mojo::Parameters->new('foo=bar&foo=baz&bar=yada')->remove('foo');

=head2 C<to_hash>

  my $hash = $p->to_hash;

Turn parameters into a hash reference.

  # "baz"
  Mojo::Parameters->new('foo=bar&foo=baz')->to_hash->{foo}[1];

=head2 C<to_string>

  my $string = $p->to_string;
  my $string = "$p";

Turn parameters into a string.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
