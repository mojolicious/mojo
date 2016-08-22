package Mojolicious::Validator::Validation;
use Mojo::Base -base;

use Carp         ();
use Scalar::Util ();

has [qw(csrf_token topic validator)];
has [qw(input output)] => sub { {} };

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;
  Carp::croak "Undefined subroutine &${package}::$method called"
    unless Scalar::Util::blessed $self && $self->isa(__PACKAGE__);

  return $self->check($method => @_) if $self->validator->checks->{$method};
  Carp::croak qq{Can't locate object method "$method" via package "$package"};
}

sub check {
  my ($self, $check) = (shift, shift);

  return $self unless $self->is_valid;

  my $cb     = $self->validator->checks->{$check};
  my $name   = $self->topic;
  my $values = $self->output->{$name};
  for my $value (ref $values eq 'ARRAY' ? @$values : $values) {
    next unless my $result = $self->$cb($name, $value, @_);
    return $self->error($name => [$check, $result, @_]);
  }

  return $self;
}

sub csrf_protect {
  my $self  = shift;
  my $token = $self->input->{csrf_token};
  $self->error(csrf_token => ['csrf_protect'])
    unless $token && $token eq ($self->csrf_token // '');
  return $self;
}

sub error {
  my ($self, $name) = (shift, shift);
  return $self->{error}{$name} unless @_;
  $self->{error}{$name} = shift;
  delete $self->output->{$name};
  return $self;
}

sub every_param {
  return [] unless defined(my $value = shift->output->{shift()});
  return [ref $value eq 'ARRAY' ? @$value : $value];
}

sub failed { [sort keys %{shift->{error}}] }

sub has_data { !!keys %{shift->input} }

sub has_error { $_[1] ? exists $_[0]{error}{$_[1]} : !!keys %{$_[0]{error}} }

sub is_valid { exists $_[0]->output->{$_[1] // $_[0]->topic} }

sub optional {
  my ($self, $name, @filters) = @_;

  return $self->topic($name) unless defined(my $input = $self->input->{$name});

  my @input = ref $input eq 'ARRAY' ? @$input : ($input);
  for my $cb (map { $self->validator->filters->{$_} } @filters) {
    @input = map { $self->$cb($name, $_) } @input;
  }
  $self->output->{$name} = ref $input eq 'ARRAY' ? \@input : $input[0]
    if @input && !grep { !length } @input;

  return $self->topic($name);
}

sub param { shift->every_param(shift)->[-1] }

sub passed { [sort keys %{shift->output}] }

sub required {
  my ($self, $name) = (shift, shift);
  return $self if $self->optional($name, @_)->is_valid;
  return $self->error($name => ['required']);
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
  $validation->input({foo => 'bar'});
  $validation->required('foo')->in('bar', 'baz');
  say $validation->param('foo');

=head1 DESCRIPTION

L<Mojolicious::Validator::Validation> performs L<Mojolicious::Validator>
validation checks.

=head1 ATTRIBUTES

L<Mojolicious::Validator::Validation> implements the following attributes.

=head2 csrf_token

  my $token   = $validation->csrf_token;
  $validation = $validation->csrf_token('fa6a08...');

CSRF token.

=head2 input

  my $input   = $validation->input;
  $validation = $validation->input({foo => 'bar', baz => [123, 'yada']});

Data to be validated.

=head2 output

  my $output  = $validation->output;
  $validation = $validation->output({foo => 'bar', baz => [123, 'yada']});

Validated data.

=head2 topic

  my $topic   = $validation->topic;
  $validation = $validation->topic('foo');

Name of field currently being validated.

=head2 validator

  my $validator = $validation->validator;
  $validation   = $validation->validator(Mojolicious::Validator->new);

L<Mojolicious::Validator> object this validation belongs to.

=head1 METHODS

L<Mojolicious::Validator::Validation> inherits all methods from L<Mojo::Base>
and implements the following new ones.

=head2 check

  $validation = $validation->check('size', 2, 7);

Perform validation check on all values of the current L</"topic">, no more
checks will be performed on them after the first one failed. All checks from
L<Mojolicious::Validator/"CHECKS"> are supported.

=head2 csrf_protect

  $validation = $validation->csrf_protect;

Validate C<csrf_token> and protect from cross-site request forgery.

=head2 error

  my $err     = $validation->error('foo');
  $validation = $validation->error(foo => ['custom_check']);
  $validation = $validation->error(foo => [$check, $result, @args]);

Get or set details for failed validation check, at any given time there can
only be one per field.

  # Details about failed validation
  my ($check, $result, @args) = @{$validation->error('foo')};

=head2 every_param

  my $values = $validation->every_param('foo');

Similar to L</"param">, but returns all values sharing the same name as an
array reference.

  # Get first value
  my $first = $validation->every_param('foo')->[0];

=head2 failed

  my $names = $validation->failed;

Return an array reference with all names for values that failed validation.

  # Names of all values that failed
  say for @{$validation->failed};

=head2 has_data

  my $bool = $validation->has_data;

Check if L</"input"> is available for validation.

=head2 has_error

  my $bool = $validation->has_error;
  my $bool = $validation->has_error('foo');

Check if validation resulted in errors, defaults to checking all fields.

=head2 is_valid

  my $bool = $validation->is_valid;
  my $bool = $validation->is_valid('foo');

Check if validation was successful and field has a value, defaults to checking
the current L</"topic">.

=head2 optional

  $validation = $validation->optional('foo');
  $validation = $validation->optional('foo', 'filter1', 'filter2');

Change validation L</"topic"> and apply filters. All filters from
L<Mojolicious::Validator/"FILTERS"> are supported.

  # Trim value and check size
  $validation->optional('user', 'trim')->size(1, 15);

=head2 param

  my $value = $validation->param('foo');

Access validated values. If there are multiple values sharing the same name, and
you want to access more than just the last one, you can use L</"every_param">.

=head2 passed

  my $names = $validation->passed;

Return an array reference with all names for values that passed validation.

  # Names of all values that passed
  say for @{$validation->passed};

=head2 required

  $validation = $validation->required('foo');
  $validation = $validation->required('foo', 'filter1', 'filter2');

Change validation L</"topic">, apply filters, and make sure a value is present
and not an empty string. All filters from L<Mojolicious::Validator/"FILTERS">
are supported.

  # Trim value and check size
  $validation->required('user', 'trim')->size(1, 15);

=head1 AUTOLOAD

In addition to the L</"ATTRIBUTES"> and L</"METHODS"> above, you can also call
validation checks provided by L</"validator"> on
L<Mojolicious::Validator::Validation> objects, similar to L</"check">.

  # Call validation checks
  $validation->required('foo')->size(2, 5)->like(qr/^[A-Z]/);
  $validation->optional('bar')->equal_to('foo');
  $validation->optional('baz')->in('test', '123');

  # Longer version
  $validation->required('foo')->check('size', 2, 5)->check('like', qr/^[A-Z]/);

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
