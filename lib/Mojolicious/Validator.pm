package Mojolicious::Validator;
use Mojo::Base -base;

use Mojolicious::Validator::Validation;

has checks => sub {
  {equal_to => \&_equal_to, in => \&_in, like => \&_like, size => \&_size};
};

sub add_check {
  my ($self, $name, $cb) = @_;
  $self->checks->{$name} = $cb;
  return $self;
}

sub validation {
  Mojolicious::Validator::Validation->new(validator => shift);
}

sub _equal_to {
  my ($validation, $name, $value, $to) = @_;
  return 1 unless defined(my $other = $validation->input->{$to});
  return $value ne $other;
}

sub _in {
  my ($validation, $name, $value) = (shift, shift, shift);
  $value eq $_ && return undef for @_;
  return 1;
}

sub _like { $_[2] !~ $_[3] }

sub _size {
  my ($validation, $name, $value, $min, $max) = @_;
  my $len = length $value;
  return $len < $min || $len > $max;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Validator - Validate form data

=head1 SYNOPSIS

  use Mojolicious::Validator;

  my $validator  = Mojolicious::Validator->new;
  my $validation = $validator->validation;
  $validation->input({foo => 'bar'});
  $validation->required('foo')->like(qr/ar$/);
  say $validation->param('foo');

=head1 DESCRIPTION

L<Mojolicious::Validator> validates form data for L<Mojolicious>.

=head1 CHECKS

These validation checks are available by default.

=head2 equal_to

  $validation->equal_to('foo');

Value needs to be equal to the value of another field.

=head2 in

  $validation->in(qw(foo bar baz));

Value needs to match one of the values in the list.

=head2 like

  $validation->like(qr/^[A-Z]/);

Value needs to match the regular expression.

=head2 size

  $validation->size(2, 5);

Value length in characters needs to be between these two values.

=head1 ATTRIBUTES

L<Mojolicious::Validator> implements the following attributes.

=head2 checks

  my $checks = $validator->checks;
  $validator = $validator->checks({size => sub {...}});

Registered validation checks, by default only L</"equal_to">, L</"in">,
L</"like"> and L</"size"> are already defined.

=head1 METHODS

L<Mojolicious::Validator> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 add_check

  $validator = $validator->add_check(size => sub {...});

Register a new validation check.

=head2 validation

  my $validation = $validator->validation;

Build L<Mojolicious::Validator::Validation> object to perform validations.

  my $validation = $validator->validation;
  $validation->input({foo => 'bar'});
  $validation->required('foo')->size(1, 5);
  say $validation->param('foo');

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
