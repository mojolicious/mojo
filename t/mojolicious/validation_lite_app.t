use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::Asset::Memory;
use Mojo::Upload;
use Mojolicious::Lite;
use Test::Mojo;

# Custom check
app->validator->add_check(two => sub { length $_[2] == 2 ? undef : "e:$_[1]" });

any '/' => sub {
  my $c = shift;

  my $validation = $c->validation;
  return $c->render unless $validation->has_data;

  $validation->required('foo')->two->in('☃☃');
  $validation->optional('bar')->two;
  $validation->optional('baz')->two;
  $validation->optional('yada')->two;
} => 'index';

any '/upload' => sub {
  my $c          = shift;
  my $validation = $c->validation;
  return $c->render unless $validation->has_data;
  $validation->required('foo')->upload;
};

any '/forgery' => sub {
  my $c          = shift;
  my $validation = $c->validation;
  return $c->render unless $validation->has_data;
  $validation->csrf_protect->required('foo');
};

my $t = Test::Mojo->new;

# Required and optional values
my $validation = $t->app->validation->input({foo => 'bar', baz => 'yada'});
is_deeply $validation->passed, [], 'no names';
is_deeply $validation->failed, [], 'no names';
is $validation->param('foo'), undef, 'no value';
is_deeply $validation->every_param('foo'), [], 'no values';
ok $validation->required('foo')->is_valid, 'valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
is $validation->param('foo'), 'bar', 'right value';
is_deeply $validation->every_param('foo'), ['bar'], 'right values';
is_deeply $validation->passed,             ['foo'], 'right names';
ok !$validation->has_error, 'no error';
ok $validation->optional('baz')->is_valid, 'valid';
is_deeply $validation->output, {foo => 'bar', baz => 'yada'}, 'right result';
is $validation->param('baz'), 'yada', 'right value';
is_deeply $validation->passed, [qw(baz foo)], 'right names';
ok !$validation->has_error, 'no error';
ok !$validation->optional('does_not_exist')->is_valid, 'not valid';
is_deeply $validation->output, {foo => 'bar', baz => 'yada'}, 'right result';
ok !$validation->has_error, 'no error';
ok !$validation->required('does_not_exist')->is_valid, 'not valid';
is_deeply $validation->output, {foo => 'bar', baz => 'yada'}, 'right result';
ok $validation->has_error, 'has error';
is_deeply $validation->error('does_not_exist'), ['required'], 'right error';
$validation = $t->app->validation->input(
  {foo => [], bar => ['a'], baz => undef, yada => [undef]});
ok !$validation->optional('foo')->is_valid, 'not valid';
is_deeply $validation->output, {}, 'right result';
ok !$validation->has_error, 'no error';
ok !$validation->optional('baz')->is_valid, 'not valid';
is_deeply $validation->output, {}, 'right result';
ok !$validation->has_error, 'no error';
ok !$validation->optional('yada')->is_valid, 'not valid';
is_deeply $validation->output, {}, 'right result';
ok !$validation->has_error, 'no error';
ok $validation->optional('bar')->is_valid, 'valid';
is_deeply $validation->output, {bar => ['a']}, 'right result';
ok !$validation->in('c')->is_valid, 'not valid';
is_deeply $validation->output, {}, 'right result';
ok $validation->has_error, 'has error';

# Equal to
$validation
  = $t->app->validation->input({foo => 'bar', baz => 'bar', yada => 'yada'});
ok $validation->optional('foo')->equal_to('baz')->is_valid, 'valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
ok !$validation->has_error, 'no error';
ok !$validation->optional('baz')->equal_to('does_not_exist')->is_valid,
  'not valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
ok $validation->has_error, 'has error';
is_deeply $validation->error('baz'), [qw(equal_to 1 does_not_exist)],
  'right error';
ok !$validation->optional('yada')->equal_to('foo')->is_valid, 'not valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
ok $validation->has_error, 'has error';
is_deeply $validation->error('yada'), [qw(equal_to 1 foo)], 'right error';
is_deeply $validation->failed,        [qw(baz yada)],       'right names';

# In
$validation = $t->app->validation->input(
  {foo => [qw(bar whatever)], baz => [qw(yada ohoh)]});
ok $validation->required('foo')->in(qw(23 bar whatever))->is_valid, 'valid';
is_deeply $validation->every_param('foo'), [qw(bar whatever)], 'right results';
is $validation->param('foo'), 'whatever', 'right result';
is_deeply $validation->output, {foo => [qw(bar whatever)]}, 'right result';
ok !$validation->has_error, 'no error';
ok !$validation->required('baz')->in(qw(yada whatever))->is_valid, 'not valid';
is_deeply $validation->output, {foo => [qw(bar whatever)]}, 'right result';
ok $validation->has_error, 'has error';
is_deeply $validation->error('baz'), [qw(in 1 yada whatever)], 'right error';
is_deeply $validation->failed, ['baz'], 'right names';

# Like
$validation = $t->app->validation->input({foo => 'bar', baz => 'yada'});
ok $validation->required('foo')->like(qr/^b/)->is_valid, 'valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
ok !$validation->has_error, 'no error';
my $re = qr/ar$/;
ok !$validation->required('baz')->like($re)->is_valid, 'not valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
ok $validation->has_error, 'has error';
is_deeply $validation->error('baz'), ['like', 1, $re], 'right error';

# Size
$validation
  = $t->app->validation->input({foo => 'bar', baz => 'yada', yada => 'yada'});
ok $validation->required('foo')->size(1, 3)->is_valid, 'valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
ok !$validation->has_error, 'no error';
ok !$validation->required('baz')->size(1, 3)->is_valid, 'not valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
ok $validation->has_error, 'has error';
is_deeply $validation->error('baz'), [qw(size 1 1 3)], 'right error';
ok !$validation->required('yada')->size(5, 10)->is_valid, 'not valid';
is $validation->topic, 'yada', 'right topic';
ok $validation->has_error('baz'), 'has error';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
ok $validation->has_error, 'has error';
is_deeply $validation->error('yada'), [qw(size 1 5 10)], 'right error';

# Upload
$validation = $t->app->validation->input(
  {
    foo => Mojo::Upload->new,
    bar => [Mojo::Upload->new, Mojo::Upload->new],
    baz => [Mojo::Upload->new, 'test']
  }
);
ok $validation->required('foo')->upload->is_valid, 'valid';
ok $validation->required('bar')->upload->is_valid, 'valid';
ok $validation->required('baz')->is_valid, 'valid';
ok !$validation->has_error, 'no error';
ok !$validation->upload->is_valid, 'not valid';
ok $validation->has_error, 'has error';
is_deeply $validation->error('baz'), [qw(upload 1)], 'right error';
is_deeply $validation->failed, ['baz'], 'right names';

# Upload size
$validation = $t->app->validation->input(
  {
    foo => [
      Mojo::Upload->new(asset => Mojo::Asset::Memory->new->add_chunk('valid'))
    ],
    bar => [
      Mojo::Upload->new(
        asset => Mojo::Asset::Memory->new->add_chunk('not valid')
      )
    ]
  }
);
ok $validation->required('foo')->upload->size(1, 6)->is_valid, 'valid';
ok !$validation->has_error, 'no error';
ok !$validation->required('bar')->upload->size(1, 6)->is_valid, 'not valid';
ok $validation->has_error, 'has error';
is_deeply $validation->error('bar'), [qw(size 1 1 6)], 'right error';
is_deeply $validation->failed, ['bar'], 'right names';

# Trim
$validation = $t->app->validation->input({foo => ' bar', baz => ['  0 ', 1]});
ok $validation->required('foo', 'trim')->in('bar')->is_valid, 'valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
ok !$validation->optional('missing', 'trim')->is_valid, 'not valid';
ok $validation->optional('baz', 'trim')->like(qr/^\d$/)->is_valid, 'valid';
is_deeply $validation->output, {foo => 'bar', baz => [0, 1]}, 'right result';
$validation = $t->app->validation->input({nothing => '  ', more => [undef]});
ok !$validation->required('nothing', 'trim')->is_valid, 'not valid';
is_deeply $validation->output, {}, 'right result';
ok $validation->required('nothing')->is_valid, 'valid';
is_deeply $validation->output, {nothing => '  '}, 'right result';
ok !$validation->optional('more', 'trim')->is_valid, 'not valid';
is_deeply $validation->output, {nothing => '  '}, 'right result';

# Custom filter
$t->app->validator->add_filter(quote => sub {qq{$_[1]="$_[2]"}});
$validation = $t->app->validation->input({foo => [' bar', 'baz']});
ok $validation->required('foo', 'trim', 'quote')->like(qr/"/)->is_valid,
  'valid';
is_deeply $validation->output, {foo => ['foo="bar"', 'foo="baz"']},
  'right result';

# Multiple empty values
$validation = $t->app->validation;
ok !$validation->has_data, 'no data';
$validation->input({foo => ['', 'bar', ''], bar => ['', 'baz', '']});
ok $validation->has_data, 'has data';
ok !$validation->required('foo')->is_valid, 'not valid';
is_deeply $validation->output, {}, 'right result';
ok $validation->has_error, 'has error';
is_deeply $validation->error('foo'), ['required'], 'right error';

# "0"
$validation = $t->app->validation->input({0 => 0});
ok $validation->has_data, 'has data';
ok $validation->required(0)->size(1, 1)->is_valid, 'valid';
is_deeply $validation->output, {0 => 0}, 'right result';
is $validation->param(0), 0, 'right value';

# Custom error
$validation = $t->app->validation->input({foo => 'bar'});
ok !$validation->required('foo')->has_error, 'no error';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
ok $validation->error(foo => ['custom_check'])->has_error, 'has error';
is_deeply $validation->output, {}, 'right result';
is_deeply $validation->size(1, 2)->error('foo'), ['custom_check'],
  'right error';

# CSRF protection
$validation = $t->app->validation->input({foo => 'bar'})->csrf_protect;
ok $validation->has_data,  'has data';
ok $validation->has_error, 'has error';
is_deeply $validation->error('csrf_token'), ['csrf_protect'], 'right error';
$validation = $t->app->validation->input({csrf_token => 'abc'});
ok $validation->has_data, 'has data';
ok $validation->csrf_protect->has_error, 'has error';
ok $validation->has_data, 'has data';
is_deeply $validation->error('csrf_token'), ['csrf_protect'], 'right error';
$validation = $t->app->validation->input({csrf_token => 'abc', foo => 'bar'})
  ->csrf_token('cba')->csrf_protect;
ok $validation->has_error, 'has error';
is_deeply $validation->error('csrf_token'), ['csrf_protect'], 'right error';
$validation = $t->app->validation->input({csrf_token => 'abc', foo => 'bar'})
  ->csrf_token('abc')->csrf_protect;
ok !$validation->has_error, 'no error';
ok $validation->required('foo')->is_valid, 'valid';
is_deeply $validation->output, {foo => 'bar'}, 'right result';
$validation = $t->app->validation->input({csrf_token => ['abc', 'abc']})
  ->csrf_token('abc')->csrf_protect;
ok $validation->has_error, 'has error';
is_deeply $validation->error('csrf_token'), ['csrf_protect'], 'right error';

# Missing method and function (AUTOLOAD)
eval { $t->app->validation->missing };
my $package = 'Mojolicious::Validator::Validation';
like $@, qr/^Can't locate object method "missing" via package "$package"/,
  'right error';
eval { Mojolicious::Validator::Validation::missing() };
like $@, qr/^Undefined subroutine &${package}::missing called/, 'right error';

# No validation
$t->get_ok('/')->status_is(200)->element_exists_not('div:root')
  ->text_is('label[for="foo"]' => '<Foo>')
  ->element_exists('input[type="text"]')->element_exists('textarea')
  ->text_is('label[for="baz"]' => 'Baz')->element_exists('select')
  ->element_exists('input[type="password"]');

# Successful validation
$t->get_ok('/' => form => {foo => '☃☃'})->status_is(200)
  ->element_exists_not('div:root')->text_is('label[for="foo"]' => '<Foo>')
  ->element_exists('input[type="text"]')->element_exists('textarea')
  ->text_is('label[for="baz"]' => 'Baz')->element_exists('select')
  ->element_exists('input[type="password"]');

# Validation failed for required fields
$t->post_ok('/' => form => {foo => 'no'})->status_is(200)
  ->text_is('div:root'                                 => 'in 1')
  ->text_is('label.custom.field-with-error[for="foo"]' => '<Foo>')
  ->element_exists('input.custom.field-with-error[type="text"][value="no"]')
  ->element_exists_not('textarea.field-with-error')
  ->element_exists_not('label.custom.field-with-error[for="baz"]')
  ->element_exists_not('select.field-with-error')
  ->element_exists_not('input.field-with-error[type="password"]')
  ->element_count_is('.field-with-error', 2)
  ->element_count_is('.field-with-error', 2, 'with description');

# Successful file upload
$t->post_ok(
  '/upload' => form => {foo => {content => 'bar', filename => 'test.txt'}})
  ->element_exists_not('.field-with-error');

# Successful file upload (multiple files)
$t->post_ok(
  '/upload' => form => {
    foo => [
      {content => 'One', filename => 'one.txt'},
      {content => 'Two', filename => 'two.txt'}
    ]
  }
)->element_exists_not('.field-with-error');

# Failed file upload
$t->post_ok('/upload' => form => {foo => 'bar'})
  ->element_exists('.field-with-error');

# Failed file upload (multiple files)
$t->post_ok('/upload' => form => {foo => ['one', 'two']})
  ->element_exists('.field-with-error');

# Missing CSRF token
$t->get_ok('/forgery' => form => {foo => 'bar'})->status_is(200)
  ->content_like(qr/Wrong or missing CSRF token!/)
  ->element_exists('[value=bar]')->element_exists_not('.field-with-error');

# Correct CSRF token
my $token = $t->ua->get('/forgery')->res->dom->at('[name=csrf_token]')->val;
$t->post_ok('/forgery' => form => {csrf_token => $token, foo => 'bar'})
  ->status_is(200)->content_unlike(qr/Wrong or missing CSRF token!/)
  ->element_exists('[value=bar]')->element_exists_not('.field-with-error');

# Correct CSRF token (header)
$t->post_ok('/forgery' => {'X-CSRF-Token' => $token} => form => {foo => 'bar'})
  ->status_is(200)->content_unlike(qr/Wrong or missing CSRF token!/)
  ->element_exists('[value=bar]')->element_exists_not('.field-with-error');

# Wrong CSRF token (header)
$t->post_ok('/forgery' => {'X-CSRF-Token' => 'abc'} => form => {foo => 'bar'})
  ->status_is(200)->content_like(qr/Wrong or missing CSRF token!/)
  ->element_exists('[value=bar]')->element_exists_not('.field-with-error');

# Missing CSRF token and form
$t->get_ok('/forgery')->status_is(200)
  ->content_unlike(qr/Wrong or missing CSRF token!/)
  ->element_exists_not('.field-with-error');

# Correct CSRF token and missing form
$t->post_ok('/forgery' => {'X-CSRF-Token' => $token})->status_is(200)
  ->content_unlike(qr/Wrong or missing CSRF token!/)
  ->element_exists('.field-with-error');

# Failed validation for all fields (with custom helper)
$t->app->helper(
  tag_with_error => sub {
    my ($c, $tag) = (shift, shift);
    my ($content, %attrs) = (@_ % 2 ? pop : undef, @_);
    $attrs{class}
      .= $attrs{class} ? ' my-field-with-error' : 'my-field-with-error';
    return $c->tag($tag, %attrs, defined $content ? $content : ());
  }
);
$t->get_ok('/?foo=too_long&bar=too_long_too&baz=way_too_long&yada=whatever')
  ->status_is(200)->text_is('div:root' => 'two e:foo')
  ->text_is('label.custom.my-field-with-error[for="foo"]' => '<Foo>')
  ->element_exists('input.custom.my-field-with-error[type="text"]')
  ->element_exists('textarea.my-field-with-error')
  ->text_is('label.custom.my-field-with-error[for="baz"]' => 'Baz')
  ->element_exists('select.my-field-with-error')
  ->element_exists('input.my-field-with-error[type="password"]');

done_testing();

__DATA__

@@ index.html.ep
% if (validation->has_error('foo')) {
  <div>
    %= validation->error('foo')->[0]
    %= validation->error('foo')->[1]
  </div>
% }
%= form_for index => begin
  %= label_for foo => '<Foo>', class => 'custom'
  %= text_field 'foo', class => 'custom', id => 'foo'
  %= text_area 'bar'
  %= label_for baz => (class => 'custom') => begin
    Baz
  % end
  %= select_field baz => [qw(yada yada)], id => 'baz'
  %= password_field 'yada'
% end

@@ upload.html.ep
%= form_for upload => begin
  %= file_field 'foo'
  %= submit_button
% end

@@ forgery.html.ep
%= form_for forgery => begin
  %= 'Wrong or missing CSRF token!' if validation->has_error('csrf_token')
  %= csrf_field
  %= text_field 'foo'
%= end
