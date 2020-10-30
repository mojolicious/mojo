use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use Mojolicious::Lite;

any '/' => {text => 'Hello Test!'};

my $t = Test::Mojo->new;

subtest 'Basics' => sub {
  isa_ok $t->app, 'Mojolicious', 'right class';
  $t->get_ok('/')->status_is(200)->content_is('Hello Test!');
  ok $t->success, 'success';
  $t->handler(sub {1})->status_is(404);
  ok $t->success, 'success';
  $t->handler(sub {0})->status_is(404);
  ok !$t->success, 'no success';
};

subtest 'or' => sub {
  my $or = '';
  $t->success(0)->or(sub { $or .= 'false' })->success(1)->or(sub { $or .= 'true' });
  is $or, 'false', 'right result';
};

my @args;
$t->handler(sub { @args = @_ });

subtest 'get_ok' => sub {
  $t->get_ok('/');
  is_deeply \@args, ['ok', 1, 'GET /'], 'right result';
  is $t->tx->req->method, 'GET', 'right method';
};

subtest 'head_ok' => sub {
  $t->head_ok('/');
  is_deeply \@args, ['ok', 1, 'HEAD /'], 'right result';
  is $t->tx->req->method, 'HEAD', 'right method';
};

subtest 'post_ok' => sub {
  $t->post_ok('/');
  is_deeply \@args, ['ok', 1, 'POST /'], 'right result';
  is $t->tx->req->method, 'POST', 'right method';
};

subtest 'put_ok' => sub {
  $t->put_ok('/');
  is_deeply \@args, ['ok', 1, 'PUT /'], 'right result';
  is $t->tx->req->method, 'PUT', 'right method';
};

subtest 'patch_ok' => sub {
  $t->patch_ok('/');
  is_deeply \@args, ['ok', 1, 'PATCH /'], 'right result';
  is $t->tx->req->method, 'PATCH', 'right method';
};

subtest 'delete_ok' => sub {
  $t->delete_ok('/');
  is_deeply \@args, ['ok', 1, 'DELETE /'], 'right result';
  is $t->tx->req->method, 'DELETE', 'right method';
};

subtest 'options_ok' => sub {
  $t->options_ok('/');
  is_deeply \@args, ['ok', 1, 'OPTIONS /'], 'right result';
  is $t->tx->req->method, 'OPTIONS', 'right method';
};

subtest 'status_is' => sub {
  $t->status_is(200);
  is_deeply \@args, ['is', 200, 200, '200 OK'], 'right result';
  $t->status_is(404, 'some description');
  is_deeply \@args, ['is', 200, 404, 'some description'], 'right result';
};

subtest 'content_is' => sub {
  $t->content_is('Hello Test!');
  is_deeply \@args, ['is', 'Hello Test!', 'Hello Test!', 'exact match for content'], 'right result';
  $t->content_is('Hello Test!', 'some description');
  is_deeply \@args, ['is', 'Hello Test!', 'Hello Test!', 'some description'], 'right result';
};

subtest 'content_isnt' => sub {
  $t->content_isnt('Goodbye Test!');
  is_deeply \@args, ['isnt', 'Hello Test!', 'Goodbye Test!', 'no match for content'], 'right result';
  $t->content_isnt('Goodbye Test!', 'some description');
  is_deeply \@args, ['isnt', 'Hello Test!', 'Goodbye Test!', 'some description'], 'right result';
};

subtest 'content_like' => sub {
  $t->content_like(qr/Hello Test!/);
  is_deeply \@args, ['like', 'Hello Test!', qr/Hello Test!/, 'content is similar'], 'right result';
  $t->content_like(qr/Hello Test!/, 'some description');
  is_deeply \@args, ['like', 'Hello Test!', qr/Hello Test!/, 'some description'], 'right result';
};

subtest 'content_type_is' => sub {
  $t->content_type_is('text/html;charset=UTF-8');
  is_deeply \@args,
    ['is', 'text/html;charset=UTF-8', 'text/html;charset=UTF-8', 'Content-Type: text/html;charset=UTF-8'],
    'right result';
  $t->content_type_is('text/html;charset=UTF-8', 'some description');
  is_deeply \@args, ['is', 'text/html;charset=UTF-8', 'text/html;charset=UTF-8', 'some description'], 'right result';
};

subtest 'content_type_isnt' => sub {
  $t->content_type_isnt('image/png');
  is_deeply \@args, ['isnt', 'text/html;charset=UTF-8', 'image/png', 'not Content-Type: image/png'], 'right result';
  $t->content_type_isnt('image/png', 'some description');
  is_deeply \@args, ['isnt', 'text/html;charset=UTF-8', 'image/png', 'some description'], 'right result';
};

subtest 'content_type_like' => sub {
  $t->content_type_like(qr/text\/html;charset=UTF-8/);
  is_deeply \@args, ['like', 'text/html;charset=UTF-8', qr/text\/html;charset=UTF-8/, 'Content-Type is similar'],
    'right result';
  $t->content_type_like(qr/text\/html;charset=UTF-8/, 'some description');
  is_deeply \@args, ['like', 'text/html;charset=UTF-8', qr/text\/html;charset=UTF-8/, 'some description'],
    'right result';
};

subtest 'content_type_unlike' => sub {
  $t->content_type_unlike(qr/image\/png/);
  is_deeply \@args, ['unlike', 'text/html;charset=UTF-8', qr/image\/png/, 'Content-Type is not similar'],
    'right result';
  $t->content_type_unlike(qr/image\/png/, 'some description');
  is_deeply \@args, ['unlike', 'text/html;charset=UTF-8', qr/image\/png/, 'some description'], 'right result';
};

subtest 'content_unlike' => sub {
  $t->content_unlike(qr/Goodbye Test!/);
  is_deeply \@args, ['unlike', 'Hello Test!', qr/Goodbye Test!/, 'content is not similar'], 'right result';
  $t->content_unlike(qr/Goodbye Test!/, 'some description');
  is_deeply \@args, ['unlike', 'Hello Test!', qr/Goodbye Test!/, 'some description'], 'right result';
};

subtest 'attr_is' => sub {
  $t->tx->res->body('<p id="test">Test</p>');
  $t->attr_is('p', 'id', 'wrong');
  is_deeply \@args, ['is', 'test', 'wrong', 'exact match for attribute "id" at selector "p"'], 'right result';
  $t->attr_is('p', 'id', 'wrong', 'some description');
  is_deeply \@args, ['is', 'test', 'wrong', 'some description'], 'right result';
};

done_testing();
