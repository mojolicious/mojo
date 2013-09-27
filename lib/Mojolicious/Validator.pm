package Mojolicious::Validator;
use Mojo::Base -base;

use Mojolicious::Validator::Validation;

has checks => sub {
  {equal_to => \&_equal_to, in => \&_in, regex => \&_regex, size => \&_size};
};
has errors => sub {
  {
    equal_to => sub {'Values are not equal.'},
    in       => sub {'Value is not allowed.'},
    required => sub {'Value is required.'},
    size     => sub {qq{Value needs to be $_[3]-$_[4] characters long.}}
  };
};

sub add_check { shift->_add(checks => @_) }
sub add_error { shift->_add(errors => @_) }

sub validation {
  Mojolicious::Validator::Validation->new(validator => shift);
}

sub _add {
  my ($self, $attr, $name, $cb) = @_;
  $self->$attr->{$name} = $cb;
  return $self;
}

sub _equal_to {
  my ($validation, $name, $value, $to) = @_;
  return undef unless defined(my $other = $validation->input->{$to});
  return $value eq $other;
}

sub _in {
  my ($validation, $name, $value) = (shift, shift, shift);
  $value eq $_ && return 1 for @_;
  return undef;
}

sub _regex { $_[2] =~ $_[3] }

sub _size {
  my ($validation, $name, $value, $min, $max) = @_;
  my $len = length $value;
  return $len >= $min && $len <= $max;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Validator - Validate form data

=head1 SYNOPSIS

  use Mojolicious::Validator;

  my $validator  = Mojolicious::Validator->new;
  my $validation = $validator->validation;

=head1 DESCRIPTION

L<Mojolicious::Validator> validates form data. Note that this module is
EXPERIMENTAL and might change without warning!

=head1 CHECKS

These checks are available for validation by default.

=head2 equal_to

  $validation->equal_to('foo');

Value needs to be equal to the value of another field.

=head2 in

  $validation->in('foo', 'bar', 'baz');

Value needs to match one of the values in the list.

=head2 regex

  $validation->regex(qr/^[A-Z]/);

Value needs to match the regular expression.

=head2 size

  $validation->size(2, 5);

Value length in characters needs to be between these two values.

=head1 ATTRIBUTES

L<Mojolicious::Validator> implements the following attributes.

=head2 checks

  my $checks = $validator->checks;
  $validator = $validator->checks({size => sub {...}});

Registered checks, by default only C<equal_to>, C<in>, C<regex> and C<size>
are already defined.

=head2 errors

  my $errors = $validator->errors;
  $validator = $validator->errors({size => sub {...}});

Registered error generators, by default only C<equal_to>, C<in>, C<required>
and C<size> are already defined.

=head1 METHODS

L<Mojolicious::Validator> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 add_check

  $validator = $validator->add_check(size => sub {...});

Register a new check.

=head2 add_error

  $validator = $validator->add_error(size => sub {...});

Register a new error generator.

=head2 validation

  my $validation = $validator->validation;

Get a new L<Mojolicious::Validator::Validation> object to perform validations.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
