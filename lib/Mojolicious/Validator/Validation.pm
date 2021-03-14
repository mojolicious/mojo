package Mojolicious::Validator::Validation;
use Mojo::Base -base;

use Carp ();
use Mojo::DynamicMethods -dispatch;
use Scalar::Util ();

has [qw(csrf_token topic validator)];
has [qw(input output)] => sub { {} };

sub BUILD_DYNAMIC {
  my ($class, $method, $dyn_methods) = @_;

  return sub {
    my $self    = shift;
    my $dynamic = $dyn_methods->{$self->validator}{$method};
    return $self->check($method => @_) if $dynamic;
    my $package = ref $self;
    Carp::croak qq{Can't locate object method "$method" via package "$package"};
  };
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
  $self->error(csrf_token => ['csrf_protect']) unless $token && $token eq ($self->csrf_token // '');
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
  return [] unless defined(my $value = $_[0]->output->{$_[1] // $_[0]->topic});
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
  $self->output->{$name} = @input > 1 ? \@input : $input[0] if @input && !grep { !defined } @input;

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
  my $v = Mojolicious::Validator::Validation->new(validator => $validator);
  $v->input({foo => 'bar'});
  $v->required('foo')->in('bar', 'baz');
  say $v->param('foo');

=head1 DESCRIPTION

L<Mojolicious::Validator::Validation> performs L<Mojolicious::Validator> validation checks.

=head1 ATTRIBUTES

L<Mojolicious::Validator::Validation> implements the following attributes.

=head2 csrf_token

  my $token = $v->csrf_token;
  $v        = $v->csrf_token('fa6a08...');

CSRF token.

=head2 input

  my $input = $v->input;
  $v        = $v->input({foo => 'bar', baz => [123, 'yada']});

Data to be validated.

=head2 output

  my $output = $v->output;
  $v         = $v->output({foo => 'bar', baz => [123, 'yada']});

Validated data.

=head2 topic

  my $topic = $v->topic;
  $v        = $v->topic('foo');

Name of field currently being validated.

=head2 validator

  my $v = $v->validator;
  $v    = $v->validator(Mojolicious::Validator->new);

L<Mojolicious::Validator> object this validation belongs to.

=head1 METHODS

L<Mojolicious::Validator::Validation> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 check

  $v = $v->check('size', 2, 7);

Perform validation check on all values of the current L</"topic">, no more checks will be performed on them after the
first one failed. All checks from L<Mojolicious::Validator/"CHECKS"> are supported.

=head2 csrf_protect

  $v = $v->csrf_protect;

Validate C<csrf_token> and protect from cross-site request forgery.

=head2 error

  my $err = $v->error('foo');
  $v      = $v->error(foo => ['custom_check']);
  $v      = $v->error(foo => [$check, $result, @args]);

Get or set details for failed validation check, at any given time there can only be one per field.

  # Details about failed validation
  my ($check, $result, @args) = @{$v->error('foo')};

  # Force validation to fail for a field without performing a check
  $v->error(foo => ['some_made_up_check_name']);

=head2 every_param

  my $values = $v->every_param;
  my $values = $v->every_param('foo');

Similar to L</"param">, but returns all values sharing the same name as an array reference.

  # Get first value
  my $first = $v->every_param('foo')->[0];

=head2 failed

  my $names = $v->failed;

Return an array reference with all names for values that failed validation.

  # Names of all values that failed
  say for @{$v->failed};

=head2 has_data

  my $bool = $v->has_data;

Check if L</"input"> is available for validation.

=head2 has_error

  my $bool = $v->has_error;
  my $bool = $v->has_error('foo');

Check if validation resulted in errors, defaults to checking all fields.

=head2 is_valid

  my $bool = $v->is_valid;
  my $bool = $v->is_valid('foo');

Check if validation was successful and field has a value, defaults to checking the current L</"topic">.

=head2 optional

  $v = $v->optional('foo');
  $v = $v->optional('foo', @filters);

Change validation L</"topic"> and apply filters. All filters from L<Mojolicious::Validator/"FILTERS"> are supported.

  # Trim value and check size
  $v->optional('user', 'trim')->size(1, 15);

=head2 param

  my $value = $v->param;
  my $value = $v->param('foo');

Access validated values, defaults to the current L</"topic">. If there are multiple values sharing the same name, and
you want to access more than just the last one, you can use L</"every_param">.

  # Get value right away
  my $user = $v->optional('user')->size(1, 15)->param;

=head2 passed

  my $names = $v->passed;

Return an array reference with all names for values that passed validation.

  # Names of all values that passed
  say for @{$v->passed};

=head2 required

  $v = $v->required('foo');
  $v = $v->required('foo', @filters);

Change validation L</"topic">, apply filters, and make sure a value is present. All filters from
L<Mojolicious::Validator/"FILTERS"> are supported.

  # Trim value and check size
  $v->required('user', 'trim')->size(1, 15);

=head1 CHECKS

In addition to the L</"ATTRIBUTES"> and L</"METHODS"> above, you can also call validation checks provided by
L</"validator"> on L<Mojolicious::Validator::Validation> objects, similar to L</"check">.

  # Call validation checks
  $v->required('foo')->size(2, 5)->like(qr/^[A-Z]/);
  $v->optional('bar')->equal_to('foo');
  $v->optional('baz')->in('test', '123');

  # Longer version
  $v->required('foo')->check('size', 2, 5)->check('like', qr/^[A-Z]/);

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
