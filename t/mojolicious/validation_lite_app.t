use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

get '/' => sub {
  my $self = shift;
  $self->validation->required('name')->range(2, 5);
} => 'index';

my $t = Test::Mojo->new;

# Required and optional values
my $validation = $t->app->validation;
$validation->input({foo => 'bar', baz => 'yada'});
ok $validation->required('foo')->is_valid, 'valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
is $validation->param('foo'), 'bar', 'right value';
is_deeply [$validation->param], ['foo'], 'right names';
ok !$validation->has_errors, 'no errors';
ok $validation->optional('baz')->is_valid, 'valid';
is_deeply $validation->output, {foo => 'bar', baz => 'yada'}, 'right result';
is $validation->param('baz'), 'yada', 'right value';
is_deeply [$validation->param], [qw(baz foo)], 'right names';
is_deeply [$validation->param([qw(foo baz)])], [qw(bar yada)], 'right values';
ok !$validation->has_errors, 'no errors';
ok !$validation->optional('does_not_exist')->is_valid, 'not valid';
is_deeply $validation->output, {foo => 'bar', baz => 'yada'}, 'right result';
ok !$validation->has_errors, 'no errors';
ok !$validation->required('does_not_exist')->is_valid, 'not valid';
is_deeply $validation->output, {foo => 'bar', baz => 'yada'}, 'right result';
ok $validation->has_errors, 'has errors';
is_deeply [$validation->errors('does_not_exist')], ['Value is required.'],
  'right error';

# Range
$validation = $t->app->validation;
$validation->input({foo => 'bar', baz => 'yada', yada => 'yada'});
ok $validation->required('foo')->range(1, 3)->is_valid, 'valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
ok !$validation->has_errors, 'no errors';
ok !$validation->required('baz')->range(1, 3)->is_valid, 'not valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
ok $validation->has_errors, 'has errors';
is_deeply [$validation->errors('baz')],
  ['Value needs to be 1-3 characters long.'], 'right error';
ok !$validation->required('yada')->range(5, 10)->is_valid, 'not valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
ok $validation->has_errors, 'has errors';
is_deeply [$validation->errors('yada')],
  ['Value needs to be 5-10 characters long.'], 'right error';

# Custom errors
$validation = $t->app->validation;
$validation->input({foo => 'bar', yada => 'yada'});
ok !$validation->error('Bar is required.')->required('bar')->is_valid,
  'not valid';
is_deeply $validation->output, {}, 'right result';
ok $validation->has_errors, 'has errors';
is_deeply [$validation->errors('bar')], ['Bar is required.'], 'right error';
ok !$validation->required('baz')->is_valid, 'not valid';
ok $validation->has_errors, 'has errors';
is_deeply [$validation->errors('baz')], ['Value is required.'], 'right error';
ok !$validation->required('foo')->error('Foo is too small.')->range(25, 100)
  ->is_valid, 'not valid';
ok $validation->has_errors, 'has errors';
is_deeply [$validation->errors('foo')], ['Foo is too small.'], 'right error';
is $validation->topic, 'foo', 'right topic';
ok !$validation->error('Failed!')->required('yada')->range(25, 100)->is_valid,
  'not valid';
ok $validation->has_errors, 'has errors';
is_deeply [$validation->errors('yada')],
  ['Value needs to be 25-100 characters long.'], 'right error';
is $validation->topic, 'yada', 'right topic';

# Successful validation
$t->get_ok('/?name=sri')->status_is(200)->content_is("\n");

# Failed validation
$t->get_ok('/?name=sebastian')->status_is(200)
  ->content_is("Value needs to be 2-5 characters long.\n");

done_testing();

__DATA__

@@ index.html.ep
%= $_ for validation->errors('name')
