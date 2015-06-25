package Mojolicious::Validator;
use Mojo::Base -base;

use Mojolicious::Validator::Validation;

has checks => sub {
  {
    equal_to => \&_equal_to,
    file     => sub { !ref $_[2] || !$_[2]->isa('Mojo::Upload') },
    in       => \&_in,
    like => sub { $_[2] !~ $_[3] },
    size => \&_size
  };
};

sub add_check { $_[0]->checks->{$_[1]} = $_[2] and return $_[0] }

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

sub _size {
  my ($validation, $name, $value, $min, $max) = @_;
  my $len = ref $value ? $value->size : length $value;
  return $len < $min || $len > $max;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Validator - Validate values

=head1 SYNOPSIS

  use Mojolicious::Validator;

  my $validator  = Mojolicious::Validator->new;
  my $validation = $validator->validation;
  $validation->input({foo => 'bar'});
  $validation->required('foo')->like(qr/ar$/);
  say $validation->param('foo');

=head1 DESCRIPTION

L<Mojolicious::Validator> validates values for L<Mojolicious>.

=head1 CHECKS

These validation checks are available by default.

=head2 equal_to

  $validation = $validation->equal_to('foo');

Value needs to be equal to the value of another field. Note that this check does
not work with file uploads for security reasons.

=head2 file

  $validation = $validation->file;

Value needs to be a L<Mojo::Upload> object, representing a file upload.

=head2 in

  $validation = $validation->in(qw(foo bar baz));

Value needs to match one of the values in the list. Note that this check does
not work with file uploads for security reasons.

=head2 like

  $validation = $validation->like(qr/^[A-Z]/);

Value needs to match the regular expression. Note that this check does not work
with file uploads for security reasons.

=head2 size

  $validation = $validation->size(2, 5);

Value length needs to be between these two values.

=head1 ATTRIBUTES

L<Mojolicious::Validator> implements the following attributes.

=head2 checks

  my $checks = $validator->checks;
  $validator = $validator->checks({size => sub {...}});

Registered validation checks, by default only L</"equal_to">, L</"file">,
L</"in">, L</"like"> and L</"size"> are already defined.

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
