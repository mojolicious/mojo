package Mojolicious::Validator;
use Mojo::Base -base;

use Mojo::Util 'trim';
use Mojolicious::Validator::Validation;

has checks => sub {
  {
    equal_to => \&_equal_to,
    in       => \&_in,
    like     => sub { $_[2] !~ $_[3] },
    size     => \&_size,
    upload   => sub { !ref $_[2] || !$_[2]->isa('Mojo::Upload') }
  };
};
has filters => sub { {trim => \&_trim} };

sub add_check  { $_[0]->checks->{$_[1]}  = $_[2] and return $_[0] }
sub add_filter { $_[0]->filters->{$_[1]} = $_[2] and return $_[0] }

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

sub _trim { trim $_[2] // '' }

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

String value needs to be equal to the value of another field.

=head2 in

  $validation = $validation->in('foo', 'bar', 'baz');

String value needs to match one of the values in the list.

=head2 like

  $validation = $validation->like(qr/^[A-Z]/);

String value needs to match the regular expression.

=head2 size

  $validation = $validation->size(2, 5);

String value length or size of L<Mojo::Upload> object in bytes needs to be
between these two values.

=head2 upload

  $validation = $validation->upload;

Value needs to be a L<Mojo::Upload> object, representing a file upload.

=head1 FILTERS

These filters are available by default.

=head2 trim

  $validation = $validation->optional('foo', 'trim');

Trim whitespace characters from both ends of string value with
L<Mojo::Util/"trim">.

=head1 ATTRIBUTES

L<Mojolicious::Validator> implements the following attributes.

=head2 checks

  my $checks = $validator->checks;
  $validator = $validator->checks({size => sub {...}});

Registered validation checks, by default only L</"equal_to">, L</"in">,
L</"like">, L</"size"> and L</"upload"> are already defined.

=head1 METHODS

L<Mojolicious::Validator> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 add_check

  $validator = $validator->add_check(size => sub {...});

Register a validation check.

  $validator->add_check(foo => sub {
    my ($validation, $name, $value, @args) = @_;
    ...
    return undef;
  });

=head2 add_filter

  $validator = $validator->add_filter(trim => sub {...});

Register a new filter.

  $validator->add_filter(foo => sub {
    my ($validation, $name, $value) = @_;
    ...
    return $value;
  });

=head2 validation

  my $validation = $validator->validation;

Build L<Mojolicious::Validator::Validation> object to perform validations.

  my $validation = $validator->validation;
  $validation->input({foo => 'bar'});
  $validation->required('foo')->size(1, 5);
  say $validation->param('foo');

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
