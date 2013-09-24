package Mojolicious::Validator;
use Mojo::Base -base;

use Mojolicious::Validator::Validation;

has checks => sub { {range => \&_range} };
has errors => sub {
  {
    range    => sub {qq{Value needs to be $_[3]-$_[4] characters long.}},
    required => sub {qq{Value is required.}}
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

sub _range {
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

L<Mojolicious::Validator> validates form data.

=head1 ATTRIBUTES

L<Mojolicious::Validator> implements the following attributes.

=head2 checks

  my $checks = $validator->checks;
  $validator = $validator->checks({range => sub {...}});

Registered checks, by default only C<range> is already defined.

=head2 errors

  my $errors = $validator->errors;
  $validator = $validator->errors({range => sub {...}});

Registered error generators, by default only C<range> and C<required> are
already defined.

=head1 METHODS

L<Mojolicious::Validator> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 add_check

  $validator = $validator->add_check(range => sub {...});

Register a new check.

=head2 add_error

  $validator = $validator->add_error(range => sub {...});

Register a new error generator.

=head2 validation

  my $validation = $validator->validation;

Get a new L<Mojolicious::Validator::Validation> object to perform validations.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
