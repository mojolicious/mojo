use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use Mojolicious::Lite;

any '/' => {text => 'Hello Test!'};

websocket '/websocket' => sub {
  my $c = shift;
  $c->send({text => 'testing message'});
};

any '/sse' => sub {
  my $c = shift;
  $c->write_sse({text => 'One', id => 23});
  $c->write_sse({text => 'Two'});
  $c->write_sse({text => 'Three'});
  $c->write_sse({text => 'Four'});
  $c->finish;
};

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

subtest 'attr_isnt' => sub {
  $t->tx->res->body('<p id="test">Test</p>');
  $t->attr_isnt('p', 'id', 'wrong');
  is_deeply \@args, ['isnt', 'test', 'wrong', 'no match for attribute "id" at selector "p"'], 'right result';
  $t->attr_isnt('p', 'id', 'wrong', 'some description');
  is_deeply \@args, ['isnt', 'test', 'wrong', 'some description'], 'right result';
};

subtest 'attr_like' => sub {
  $t->tx->res->body('<p id="test">Test</p>');
  $t->attr_like('p', 'id', qr/test/);
  is_deeply \@args, ['like', 'test', qr/test/, 'similar match for attribute "id" at selector "p"'], 'right result';
  $t->attr_like('p', 'id', qr/test/, 'some description');
  is_deeply \@args, ['like', 'test', qr/test/, 'some description'], 'right result';
};

subtest 'attr_unlike' => sub {
  $t->tx->res->body('<p id="test">Test</p>');
  $t->attr_unlike('p', 'id', qr/wrong/);
  is_deeply \@args, ['unlike', 'test', qr/wrong/, 'no similar match for attribute "id" at selector "p"'],
    'right result';
  $t->attr_unlike('p', 'id', qr/wrong/, 'some description');
  is_deeply \@args, ['unlike', 'test', qr/wrong/, 'some description'], 'right result';
};

subtest 'header_exists' => sub {
  $t->header_exists('Content-Type');
  is_deeply \@args, ['ok', 1, 'header "Content-Type" exists'], 'right result';
  $t->header_exists('Content-Type', 'some description');
  is_deeply \@args, ['ok', 1, 'some description'], 'right result';
};

subtest 'header_exists_not' => sub {
  $t->header_exists_not('X-Exists-Not');
  is_deeply \@args, ['ok', 1, 'no "X-Exists-Not" header'], 'right result';
  $t->header_exists_not('X-Exists-Not', 'some description');
  is_deeply \@args, ['ok', 1, 'some description'], 'right result';
};

subtest 'header_is' => sub {
  $t->header_is('Content-Type', 'text/html;charset=UTF-8');
  is_deeply \@args,
    ['is', 'text/html;charset=UTF-8', 'text/html;charset=UTF-8', 'Content-Type: text/html;charset=UTF-8'],
    'right result';
  $t->header_is('Content-Type', 'text/html;charset=UTF-8', 'some description');
  is_deeply \@args, ['is', 'text/html;charset=UTF-8', 'text/html;charset=UTF-8', 'some description'], 'right result';
};

subtest 'header_isnt' => sub {
  $t->header_isnt('Content-Type', 'image/png');
  is_deeply \@args, ['isnt', 'text/html;charset=UTF-8', 'image/png', 'not Content-Type: image/png'], 'right result';
  $t->header_isnt('Content-Type', 'image/png', 'some description');
  is_deeply \@args, ['isnt', 'text/html;charset=UTF-8', 'image/png', 'some description'], 'right result';
};

subtest 'header_like' => sub {
  $t->header_like('Content-Type', qr/text\/html;charset=UTF-8/);
  is_deeply \@args, ['like', 'text/html;charset=UTF-8', qr/text\/html;charset=UTF-8/, 'Content-Type is similar'],
    'right result';
  $t->header_like('Content-Type', qr/text\/html;charset=UTF-8/, 'some description');
  is_deeply \@args, ['like', 'text/html;charset=UTF-8', qr/text\/html;charset=UTF-8/, 'some description'],
    'right result';
};

subtest 'header_unlike' => sub {
  $t->header_unlike('Content-Type', qr/image\/png/);
  is_deeply \@args, ['unlike', 'text/html;charset=UTF-8', qr/image\/png/, 'Content-Type is not similar'],
    'right result';
  $t->header_unlike('Content-Type', qr/image\/png/, 'some description');
  is_deeply \@args, ['unlike', 'text/html;charset=UTF-8', qr/image\/png/, 'some description'], 'right result';
};

subtest 'message_is' => sub {
  $t->websocket_ok('/websocket')->message_ok->message_is('testing message');
  is_deeply \@args, ['is', 'testing message', 'testing message', 'exact match for message'], 'right result';
  $t->websocket_ok('/websocket')->message_ok->message_is('testing message', 'some description');
  is_deeply \@args, ['is', 'testing message', 'testing message', 'some description'], 'right result';
  $t->websocket_ok('/websocket')->message_ok->message_is('incorrect testing message');
  is_deeply \@args, ['is', 'testing message', 'incorrect testing message', 'exact match for message'], 'right result';
};

subtest 'message_isnt' => sub {
  $t->websocket_ok('/websocket')->message_ok->message_isnt('testing message');
  is_deeply \@args, ['isnt', 'testing message', 'testing message', 'no match for message'], 'right result.';
  $t->websocket_ok('/websocket')->message_ok->message_isnt('testing message', 'some description');
  is_deeply \@args, ['isnt', 'testing message', 'testing message', 'some description'], 'right result';
  $t->websocket_ok('/websocket')->message_ok->message_isnt('incorrect testing message');
  is_deeply \@args, ['isnt', 'testing message', 'incorrect testing message', 'no match for message'], 'right result';
};

subtest 'message_like' => sub {
  $t->websocket_ok('/websocket')->message_ok->message_like(qr/^test/);
  is_deeply \@args, ['like', 'testing message', qr/^test/, 'message is similar'], 'right result';
  $t->websocket_ok('/websocket')->message_ok->message_like(qr/^test/, 'some description');
  is_deeply \@args, ['like', 'testing message', qr/^test/, 'some description'], 'right result';
};

subtest 'message_ok' => sub {
  $t->websocket_ok('/websocket')->message_ok;
  is_deeply \@args, ['ok', !!1, 'message received'], 'right result';
  $t->websocket_ok('/websocket')->message_ok('some description');
  is_deeply \@args, ['ok', !!1, 'some description'], 'right result';
  $t->websocket_ok('/')->message_ok;
  is_deeply \@args, ['ok', !!0, 'message received'], 'right result';
};

subtest 'message_unlike' => sub {
  $t->websocket_ok('/websocket')->message_ok->message_unlike(qr/^test/);
  is_deeply \@args, ['unlike', 'testing message', qr/^test/, 'message is not similar'], 'right result';
  $t->websocket_ok('/websocket')->message_ok->message_unlike(qr/^test/, 'some description');
  is_deeply \@args, ['unlike', 'testing message', qr/^test/, 'some description'], 'right result';
};

subtest 'SSE' => sub {
  subtest 'get_sse_ok' => sub {
    $t->get_sse_ok('/sse');
    is_deeply \@args, ['ok', 1, 'SSE connection established: GET /sse'], 'right result';
    $t->sse_finish_ok;
    is_deeply \@args, ['ok', 1, 'closed SSE connection'], 'right result';
  };

  subtest 'post_sse_ok' => sub {
    $t->post_sse_ok('/sse');
    is_deeply \@args, ['ok', 1, 'SSE connection established: POST /sse'], 'right result';
    $t->sse_ok->sse_ok->sse_ok->sse_ok->sse_finished_ok;
    is_deeply \@args, ['ok', 1, 'SSE connection has been closed'], 'right result';
  };

  subtest 'sse_id_is' => sub {
    $t->get_sse_ok('/sse')->sse_ok->sse_id_is('Two');
    is_deeply \@args, ['is', 23, 'Two', 'exact match for SSE event id'], 'right result';
    $t->sse_id_is('Two', 'some description');
    is_deeply \@args, ['is', 23, 'Two', 'some description'], 'right result';
    $t->sse_finish_ok;
  };

  subtest 'sse_id_isnt' => sub {
    $t->get_sse_ok('/sse')->sse_ok->sse_id_isnt('Two');
    is_deeply \@args, ['isnt', 23, 'Two', 'no match for SSE event id'], 'right result';
    $t->sse_id_isnt('Two', 'some description');
    is_deeply \@args, ['isnt', 23, 'Two', 'some description'], 'right result';
    $t->sse_finish_ok;
  };

  subtest 'sse_type_is' => sub {
    $t->get_sse_ok('/sse')->sse_ok->sse_type_is('Two');
    is_deeply \@args, ['is', 'message', 'Two', 'exact match for SSE event type'], 'right result';
    $t->sse_type_is('Two', 'some description');
    is_deeply \@args, ['is', 'message', 'Two', 'some description'], 'right result';
    $t->sse_finish_ok;
  };

  subtest 'sse_type_isnt' => sub {
    $t->get_sse_ok('/sse')->sse_ok->sse_type_isnt('Two');
    is_deeply \@args, ['isnt', 'message', 'Two', 'no match for SSE event type'], 'right result';
    $t->sse_type_isnt('Two', 'some description');
    is_deeply \@args, ['isnt', 'message', 'Two', 'some description'], 'right result';
    $t->sse_finish_ok;
  };

  subtest 'sse_text_is' => sub {
    $t->get_sse_ok('/sse')->sse_ok->sse_text_is('Two');
    is_deeply \@args, ['is', 'One', 'Two', 'exact match for SSE event text'], 'right result';
    $t->sse_text_is('Two', 'some description');
    is_deeply \@args, ['is', 'One', 'Two', 'some description'], 'right result';
    $t->sse_finish_ok;
  };

  subtest 'sse_text_isnt' => sub {
    $t->get_sse_ok('/sse')->sse_ok->sse_text_isnt('Two');
    is_deeply \@args, ['isnt', 'One', 'Two', 'no match for SSE event text'], 'right result';
    $t->sse_text_isnt('Two', 'some description');
    is_deeply \@args, ['isnt', 'One', 'Two', 'some description'], 'right result';
    $t->sse_finish_ok;
  };

  subtest 'sse_text_like' => sub {
    $t->get_sse_ok('/sse')->sse_ok->sse_text_like(qr/Two/);
    is_deeply \@args, ['like', 'One', qr/Two/, 'similar match for SSE event text'], 'right result';
    $t->sse_text_like(qr/Two/, 'some description');
    is_deeply \@args, ['like', 'One', qr/Two/, 'some description'], 'right result';
    $t->sse_finish_ok;
  };

  subtest 'sse_text_unlike' => sub {
    $t->get_sse_ok('/sse')->sse_ok->sse_text_unlike(qr/Two/);
    is_deeply \@args, ['unlike', 'One', qr/Two/, 'no similar match for SSE event text'], 'right result';
    $t->sse_text_unlike(qr/Two/, 'some description');
    is_deeply \@args, ['unlike', 'One', qr/Two/, 'some description'], 'right result';
    $t->sse_finish_ok;
  };
};

done_testing();
