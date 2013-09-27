package Mojolicious::Validator::Validation;
use Mojo::Base -base;

use Carp 'croak';
use Scalar::Util 'blessed';
use Mojo::Collection;

has [qw(input output)] => sub { {} };
has [qw(topic validator)];

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^([\w:]+)::(\w+)$/;
  Carp::croak "Undefined subroutine &${package}::$method called"
    unless Scalar::Util::blessed $self && $self->isa(__PACKAGE__);

  croak qq{Can't locate object method "$method" via package "$package"}
    unless $self->validator->checks->{$method};
  return $self->check($method => @_);
}

sub DESTROY { }

sub check {
  my ($self, $check) = (shift, shift);

  my $err = delete $self->{error};
  return $self unless $self->is_valid;

  my $cb   = $self->validator->checks->{$check};
  my $name = $self->topic;
  return $self if $self->_check($name, $self->input->{$name}, $cb, @_);

  delete $self->output->{$name};
  $self->_error($check, $err, $name, delete $self->input->{$name}, @_);
  return $self;
}

sub error {
  my $self = shift;
  $self->{error} = shift;
  return $self;
}

sub errors { Mojo::Collection->new(@{shift->{errors}{shift()} // []}) }

sub has_errors {
  $_[1] ? exists $_[0]{errors}{$_[1]} : !!keys %{$_[0]{errors}};
}

sub is_submitted { !!keys %{shift->input} }

sub is_valid { exists $_[0]->output->{$_[1] // $_[0]->topic} }

sub optional {
  my ($self, $name) = @_;
  my $input = $self->input->{$name};
  $self->output->{$name} = $input
    if $self->_check($name, $input, sub { defined $_[2] && length $_[2] });
  return $self->topic($name);
}

sub param {
  my ($self, $name) = @_;

  # Multiple names
  return map { scalar $self->param($_) } @$name if ref $name eq 'ARRAY';

  # List names
  return sort keys %{$self->output} unless $name;

  my $value = $self->output->{$name};
  my @values = ref $value eq 'ARRAY' ? @$value : ($value);
  return wantarray ? @values : $values[0];
}

sub required {
  my ($self, $name) = @_;
  $self->optional($name);
  my $err = delete $self->{error};
  $self->_error('required', $err, $name, $self->input->{$name})
    unless $self->is_valid;
  return $self;
}

sub _check {
  my ($self, $name, $input, $cb) = (shift, shift, shift, shift);
  for my $value (ref $input eq 'ARRAY' ? @$input : $input) {
    return undef unless $self->$cb($name, $value, @_);
  }
  return 1;
}

sub _error {
  my ($self, $check, $err, $name, $input)
    = (shift, shift, shift, shift, shift);
  my $cb = $self->validator->errors->{$check} // sub {'Value is invalid.'};
  push @{$self->{errors}{$name}}, $err // $self->$cb($name, $_, @_)
    for ref $input eq 'ARRAY' ? @$input : $input;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Validator::Validation - Perform validations

=head1 SYNOPSIS

  use Mojolicious::Validator;
  use Mojolicious::Validator::Validation;

  my $validator = Mojolicious::Validator->new;
  my $validation
    = Mojolicious::Validator::Validation->new(validator => $validator);

=head1 DESCRIPTION

L<Mojolicious::Validator::Validation> performs validations.

=head1 ATTRIBUTES

L<Mojolicious::Validator::Validation> implements the following attributes.

=head2 input

  my $input   = $validation->input;
  $validation = $validation->input({});

Data to be validated.

=head2 output

  my $output  = $validation->output;
  $validation = $validation->output({});

Validated data.

=head2 topic

  my $topic   = $validation->topic;
  $validation = $validation->topic('foo');

Current validation topic.

=head2 validator

  my $validator = $validation->validator;
  $validation   = $validation->validator(Mojolicious::Validator->new);

L<Mojolicious::Validator> object this validation belongs to.

=head1 METHODS

L<Mojolicious::Validator::Validation> inherits all methods from L<Mojo::Base>
and implements the following new ones.

=head2 check

  $validation = $validation->check('size', 2, 7);

Perform validation check.

=head2 error

  $validation = $validation->error('This went wrong.');

Set custom error message for next validation check.

=head2 errors

  my $collection = $validation->errors('foo');

Return L<Mojo::Collection> object containing all error messages for failed
validation checks.

=head2 has_errors

  my $success = $validation->has_errors;
  my $success = $validation->has_errors('foo');

Check if validation resulted in errors, defaults to checking all fields.

=head2 is_submitted

  my $success = $validation->is_submitted;

Check if data has been submitted for validation.

=head2 is_valid

  my $success = $validation->is_valid;
  my $success = $validation->is_valid('foo');

Check if validation was successful and field has a value, defaults to checking
the current C<topic>.

=head2 optional

  $validation = $validation->optional('foo');

Change validation C<topic>.

=head2 param

  my @names       = $c->param;
  my $foo         = $c->param('foo');
  my @foo         = $c->param('foo');
  my ($foo, $bar) = $c->param(['foo', 'bar']);

Access validated parameters.

=head2 required

  $validation = $validation->required('foo');

Change validation C<topic> and make sure a value is present.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
