use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use Mojolicious::Lite;

any '/' => {text => 'Hello Test!'};

my $t = Test::Mojo->new;

# Basics
isa_ok $t->app, 'Mojolicious', 'right class';
$t->get_ok('/')->status_is(200)->content_is('Hello Test!');
ok $t->success, 'success';
$t->handler(sub {1})->status_is(404);
ok $t->success, 'success';
$t->handler(sub {0})->status_is(404);
ok !$t->success, 'no success';

# or
my $or = '';
$t->success(0)->or(sub { $or .= 'false' })->success(1)
  ->or(sub { $or .= 'true' });
is $or, 'false', 'right result';

# get_ok
my @args;
$t->handler(sub { @args = @_ });
$t->get_ok('/');
is_deeply \@args, ['ok', 1, 'GET /'], 'right result';
is $t->tx->req->method, 'GET', 'right method';

# head_ok
$t->head_ok('/');
is_deeply \@args, ['ok', 1, 'HEAD /'], 'right result';
is $t->tx->req->method, 'HEAD', 'right method';

# post_ok
$t->post_ok('/');
is_deeply \@args, ['ok', 1, 'POST /'], 'right result';
is $t->tx->req->method, 'POST', 'right method';

# put_ok
$t->put_ok('/');
is_deeply \@args, ['ok', 1, 'PUT /'], 'right result';
is $t->tx->req->method, 'PUT', 'right method';

# patch_ok
$t->patch_ok('/');
is_deeply \@args, ['ok', 1, 'PATCH /'], 'right result';
is $t->tx->req->method, 'PATCH', 'right method';

# delete_ok
$t->delete_ok('/');
is_deeply \@args, ['ok', 1, 'DELETE /'], 'right result';
is $t->tx->req->method, 'DELETE', 'right method';

# options_ok
$t->options_ok('/');
is_deeply \@args, ['ok', 1, 'OPTIONS /'], 'right result';
is $t->tx->req->method, 'OPTIONS', 'right method';

# status_is
$t->status_is(200);
is_deeply \@args, ['is', 200, 200, '200 OK'], 'right result';
$t->status_is(404, 'some description');
is_deeply \@args, ['is', 200, 404, 'some description'], 'right result';

# content_is
$t->content_is('Hello Test!');
is_deeply \@args,
  ['is', 'Hello Test!', 'Hello Test!', 'exact match for content'],
  'right result';
$t->content_is('Hello Test!', 'some description');
is_deeply \@args, ['is', 'Hello Test!', 'Hello Test!', 'some description'],
  'right result';

done_testing();
