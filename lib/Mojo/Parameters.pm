package Mojo::Parameters;
use Mojo::Base -base;
use overload 'bool' => sub {1}, fallback => 1;
use overload '""' => sub { shift->to_string }, fallback => 1;

use Mojo::Util qw/encode decode url_escape url_unescape/;
use Mojo::URL;

has charset        => 'UTF-8';
has pair_separator => '&';
has params         => sub { [] };

# "Yeah, Moe, that team sure did suck last night. They just plain sucked!
#  I've seen teams suck before,
#  but they were the suckiest bunch of sucks that ever sucked!
#  HOMER!
#  I gotta go Moe my damn weiner kids are listening."
sub new {
  my $self = shift->SUPER::new();

  # Hash/Array
  if (@_ > 1) { $self->append(@_) }

  # String
  else { $self->parse(@_) }

  return $self;
}

sub append {
  my ($self, @params) = @_;

  # Filter array values
  for (my $i = 1; $i < @params; $i += 2) {
    next if ref $params[$i] ne 'ARRAY';
    push @params, map { ($params[$i - 1], $_) } @{$params[$i]};
    splice @params, $i - 1, 2;
  }
  push @{$self->params}, map { defined $_ ? "$_" : '' } @params;

  return $self;
}

sub clone {
  my $self  = shift;
  my $clone = Mojo::Parameters->new;
  $clone->pair_separator($self->pair_separator);
  $clone->params([@{$self->params}]);
  return $clone;
}

sub merge {
  my $self = shift;
  push @{$self->params}, @{$_->params} for @_;
  return $self;
}

sub param {
  my $self = shift;
  my $name = shift;

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

sub parse {
  my $self   = shift;
  my $string = shift;

  # Clear
  $self->params([]);

  return $self unless defined $string;
  my $charset = $self->charset;

  # Detect query string without key/value pairs
  if ($string !~ /\=/) {

    # Replace "+" with whitespace
    $string =~ s/\+/\ /g;

    # Escaped string
    if (index($string, '%') >= 0) {
      url_unescape $string;
      my $backup = $string;
      decode $charset, $string if $charset;
      $string = $backup unless defined $string;
    }

    $self->params([$string, undef]);
    return $self;
  }

  # Detect pair separator for reconstruction
  $self->pair_separator(';') if $string =~ /\;/ && $string !~ /\&/;

  # W3C suggests to also accept ";" as a separator
  for my $pair (split /[\&\;]+/, $string) {

    # Parse
    $pair =~ /^([^\=]*)(?:=(.*))?$/;
    my $name  = $1;
    my $value = $2;
    $name  = '' unless defined $name;
    $value = '' unless defined $value;

    # Replace "+" with whitespace
    $name  =~ s/\+/\ /g;
    $value =~ s/\+/\ /g;

    # Escaped name
    if (index($name, '%') >= 0) {
      url_unescape $name;
      my $backup = $name;
      decode $charset, $name if $charset;
      $name = $backup unless defined $name;
    }

    # Escaped value
    if (index($value, '%') >= 0) {
      url_unescape $value;
      my $backup = $value;
      decode $charset, $value if $charset;
      $value = $backup unless defined $value;
    }

    push @{$self->params}, $name, $value;
  }

  return $self;
}

# "Don't kid yourself, Jimmy. If a cow ever got the chance,
#  he'd eat you and everyone you care about!"
sub remove {
  my ($self, $name) = @_;
  $name = '' unless defined $name;

  # Remove
  my $params = $self->params;
  for (my $i = 0; $i < @$params;) {
    if ($params->[$i] eq $name) { splice @$params, $i, 2 }
    else                        { $i += 2 }
  }
  $self->params($params);

  return $self;
}

sub to_hash {
  my $self = shift;

  # Format
  my $params = $self->params;
  my %params;
  for (my $i = 0; $i < @$params; $i += 2) {
    my $name  = $params->[$i];
    my $value = $params->[$i + 1];

    # Array
    if (exists $params{$name}) {
      $params{$name} = [$params{$name}]
        unless ref $params{$name} eq 'ARRAY';
      push @{$params{$name}}, $value;
    }

    # String
    else { $params{$name} = $value }
  }

  return \%params;
}

sub to_string {
  my $self = shift;

  my $params = $self->params;
  return '' unless @{$self->params};

  # Format
  my @params;
  my $charset = $self->charset;
  for (my $i = 0; $i < @$params; $i += 2) {
    my $name  = $params->[$i];
    my $value = $params->[$i + 1];

    # *( pchar / "/" / "?" ) with the exception of ";", "&" and "="
    encode $charset, $name if $charset;
    url_escape $name, $Mojo::URL::UNRESERVED;
    if ($value) {
      encode $charset, $value if $charset;
      url_escape $value, $Mojo::URL::UNRESERVED;
    }

    # Replace whitespace with "+"
    $name =~ s/\%20/\+/g;
    $value =~ s/\%20/\+/g if $value;

    push @params, defined $value ? "$name=$value" : "$name";
  }

  my $separator = $self->pair_separator;
  return join $separator, @params;
}

1;
__END__

=head1 NAME

Mojo::Parameters - Parameter Container

=head1 SYNOPSIS

  use Mojo::Parameters;

  my $params = Mojo::Parameters->new(foo => 'bar', baz => 23);

=head1 DESCRIPTION

L<Mojo::Parameters> is a container for form parameters.

=head1 ATTRIBUTES

L<Mojo::Parameters> implements the following attributes.

=head2 C<charset>

  my $charset = $params->charset;
  $params     = $params->charset('UTF-8');

Charset used for decoding parameters.

=head2 C<pair_separator>

  my $separator = $params->pair_separator;
  $params       = $params->pair_separator(';');

Separator for parameter pairs.

=head2 C<params>

  my $parameters = $params->params;
  $params        = $params->params(foo => 'b;ar', baz => 23);

The parameters.

=head1 METHODS

L<Mojo::Parameters> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

  my $params = Mojo::Parameters->new;
  my $params = Mojo::Parameters->new('foo=b%3Bar&baz=23');
  my $params = Mojo::Parameters->new(foo => 'b;ar', baz => 23);

Construct a new L<Mojo::Parameters> object.

=head2 C<append>

  $params = $params->append(foo => 'ba;r');

Append parameters.

=head2 C<clone>

  my $params2 = $params->clone;

Clone parameters.

=head2 C<merge>

  $params = $params->merge($params2, $params3);

Merge parameters.

=head2 C<param>

  my @names = $params->param;
  my $foo   = $params->param('foo');
  my @foo   = $params->param('foo');
  my $foo   = $params->param(foo => 'ba;r');

Check parameter values.

=head2 C<parse>

  $params = $params->parse('foo=b%3Bar&baz=23');

Parse parameters.

=head2 C<remove>

  $params = $params->remove('foo');

Remove a parameter.

=head2 C<to_hash>

  my $hash = $params->to_hash;

Turn parameters into a hashref.

=head2 C<to_string>

  my $string = $params->to_string;

Turn parameters into a string.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
