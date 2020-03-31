use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use Mojolicious::Lite;

get '/' => {text => 'Hello Test!'};

my $t = Test::Mojo->new;

# Basics
isa_ok $t->app, 'Mojolicious', 'right class';
$t->get_ok('/')->status_is(200)->content_is('Hello Test!');
ok $t->success, 'success';
$t->handler(sub {1})->status_is(404);
ok $t->success, 'success';
$t->handler(sub {0})->status_is(404);
ok !$t->success, 'no success';

# get_ok
my @args;
$t->handler(sub { @args = @_ });
$t->get_ok('/');
is_deeply \@args, ['ok', 1, 'GET /'], 'right result';

# status_is
$t->status_is(200);
is_deeply \@args, ['is', 200, 200, '200 OK'], 'right result';
$t->status_is(404);
is_deeply \@args, ['is', 200, 404, '404 Not Found'], 'right result';

# content_is
$t->content_is('Hello Test!');
is_deeply \@args,
  ['is', 'Hello Test!', 'Hello Test!', 'exact match for content'],
  'right result';

done_testing();
