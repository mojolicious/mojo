use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use Mojolicious::Lite;

any '/' => {text => 'Hello Test!'};

websocket '/websocket' => sub {
  my $c = shift;
  $c->send({text => 'testing message'});
};

get '/html' => sub {
  my $c = shift;
  $c->session(visited => 1);
  $c->render(inline => '<div><p id="a">One</p><p>Two</p></div>');
};

get '/json' => {json => {foo => [1, 2, 3], bar => 'baz'}};

websocket '/echo' => sub {
  my $c = shift;
  $c->on(binary => sub { $c->send({binary => pop}) });
  $c->on(text   => sub { $c->send(pop) });
};

websocket '/close' => sub { shift->finish(4000) };

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

subtest 'query_ok' => sub {
  $t->query_ok('/');
  is_deeply \@args, ['ok', 1, 'QUERY /'], 'right result';
  is $t->tx->req->method, 'QUERY', 'right method';
};

subtest 'request_ok' => sub {
  $t->request_ok($t->ua->build_tx(GET => '/'));
  is_deeply \@args, ['ok', 1, 'GET /'], 'right result';
  is $t->tx->req->method, 'GET', 'right method';
};

subtest 'status_is' => sub {
  $t->status_is(200);
  is_deeply \@args, ['is', 200, 200, '200 OK'], 'right result';
  $t->status_is(404, 'some description');
  is_deeply \@args, ['is', 200, 404, 'some description'], 'right result';
};

subtest 'status_isnt' => sub {
  $t->status_isnt(404);
  is_deeply \@args, ['isnt', 200, 404, 'not 404 Not Found'], 'right result';
  $t->status_isnt(200, 'some description');
  is_deeply \@args, ['isnt', 200, 200, 'some description'], 'right result';
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

subtest 'text_is' => sub {
  $t->get_ok('/html')->text_is('p', 'One');
  is_deeply \@args, ['is', 'One', 'One', 'exact match for selector "p"'], 'right result';
  $t->text_is('p', 'Two', 'some description');
  is_deeply \@args, ['is', 'One', 'Two', 'some description'], 'right result';
  $t->text_is('span', 'One');
  is_deeply \@args, ['is', undef, 'One', 'exact match for selector "span"'], 'right result';
};

subtest 'text_isnt' => sub {
  $t->get_ok('/html')->text_isnt('p', 'Two');
  is_deeply \@args, ['isnt', 'One', 'Two', 'no match for selector "p"'], 'right result';
  $t->text_isnt('p', 'Two', 'some description');
  is_deeply \@args, ['isnt', 'One', 'Two', 'some description'], 'right result';
};

subtest 'text_like' => sub {
  $t->get_ok('/html')->text_like('p', qr/On/);
  is_deeply \@args, ['like', 'One', qr/On/, 'similar match for selector "p"'], 'right result';
  $t->text_like('p', qr/On/, 'some description');
  is_deeply \@args, ['like', 'One', qr/On/, 'some description'], 'right result';
};

subtest 'text_unlike' => sub {
  $t->get_ok('/html')->text_unlike('p', qr/Tw/);
  is_deeply \@args, ['unlike', 'One', qr/Tw/, 'no similar match for selector "p"'], 'right result';
  $t->text_unlike('p', qr/Tw/, 'some description');
  is_deeply \@args, ['unlike', 'One', qr/Tw/, 'some description'], 'right result';
};

subtest 'element_exists' => sub {
  $t->get_ok('/html')->element_exists('p#a');
  is $args[0], 'ok', 'right test';
  isa_ok $args[1], 'Mojo::DOM', 'right element';
  is $args[1]->text, 'One',                               'right text';
  is $args[2],       'element for selector "p#a" exists', 'right description';
  $t->element_exists('span', 'some description');
  is_deeply \@args, ['ok', undef, 'some description'], 'right result';
};

subtest 'element_exists_not' => sub {
  $t->get_ok('/html')->element_exists_not('span');
  is_deeply \@args, ['ok', 1, 'no element for selector "span"'], 'right result';
  $t->element_exists_not('p', 'some description');
  is_deeply \@args, ['ok', '', 'some description'], 'right result';
};

subtest 'element_count_is' => sub {
  $t->get_ok('/html')->element_count_is('p', 2);
  is_deeply \@args, ['is', 2, 2, 'element count for selector "p"'], 'right result';
  $t->element_count_is('span', 1, 'some description');
  is_deeply \@args, ['is', 0, 1, 'some description'], 'right result';
};

subtest 'json_has' => sub {
  $t->get_ok('/json')->json_has('/foo');
  is_deeply \@args, ['ok', 1, 'has value for JSON Pointer "/foo"'], 'right result';
  $t->json_has('/missing', 'some description');
  is_deeply \@args, ['ok', '', 'some description'], 'right result';
};

subtest 'json_hasnt' => sub {
  $t->get_ok('/json')->json_hasnt('/missing');
  is_deeply \@args, ['ok', 1, 'has no value for JSON Pointer "/missing"'], 'right result';
  $t->json_hasnt('/foo', 'some description');
  is_deeply \@args, ['ok', '', 'some description'], 'right result';
};

subtest 'json_is' => sub {
  $t->get_ok('/json')->json_is('/foo', [1, 2, 3]);
  is_deeply \@args, ['is_deeply', [1, 2, 3], [1, 2, 3], 'exact match for JSON Pointer "/foo"'], 'right result';
  $t->json_is('/foo/1', 2, 'some description');
  is_deeply \@args, ['is_deeply', 2, 2, 'some description'], 'right result';
  $t->json_is({foo => [1, 2, 3], bar => 'baz'});
  is_deeply \@args,
    ['is_deeply', {foo => [1, 2, 3], bar => 'baz'}, {foo => [1, 2, 3], bar => 'baz'},
    'exact match for JSON Pointer ""'], 'right result';
};

subtest 'json_like' => sub {
  $t->get_ok('/json')->json_like('/bar', qr/baz/);
  is_deeply \@args, ['like', 'baz', qr/baz/, 'similar match for JSON Pointer "/bar"'], 'right result';
  $t->json_like('/bar', qr/baz/, 'some description');
  is_deeply \@args, ['like', 'baz', qr/baz/, 'some description'], 'right result';
};

subtest 'json_unlike' => sub {
  $t->get_ok('/json')->json_unlike('/bar', qr/yada/);
  is_deeply \@args, ['unlike', 'baz', qr/yada/, 'no similar match for JSON Pointer "/bar"'], 'right result';
  $t->json_unlike('/bar', qr/yada/, 'some description');
  is_deeply \@args, ['unlike', 'baz', qr/yada/, 'some description'], 'right result';
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

subtest 'send_ok' => sub {
  $t->websocket_ok('/echo')->send_ok('hi');
  is_deeply \@args, ['ok', 1, 'send message'], 'right result';
  $t->send_ok('hi', 'some description');
  is_deeply \@args, ['ok', 1, 'some description'], 'right result';
  $t->finish_ok;
  $t->get_ok('/')->send_ok('hi');
  is_deeply \@args, ['ok', 0, 'send message'], 'right result';
};

subtest 'Message type checks' => sub {
  $t->websocket_ok('/echo')->send_ok({binary => 'bin'})->message_ok->message_is({binary => 'bin'});
  is_deeply \@args, ['is', 'bin', 'bin', 'exact match for message'], 'right result';
  $t->message_is({text => 'bin'});
  is_deeply \@args, ['is', '', 'bin', 'exact match for message'], 'right result';
  $t->send_ok({text => 'txt'})->message_ok->message_is({text => 'txt'});
  is_deeply \@args, ['is', 'txt', 'txt', 'exact match for message'], 'right result';
  $t->message_is({binary => 'txt'});
  is_deeply \@args, ['is', '', 'txt', 'exact match for message'], 'right result';
  $t->finish_ok;
};

subtest 'json_message_has' => sub {
  $t->websocket_ok('/echo')->send_ok({json => {a => [1, 2]}})->message_ok->json_message_has('/a');
  is_deeply \@args, ['ok', 1, 'has value for JSON Pointer "/a"'], 'right result';
  $t->json_message_has('/b', 'some description');
  is_deeply \@args, ['ok', undef, 'some description'], 'right result';
  $t->finish_ok;
};

subtest 'json_message_hasnt' => sub {
  $t->websocket_ok('/echo')->send_ok({json => {a => [1, 2]}})->message_ok->json_message_hasnt('/b');
  is_deeply \@args, ['ok', 1, 'has no value for JSON Pointer "/b"'], 'right result';
  $t->json_message_hasnt('/a', 'some description');
  is_deeply \@args, ['ok', '', 'some description'], 'right result';
  $t->finish_ok;
};

subtest 'json_message_is' => sub {
  $t->websocket_ok('/echo')->send_ok({json => {a => [1, 2]}})->message_ok->json_message_is('/a', [1, 2]);
  is_deeply \@args, ['is_deeply', [1, 2], [1, 2], 'exact match for JSON Pointer "/a"'], 'right result';
  $t->json_message_is('/a/1', 2, 'some description');
  is_deeply \@args, ['is_deeply', 2, 2, 'some description'], 'right result';
  $t->json_message_is({a => [1, 2]});
  is_deeply \@args, ['is_deeply', {a => [1, 2]}, {a => [1, 2]}, 'exact match for JSON Pointer ""'], 'right result';
  $t->finish_ok;
};

subtest 'json_message_like' => sub {
  $t->websocket_ok('/echo')->send_ok({json => {a => 'test'}})->message_ok->json_message_like('/a', qr/es/);
  is_deeply \@args, ['like', 'test', qr/es/, 'similar match for JSON Pointer "/a"'], 'right result';
  $t->json_message_like('/a', qr/es/, 'some description');
  is_deeply \@args, ['like', 'test', qr/es/, 'some description'], 'right result';
  $t->finish_ok;
};

subtest 'json_message_unlike' => sub {
  $t->websocket_ok('/echo')->send_ok({json => {a => 'test'}})->message_ok->json_message_unlike('/a', qr/yada/);
  is_deeply \@args, ['unlike', 'test', qr/yada/, 'no similar match for JSON Pointer "/a"'], 'right result';
  $t->json_message_unlike('/a', qr/yada/, 'some description');
  is_deeply \@args, ['unlike', 'test', qr/yada/, 'some description'], 'right result';
  $t->finish_ok;
};

subtest 'finish_ok' => sub {
  $t->websocket_ok('/echo')->finish_ok;
  is_deeply \@args, ['ok', 1, 'closed WebSocket'], 'right result';
};

subtest 'finished_ok' => sub {
  $t->websocket_ok('/close')->finished_ok(4000);
  is_deeply \@args, ['ok', 1, 'WebSocket closed with status 4000'], 'right result';
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

subtest 'Descriptions' => sub {
  $t->get_ok('/')->status_is(200, 'ä');
  is_deeply \@args, ['is', 200, 200, "\xc3\xa4"], 'description is encoded';
};

subtest 'reset_session' => sub {
  $t->get_ok('/html');
  ok $t->tx,                     'has transaction';
  ok @{$t->ua->cookie_jar->all}, 'has cookies';
  is $t->reset_session, $t,    'returns itself';
  is $t->tx,            undef, 'no transaction';
  is_deeply $t->ua->cookie_jar->all, [], 'no cookies';
};

subtest 'new' => sub {
  is(Test::Mojo->new->app,      app, 'default application');
  is(Test::Mojo->new(app)->app, app, 'same application');
  my $t2 = Test::Mojo->new(app, {test => 23});
  is $t2->app,                            app, 'same application';
  is $t2->app->config->{test},            23,  'right value';
  is $t2->app->config->{config_override}, 1,   'right value';
};

done_testing();
