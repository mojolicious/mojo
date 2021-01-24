use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::Mojo;
use Test::More;
use Mojo::Asset::Memory;
use Mojo::Upload;
use Mojolicious::Lite;

# Custom check
app->validator->add_check(two => sub { length $_[2] == 2 ? undef : "e:$_[1]" });

any '/' => sub {
  my $c = shift;

  my $v = $c->validation;
  return $c->render unless $v->has_data;

  $v->required('foo')->two->in('☃☃');
  $v->optional('bar')->two;
  $v->optional('baz')->two;
  $v->optional('yada')->two;
} => 'index';

any '/upload' => sub {
  my $c = shift;
  my $v = $c->validation;
  return $c->render unless $v->has_data;
  $v->required('foo')->upload;
};

any '/forgery' => sub {
  my $c = shift;
  my $v = $c->validation;
  return $c->render unless $v->has_data;
  $v->csrf_protect->required('foo');
};

my $t = Test::Mojo->new;

subtest 'Required and optional values' => sub {
  my $v = $t->app->validation->input({foo => 'bar', baz => 'yada'});
  is_deeply $v->passed, [], 'no names';
  is_deeply $v->failed, [], 'no names';
  is $v->param('foo'), undef, 'no value';
  is_deeply $v->every_param('foo'), [], 'no values';
  ok $v->required('foo')->is_valid, 'valid';
  is_deeply $v->output, {foo => 'bar'}, 'right result';
  is $v->param, 'bar', 'right value';
  is $v->param('foo'), 'bar', 'right value';
  is_deeply $v->every_param, ['bar'], 'right values';
  is_deeply $v->every_param('foo'), ['bar'], 'right values';
  is_deeply $v->passed, ['foo'], 'right names';
  ok !$v->has_error, 'no error';
  ok $v->optional('baz')->is_valid, 'valid';
  is_deeply $v->output, {foo => 'bar', baz => 'yada'}, 'right result';
  is $v->param('baz'), 'yada', 'right value';
  is_deeply $v->passed, [qw(baz foo)], 'right names';
  ok !$v->has_error, 'no error';
  ok !$v->optional('does_not_exist')->is_valid, 'not valid';
  is_deeply $v->output, {foo => 'bar', baz => 'yada'}, 'right result';
  ok !$v->has_error, 'no error';
  ok !$v->required('does_not_exist')->is_valid, 'not valid';
  is_deeply $v->output, {foo => 'bar', baz => 'yada'}, 'right result';
  ok $v->has_error, 'has error';
  is_deeply $v->error('does_not_exist'), ['required'], 'right error';
  $v = $t->app->validation->input({foo => [], bar => ['a'], baz => undef, yada => [undef]});
  ok !$v->optional('foo')->is_valid, 'not valid';
  is_deeply $v->output, {}, 'right result';
  ok !$v->has_error, 'no error';
  ok !$v->optional('baz')->is_valid, 'not valid';
  is_deeply $v->output, {}, 'right result';
  ok !$v->has_error, 'no error';
  ok !$v->optional('yada')->is_valid, 'not valid';
  is_deeply $v->output, {}, 'right result';
  ok !$v->has_error, 'no error';
  ok $v->optional('bar')->is_valid, 'valid';
  is_deeply $v->output, {bar => ['a']}, 'right result';
  ok !$v->in('c')->is_valid, 'not valid';
  is_deeply $v->output, {}, 'right result';
  ok $v->has_error, 'has error';
};

subtest 'Empty string' => sub {
  my $v = $t->app->validation->input({foo => ''});
  ok $v->optional('foo')->is_valid, 'valid';
  is_deeply $v->output, {foo => ''}, 'right result';
};

subtest 'Equal to' => sub {
  my $v = $t->app->validation->input({foo => 'bar', baz => 'bar', yada => 'yada'});
  ok $v->optional('foo')->equal_to('baz')->is_valid, 'valid';
  is_deeply $v->output, {foo => 'bar'}, 'right result';
  ok !$v->has_error, 'no error';
  ok !$v->optional('baz')->equal_to('does_not_exist')->is_valid, 'not valid';
  is_deeply $v->output, {foo => 'bar'}, 'right result';
  ok $v->has_error, 'has error';
  is_deeply $v->error('baz'), [qw(equal_to 1 does_not_exist)], 'right error';
  ok !$v->optional('yada')->equal_to('foo')->is_valid, 'not valid';
  is_deeply $v->output, {foo => 'bar'}, 'right result';
  ok $v->has_error, 'has error';
  is_deeply $v->error('yada'), [qw(equal_to 1 foo)], 'right error';
  is_deeply $v->failed, [qw(baz yada)], 'right names';
};

subtest 'In' => sub {
  my $v = $t->app->validation->input({foo => [qw(bar whatever)], baz => [qw(yada ohoh)]});
  ok $v->required('foo')->in(qw(23 bar whatever))->is_valid, 'valid';
  is_deeply $v->every_param('foo'), [qw(bar whatever)], 'right results';
  is $v->param('foo'), 'whatever', 'right result';
  is_deeply $v->output, {foo => [qw(bar whatever)]}, 'right result';
  ok !$v->has_error, 'no error';
  ok !$v->required('baz')->in(qw(yada whatever))->is_valid, 'not valid';
  is_deeply $v->output, {foo => [qw(bar whatever)]}, 'right result';
  ok $v->has_error, 'has error';
  is_deeply $v->error('baz'), [qw(in 1 yada whatever)], 'right error';
  is_deeply $v->failed, ['baz'], 'right names';
};

subtest 'Like' => sub {
  my $v = $t->app->validation->input({foo => 'bar', baz => 'yada'});
  ok $v->required('foo')->like(qr/^b/)->is_valid, 'valid';
  is_deeply $v->output, {foo => 'bar'}, 'right result';
  ok !$v->has_error, 'no error';
  my $re = qr/ar$/;
  ok !$v->required('baz')->like($re)->is_valid, 'not valid';
  is_deeply $v->output, {foo => 'bar'}, 'right result';
  ok $v->has_error, 'has error';
  is_deeply $v->error('baz'), ['like', 1, $re], 'right error';
};

subtest 'Num' => sub {
  my $v = $t->app->validation->input({foo => 23, bar => 0, baz => 'fail'});
  ok $v->required('foo')->num->is_valid, 'valid';
  is_deeply $v->output, {foo => 23}, 'right result';
  ok $v->required('bar')->num->is_valid, 'valid';
  is_deeply $v->output, {foo => 23, bar => 0}, 'right result';
  ok !$v->has_error, 'no error';
  ok !$v->required('baz')->num->is_valid, 'not valid';
  is_deeply $v->error('baz'), [qw(num 1)], 'right error';
  is_deeply $v->failed, ['baz'], 'right names';
  $v = $t->app->validation->input({foo => 23});
  ok $v->required('foo')->num(22, 24)->is_valid, 'valid';
  $v = $t->app->validation->input({foo => 23});
  ok $v->required('foo')->num(23, 24)->is_valid, 'valid';
  $v = $t->app->validation->input({foo => 23});
  ok $v->required('foo')->num(22, 23)->is_valid, 'valid';
  $v = $t->app->validation->input({foo => 23});
  ok !$v->required('foo')->num(24, 25)->is_valid, 'not valid';
  ok $v->has_error, 'has error';
  is_deeply $v->error('foo'), [qw(num 1 24 25)], 'right error';
  $v = $t->app->validation->input({foo => 23});
  ok $v->required('foo')->num(22, undef)->is_valid, 'valid';
  $v = $t->app->validation->input({foo => 23});
  ok $v->required('foo')->num(23, undef)->is_valid, 'valid';
  $v = $t->app->validation->input({foo => 23});
  ok !$v->required('foo')->num(24, undef)->is_valid, 'not valid';
  ok $v->has_error, 'has error';
  is_deeply $v->error('foo'), ['num', 1, 24, undef], 'right error';
  $v = $t->app->validation->input({foo => 23});
  ok $v->required('foo')->num(undef, 24)->is_valid, 'valid';
  $v = $t->app->validation->input({foo => 23});
  ok $v->required('foo')->num(undef, 23)->is_valid, 'valid';
  $v = $t->app->validation->input({foo => 23});
  ok !$v->required('foo')->num(undef, 22)->is_valid, 'not valid';
  ok $v->has_error, 'has error';
  is_deeply $v->error('foo'), ['num', 1, undef, 22], 'right error';
  $v = $t->app->validation->input({foo => -5});
  ok $v->required('foo')->num->is_valid, 'valid';
  ok $v->required('foo')->num(undef, -1)->is_valid,    'valid';
  ok $v->required('foo')->num(-10,   10)->is_valid,    'valid';
  ok $v->required('foo')->num(-20,   undef)->is_valid, 'valid';
};

subtest 'Size' => sub {
  my $v = $t->app->validation->input({foo => 'bar', baz => 'yada', yada => 'yada'});
  ok $v->required('foo')->size(1, 3)->is_valid, 'valid';
  is_deeply $v->output, {foo => 'bar'}, 'right result';
  ok !$v->has_error, 'no error';
  ok !$v->required('baz')->size(1, 3)->is_valid, 'not valid';
  is_deeply $v->output, {foo => 'bar'}, 'right result';
  ok $v->has_error, 'has error';
  is_deeply $v->error('baz'), [qw(size 1 1 3)], 'right error';
  ok !$v->required('yada')->size(5, 10)->is_valid, 'not valid';
  is $v->topic, 'yada', 'right topic';
  ok $v->has_error('baz'), 'has error';
  is_deeply $v->output, {foo => 'bar'}, 'right result';
  ok $v->has_error, 'has error';
  is_deeply $v->error('yada'), [qw(size 1 5 10)], 'right error';
  ok $v->required('foo')->size(1, undef)->is_valid, 'valid';
  ok !$v->required('foo')->size(4, undef)->is_valid, 'not valid';
  ok $v->required('foo')->size(undef, 4)->is_valid, 'valid';
  ok $v->required('foo')->size(undef, 3)->is_valid, 'valid';
  ok !$v->required('foo')->size(undef, 2)->is_valid, 'not valid';
};

subtest 'Upload' => sub {
  my $v
    = $t->app->validation->input({
    foo => Mojo::Upload->new, bar => [Mojo::Upload->new, Mojo::Upload->new], baz => [Mojo::Upload->new, 'test']
    });
  ok $v->required('foo')->upload->is_valid, 'valid';
  ok $v->required('bar')->upload->is_valid, 'valid';
  ok $v->required('baz')->is_valid, 'valid';
  ok !$v->has_error, 'no error';
  ok !$v->upload->is_valid, 'not valid';
  ok $v->has_error, 'has error';
  is_deeply $v->error('baz'), [qw(upload 1)], 'right error';
  is_deeply $v->failed, ['baz'], 'right names';
};

subtest 'Upload size' => sub {
  my $v = $t->app->validation->input({
    foo => [Mojo::Upload->new(asset => Mojo::Asset::Memory->new->add_chunk('valid'))],
    bar => [Mojo::Upload->new(asset => Mojo::Asset::Memory->new->add_chunk('not valid'))]
  });
  ok $v->required('foo')->upload->size(1, 6)->is_valid, 'valid';
  ok !$v->has_error, 'no error';
  ok !$v->required('bar')->upload->size(1, 6)->is_valid, 'not valid';
  ok $v->has_error, 'has error';
  is_deeply $v->error('bar'), [qw(size 1 1 6)], 'right error';
  is_deeply $v->failed, ['bar'], 'right names';
};

subtest 'Trim' => sub {
  my $v = $t->app->validation->input({foo => ' bar', baz => ['  0 ', 1]});
  ok $v->required('foo', 'trim')->in('bar')->is_valid, 'valid';
  is_deeply $v->output, {foo => 'bar'}, 'right result';
  ok !$v->optional('missing', 'trim')->is_valid, 'not valid';
  ok $v->optional('baz', 'trim')->like(qr/^\d$/)->is_valid, 'valid';
  is_deeply $v->output, {foo => 'bar', baz => [0, 1]}, 'right result';
  $v = $t->app->validation->input({nothing => '  ', more => [undef]});
  ok $v->required('nothing', 'trim')->is_valid, 'valid';
  is_deeply $v->output, {nothing => ''}, 'right result';
  ok $v->required('nothing')->is_valid, 'valid';
  is_deeply $v->output, {nothing => '  '}, 'right result';
  ok !$v->optional('more', 'trim')->is_valid, 'not valid';
  is_deeply $v->output, {nothing => '  '}, 'right result';
};

subtest 'Not empty' => sub {
  my $v = $t->app->validation->input({foo => 'bar', baz => ''});
  ok $v->required('foo', 'not_empty')->in('bar')->is_valid, 'valid';
  ok !$v->required('baz', 'not_empty')->is_valid, 'not valid';
  ok $v->has_error, 'has error';
  is_deeply $v->error('baz'), ['required'], 'right error';
  is_deeply $v->output, {foo => 'bar'}, 'right result';
  $v = $t->app->validation->input({foo => [' bar'], baz => ['', '  ', undef]});
  ok $v->optional('foo', 'trim', 'not_empty')->is_valid, 'valid';
  ok !$v->optional('baz', 'trim', 'not_empty')->is_valid, 'not valid';
  ok !$v->has_error, 'no error';
  is_deeply $v->output, {foo => ['bar']}, 'right result';
};

subtest 'Custom filter' => sub {
  $t->app->validator->add_filter(quote => sub {qq{$_[1]="$_[2]"}});
  my $v = $t->app->validation->input({foo => [' bar', 'baz']});
  ok $v->required('foo', 'trim', 'quote')->like(qr/"/)->is_valid, 'valid';
  is_deeply $v->output, {foo => ['foo="bar"', 'foo="baz"']}, 'right result';
};

subtest 'Multiple empty values' => sub {
  my $v = $t->app->validation;
  ok !$v->has_data, 'no data';
  $v->input({foo => ['', 'bar', ''], bar => ['', 'baz', undef]});
  ok $v->has_data, 'has data';
  ok $v->required('foo')->is_valid, 'valid';
  ok !$v->required('bar')->is_valid, 'not valid';
  is_deeply $v->output, {foo => ['', 'bar', '']}, 'right result';
  ok $v->has_error, 'has error';
  is_deeply $v->error('bar'), ['required'], 'right error';
};

subtest '0' => sub {
  my $v = $t->app->validation->input({0 => 0});
  ok $v->has_data, 'has data';
  ok $v->required(0)->size(1, 1)->is_valid, 'valid';
  is_deeply $v->output, {0 => 0}, 'right result';
  is $v->param(0), 0, 'right value';
};

subtest 'Custom error' => sub {
  my $v = $t->app->validation->input({foo => 'bar'});
  ok !$v->required('foo')->has_error, 'no error';
  is_deeply $v->output, {foo => 'bar'}, 'right result';
  ok $v->error(foo => ['custom_check'])->has_error, 'has error';
  is_deeply $v->output, {}, 'right result';
  is_deeply $v->size(1, 2)->error('foo'), ['custom_check'], 'right error';
};

subtest 'CSRF protection' => sub {
  my $v = $t->app->validation->input({foo => 'bar'})->csrf_protect;
  ok $v->has_data,  'has data';
  ok $v->has_error, 'has error';
  is_deeply $v->error('csrf_token'), ['csrf_protect'], 'right error';
  $v = $t->app->validation->input({csrf_token => 'abc'});
  ok $v->has_data, 'has data';
  ok $v->csrf_protect->has_error, 'has error';
  ok $v->has_data, 'has data';
  is_deeply $v->error('csrf_token'), ['csrf_protect'], 'right error';
  $v = $t->app->validation->input({csrf_token => 'abc', foo => 'bar'})->csrf_token('cba')->csrf_protect;
  ok $v->has_error, 'has error';
  is_deeply $v->error('csrf_token'), ['csrf_protect'], 'right error';
  $v = $t->app->validation->input({csrf_token => 'abc', foo => 'bar'})->csrf_token('abc')->csrf_protect;
  ok !$v->has_error, 'no error';
  ok $v->required('foo')->is_valid, 'valid';
  is_deeply $v->output, {foo => 'bar'}, 'right result';
  $v = $t->app->validation->input({csrf_token => ['abc', 'abc']})->csrf_token('abc')->csrf_protect;
  ok $v->has_error, 'has error';
  is_deeply $v->error('csrf_token'), ['csrf_protect'], 'right error';
};

subtest 'Missing method and function (AUTOLOAD)' => sub {
  eval { $t->app->validation->missing };
  my $package = 'Mojolicious::Validator::Validation';
  like $@, qr/^Can't locate object method "missing" via package "$package"/, 'right error';
  eval { Mojolicious::Validator::Validation::missing() };
  like $@, qr/^Undefined subroutine &${package}::missing called/, 'right error';
};

subtest 'No validation' => sub {
  $t->get_ok('/')->status_is(200)->element_exists_not('div:root')->text_is('label[for="foo"]' => '<Foo>')
    ->element_exists('input[type="text"]')->element_exists('textarea')->text_like('label[for="baz"]' => qr/Baz/)
    ->element_exists('select')->element_exists('input[type="password"]');
};

subtest 'Successful validation' => sub {
  $t->get_ok('/' => form => {foo => '☃☃'})->status_is(200)->element_exists_not('div:root')
    ->text_is('label[for="foo"]' => '<Foo>')->element_exists('input[type="text"]')->element_exists('textarea')
    ->text_like('label[for="baz"]' => qr/Baz/)->element_exists('select')->element_exists('input[type="password"]');
};

subtest 'Validation failed for required fields' => sub {
  $t->post_ok('/' => form => {foo => 'no'})->status_is(200)->text_like('div:root' => qr/in.+1/s)
    ->text_is('label.custom.field-with-error[for="foo"]' => '<Foo>')
    ->element_exists('input.custom.field-with-error[type="text"][value="no"]')
    ->element_exists_not('textarea.field-with-error')->element_exists_not('label.custom.field-with-error[for="baz"]')
    ->element_exists_not('select.field-with-error')->element_exists_not('input.field-with-error[type="password"]')
    ->element_count_is('.field-with-error', 2)->element_count_is('.field-with-error', 2, 'with description');
};

subtest 'Successful file upload' => sub {
  $t->post_ok('/upload' => form => {foo => {content => 'bar', filename => 'test.txt'}})
    ->element_exists_not('.field-with-error');
};

subtest 'Successful file upload (multiple files)' => sub {
  $t->post_ok('/upload' => form =>
      {foo => [{content => 'One', filename => 'one.txt'}, {content => 'Two', filename => 'two.txt'}]})
    ->element_exists_not('.field-with-error');
};

subtest 'Failed file upload' => sub {
  $t->post_ok('/upload' => form => {foo => 'bar'})->element_exists('.field-with-error');
};

subtest 'Failed file upload (multiple files)' => sub {
  $t->post_ok('/upload' => form => {foo => ['one', 'two']})->element_exists('.field-with-error');
};

subtest 'Missing CSRF token' => sub {
  $t->get_ok('/forgery' => form => {foo => 'bar'})->status_is(200)->content_like(qr/Wrong or missing CSRF token!/)
    ->element_exists('[value=bar]')->element_exists_not('.field-with-error');
};

subtest 'Correct CSRF token' => sub {
  my $token = $t->ua->get('/forgery')->res->dom->at('[name=csrf_token]')->val;
  $t->post_ok('/forgery' => form => {csrf_token => $token, foo => 'bar'})->status_is(200)
    ->content_unlike(qr/Wrong or missing CSRF token!/)->element_exists('[value=bar]')
    ->element_exists_not('.field-with-error')->element_count_is('[name=csrf_token]', 2)->element_count_is('form', 2)
    ->element_exists('form > input[name=csrf_token] + input[type=submit]');
  is $t->tx->res->dom->find('[name=csrf_token]')->[0]->val, $t->tx->res->dom->find('[name=csrf_token]')->[1]->val,
    'same token';
};

subtest 'Correct CSRF token (header)' => sub {
  my $token = $t->ua->get('/forgery')->res->dom->at('[name=csrf_token]')->val;
  $t->post_ok('/forgery' => {'X-CSRF-Token' => $token} => form => {foo => 'bar'})->status_is(200)
    ->content_unlike(qr/Wrong or missing CSRF token!/)->element_exists('[value=bar]')
    ->element_exists_not('.field-with-error');
};

subtest 'Wrong CSRF token (header)' => sub {
  $t->post_ok('/forgery' => {'X-CSRF-Token' => 'abc'} => form => {foo => 'bar'})->status_is(200)
    ->content_like(qr/Wrong or missing CSRF token!/)->element_exists('[value=bar]')
    ->element_exists_not('.field-with-error');
};

subtest 'Missing CSRF token and form' => sub {
  $t->get_ok('/forgery')->status_is(200)->content_unlike(qr/Wrong or missing CSRF token!/)
    ->element_exists_not('.field-with-error');
};

subtest 'Correct CSRF token and missing form' => sub {
  my $token = $t->ua->get('/forgery')->res->dom->at('[name=csrf_token]')->val;
  $t->post_ok('/forgery' => {'X-CSRF-Token' => $token})->status_is(200)
    ->content_unlike(qr/Wrong or missing CSRF token!/)->element_exists('.field-with-error');
};

subtest 'Failed validation for all fields (with custom helper)' => sub {
  $t->app->helper(
    tag_with_error => sub {
      my ($c, $tag) = (shift, shift);
      my ($content, %attrs) = (@_ % 2 ? pop : undef, @_);
      $attrs{class} .= $attrs{class} ? ' my-field-with-error' : 'my-field-with-error';
      return $c->tag($tag, %attrs, defined $content ? $content : ());
    }
  );
  $t->get_ok('/?foo=too_long&bar=too_long_too&baz=way_too_long&yada=whatever')->status_is(200)
    ->text_like('div:root' => qr/two.+e:foo/s)->text_is('label.custom.my-field-with-error[for="foo"]' => '<Foo>')
    ->element_exists('input.custom.my-field-with-error[type="text"]')->element_exists('textarea.my-field-with-error')
    ->text_like('label.custom.my-field-with-error[for="baz"]' => qr/Baz/)->element_exists('select.my-field-with-error')
    ->element_exists('input.my-field-with-error[type="password"]');
};

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
%= csrf_button_to Root => '/'
