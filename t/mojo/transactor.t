use Mojo::Base -strict;

use Test::More;
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Transaction::WebSocket;
use Mojo::URL;
use Mojo::UserAgent::Transactor;
use Mojo::Util qw(b64_decode encode);

# Custom content generator
my $t = Mojo::UserAgent::Transactor->new;
$t->add_generator(
  reverse => sub {
    my ($t, $tx, $content) = @_;
    $tx->req->body(scalar reverse $content);
  }
);

# Simple GET
my $tx = $t->tx(GET => 'mojolicio.us/foo.html?bar=baz');
is $tx->req->url->to_abs, 'http://mojolicio.us/foo.html?bar=baz', 'right URL';
is $tx->req->method, 'GET', 'right method';
is $tx->req->headers->accept_encoding, 'gzip', 'right "Accept-Encoding" value';
is $tx->req->headers->user_agent, 'Mojolicious (Perl)',
  'right "User-Agent" value';

# GET with escaped slash
my $url = Mojo::URL->new('http://mojolicio.us');
$url->path->parts(['foo/bar']);
$tx = $t->tx(GET => $url);
is $tx->req->url->to_string, $url->to_string, 'URLs are equal';
is $tx->req->url->path->to_string, $url->path->to_string, 'paths are equal';
is $tx->req->url->path->to_string, 'foo%2Fbar', 'right path';
is $tx->req->method, 'GET', 'right method';

# POST with header
$t->name('MyUA 1.0');
$tx = $t->tx(POST => 'https://mojolicio.us' => {DNT => 1});
is $tx->req->url->to_abs, 'https://mojolicio.us', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->dnt,             1,      'right "DNT" value';
is $tx->req->headers->accept_encoding, 'gzip', 'right "Accept-Encoding" value';
is $tx->req->headers->user_agent, 'MyUA 1.0', 'right "User-Agent" value';

# POST with header and content
$tx = $t->tx(POST => 'https://mojolicio.us' => {DNT => 1} => 'test');
is $tx->req->url->to_abs, 'https://mojolicio.us', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->dnt, 1, 'right "DNT" value';
is $tx->req->body, 'test', 'right content';

# DELETE with content
$tx = $t->tx(DELETE => 'https://mojolicio.us' => 'test');
is $tx->req->url->to_abs, 'https://mojolicio.us', 'right URL';
is $tx->req->method, 'DELETE', 'right method';
is $tx->req->headers->dnt, undef, 'no "DNT" value';
is $tx->req->body, 'test', 'right content';

# PUT with custom content generator
$tx = $t->tx(PUT => 'mojolicio.us', reverse => 'hello!');
is $tx->req->url->to_abs, 'http://mojolicio.us', 'right URL';
is $tx->req->method, 'PUT', 'right method';
is $tx->req->headers->dnt, undef, 'no "DNT" value';
is $tx->req->body, '!olleh', 'right content';
$tx = $t->tx(PUT => 'mojolicio.us', {DNT => 1}, reverse => 'hello!');
is $tx->req->url->to_abs, 'http://mojolicio.us', 'right URL';
is $tx->req->method, 'PUT', 'right method';
is $tx->req->headers->dnt, 1, 'right "DNT" value';
is $tx->req->body, '!olleh', 'right content';

# Simple JSON POST
$tx = $t->tx(POST => 'http://example.com/foo' => json => {test => 123});
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'application/json',
  'right "Content-Type" value';
is_deeply $tx->req->json, {test => 123}, 'right content';
$tx = $t->tx(POST => 'http://example.com/foo' => json => [1, 2, 3]);
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'application/json',
  'right "Content-Type" value';
is_deeply $tx->req->json, [1, 2, 3], 'right content';

# JSON POST with headers
$tx = $t->tx(
  POST => 'http://example.com/foo' => {DNT => 1},
  json => {test                    => 123}
);
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->dnt, 1, 'right "DNT" value';
is $tx->req->headers->content_type, 'application/json',
  'right "Content-Type" value';
is_deeply $tx->req->json, {test => 123}, 'right content';

# JSON POST with custom content type
$tx = $t->tx(POST => 'http://example.com/foo' =>
    {DNT => 1, 'content-type' => 'application/something'} => json => [1, 2],);
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->dnt, 1, 'right "DNT" value';
is $tx->req->headers->content_type, 'application/something',
  'right "Content-Type" value';
is_deeply $tx->req->json, [1, 2], 'right content';

# Simple form (POST)
$tx = $t->tx(POST => 'http://example.com/foo' => form => {test => 123});
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'application/x-www-form-urlencoded',
  'right "Content-Type" value';
is $tx->req->body, 'test=123', 'right content';

# Simple form (GET)
$tx = $t->tx(GET => 'http://example.com/foo' => form => {test => 123});
is $tx->req->url->to_abs, 'http://example.com/foo?test=123', 'right URL';
is $tx->req->method, 'GET', 'right method';
is $tx->req->headers->content_type, undef, 'no "Content-Type" value';
is $tx->req->body, '', 'no content';

# Simple form with multiple values
$tx = $t->tx(
  POST => 'http://example.com/foo' => form => {a => [1, 2, 3], b => 4});
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'application/x-www-form-urlencoded',
  'right "Content-Type" value';
ok !$tx->is_empty, 'transaction is not empty';
is $tx->req->body, 'a=1&a=2&a=3&b=4', 'right content';

# Existing query string (lowercase HEAD)
$tx = $t->tx(head => 'http://example.com?foo=bar' => form => {baz => [1, 2]});
is $tx->req->url->to_abs, 'http://example.com?baz=1&baz=2', 'right URL';
is $tx->req->method, 'head', 'right method';
is $tx->req->headers->content_type, undef, 'no "Content-Type" value';
ok $tx->is_empty, 'transaction is empty';
is $tx->req->body, '', 'no content';

# UTF-8 form
$tx
  = $t->tx(POST => 'http://example.com/foo' => form => {test => 12345678912} =>
    charset => 'UTF-8');
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'application/x-www-form-urlencoded',
  'right "Content-Type" value';
is $tx->req->body, 'test=12345678912', 'right content';

# UTF-8 form with header and custom content type
$tx
  = $t->tx(POST => 'http://example.com/foo' =>
    {Accept => '*/*', 'Content-Type' => 'application/mojo-form'} => form =>
    {test => 123} => charset => 'UTF-8');
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'application/mojo-form',
  'right "Content-Type" value';
is $tx->req->headers->accept, '*/*', 'right "Accept" value';
is $tx->req->body, 'test=123', 'right content';

# Multipart form
$tx = $t->tx(POST => 'http://example.com/foo' =>
    {'Content-Type' => 'multipart/form-data'} => form => {test => 123});
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'multipart/form-data',
  'right "Content-Type" value';
like $tx->req->content->parts->[0]->headers->content_disposition, qr/"test"/,
  'right "Content-Disposition" value';
is $tx->req->content->parts->[0]->asset->slurp, 123, 'right part';
ok !$tx->req->content->parts->[0]->asset->is_file,      'stored in memory';
ok !$tx->req->content->parts->[0]->asset->auto_upgrade, 'no upgrade';
is $tx->req->content->parts->[1], undef, 'no more parts';

# Multipart form with multiple values
$tx
  = $t->tx(POST => 'http://example.com/foo' =>
    {'Content-Type' => 'multipart/form-data'} => form =>
    {a => [1, 2, 3], b => 4});
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'multipart/form-data',
  'right "Content-Type" value';
like $tx->req->content->parts->[0]->headers->content_disposition, qr/"a"/,
  'right "Content-Disposition" value';
is $tx->req->content->parts->[0]->asset->slurp, 1, 'right part';
like $tx->req->content->parts->[1]->headers->content_disposition, qr/"a"/,
  'right "Content-Disposition" value';
is $tx->req->content->parts->[1]->asset->slurp, 2, 'right part';
like $tx->req->content->parts->[2]->headers->content_disposition, qr/"a"/,
  'right "Content-Disposition" value';
is $tx->req->content->parts->[2]->asset->slurp, 3, 'right part';
like $tx->req->content->parts->[3]->headers->content_disposition, qr/"b"/,
  'right "Content-Disposition" value';
is $tx->req->content->parts->[3]->asset->slurp, 4, 'right part';
is $tx->req->content->parts->[4], undef, 'no more parts';
is_deeply $tx->req->every_param('a'), [1, 2, 3], 'right values';
is_deeply [$tx->req->param('b')], [4], 'right values';

# Multipart form with real file and custom header
$tx = $t->tx(POST => 'http://example.com/foo' => form =>
    {mytext => {file => __FILE__, DNT => 1}});
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'multipart/form-data',
  'right "Content-Type" value';
like $tx->req->content->parts->[0]->headers->content_disposition,
  qr/"mytext"/, 'right "Content-Disposition" value';
like $tx->req->content->parts->[0]->headers->content_disposition,
  qr/"transactor.t"/, 'right "Content-Disposition" value';
like $tx->req->content->parts->[0]->asset->slurp, qr/mytext/, 'right part';
ok $tx->req->content->parts->[0]->asset->is_file, 'stored in file';
ok !$tx->req->content->parts->[0]->headers->header('file'), 'no "file" header';
is $tx->req->content->parts->[0]->headers->dnt, 1, 'right "DNT" header';
is $tx->req->content->parts->[1], undef, 'no more parts';

# Multipart form with asset and custom content type
$tx
  = $t->tx(POST => 'http://example.com/foo' =>
    {'Content-Type' => 'multipart/mojo-form'} => form =>
    {mytext => {file => Mojo::Asset::File->new(path => __FILE__)}});
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'multipart/mojo-form',
  'right "Content-Type" value';
like $tx->req->content->parts->[0]->headers->content_disposition,
  qr/"mytext"/, 'right "Content-Disposition" value';
like $tx->req->content->parts->[0]->headers->content_disposition,
  qr/"transactor.t"/, 'right "Content-Disposition" value';
like $tx->req->content->parts->[0]->asset->slurp, qr/mytext/, 'right part';
ok $tx->req->content->parts->[0]->asset->is_file, 'stored in file';
is $tx->req->content->parts->[1], undef, 'no more parts';

# Multipart form with in-memory content
$tx = $t->tx(POST => 'http://example.com/foo' => form =>
    {mytext => {content => 'lalala'}});
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'multipart/form-data',
  'right "Content-Type" value';
like $tx->req->content->parts->[0]->headers->content_disposition, qr/mytext/,
  'right "Content-Disposition" value';
ok !$tx->req->content->parts->[0]->headers->header('content'),
  'no "content" header';
is $tx->req->content->parts->[0]->asset->slurp, 'lalala', 'right part';
ok !$tx->req->content->parts->[0]->asset->is_file,      'stored in memory';
ok !$tx->req->content->parts->[0]->asset->auto_upgrade, 'no upgrade';
is $tx->req->content->parts->[1], undef, 'no more parts';

# Multipart form with filename ("0")
$tx = $t->tx(POST => 'http://example.com/foo' => form =>
    {0 => {content => 'whatever', filename => '0'}});
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'multipart/form-data',
  'right "Content-Type" value';
like $tx->req->content->parts->[0]->headers->content_disposition, qr/0/,
  'right "Content-Disposition" value';
ok !$tx->req->content->parts->[0]->headers->header('filename'),
  'no "filename" header';
is $tx->req->content->parts->[0]->asset->slurp, 'whatever', 'right part';
is $tx->req->content->parts->[1], undef, 'no more parts';
is $tx->req->upload('0')->filename, '0',        'right filename';
is $tx->req->upload('0')->size,     8,          'right size';
is $tx->req->upload('0')->slurp,    'whatever', 'right content';

# Multipart form with asset and filename (UTF-8)
my $snowman = encode 'UTF-8', '☃';
$tx = $t->tx(
  POST => 'http://example.com/foo' => form => {
    '"☃"' => {
      file     => Mojo::Asset::Memory->new->add_chunk('snowman'),
      filename => '"☃".jpg'
    }
  } => charset => 'UTF-8'
);
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'multipart/form-data',
  'right "Content-Type" value';
like $tx->req->content->parts->[0]->headers->content_disposition,
  qr/$snowman/, 'right "Content-Disposition" value';
is $tx->req->content->parts->[0]->asset->slurp, 'snowman', 'right part';
is $tx->req->content->parts->[1], undef, 'no more parts';
is $tx->req->upload('%22☃%22')->filename, '%22☃%22.jpg', 'right filename';
is $tx->req->upload('%22☃%22')->size,     7,               'right size';
is $tx->req->upload('%22☃%22')->slurp,    'snowman',       'right content';

# Multipart form with multiple uploads sharing the same name
$tx = $t->tx(
  POST => 'http://example.com/foo' => form => {
    mytext => [
      {content => 'just',  filename => 'one.txt'},
      {content => 'works', filename => 'two.txt'}
    ]
  }
);
is $tx->req->url->to_abs, 'http://example.com/foo', 'right URL';
is $tx->req->method, 'POST', 'right method';
is $tx->req->headers->content_type, 'multipart/form-data',
  'right "Content-Type" value';
like $tx->req->content->parts->[0]->headers->content_disposition, qr/mytext/,
  'right "Content-Disposition" value';
like $tx->req->content->parts->[0]->headers->content_disposition,
  qr/one\.txt/, 'right "Content-Disposition" value';
is $tx->req->content->parts->[0]->asset->slurp, 'just', 'right part';
like $tx->req->content->parts->[1]->headers->content_disposition, qr/mytext/,
  'right "Content-Disposition" value';
like $tx->req->content->parts->[1]->headers->content_disposition,
  qr/two\.txt/, 'right "Content-Disposition" value';
is $tx->req->content->parts->[1]->asset->slurp, 'works', 'right part';
is $tx->req->content->parts->[2], undef, 'no more parts';

# Simple endpoint
$tx = $t->tx(GET => 'mojolicio.us');
is(($t->endpoint($tx))[0], 'http',         'right scheme');
is(($t->endpoint($tx))[1], 'mojolicio.us', 'right host');
is(($t->endpoint($tx))[2], 80,             'right port');

# Simple endpoint with proxy
$tx = $t->tx(GET => 'http://mojolicio.us');
$tx->req->proxy('http://127.0.0.1:3000');
is(($t->endpoint($tx))[0], 'http',      'right scheme');
is(($t->endpoint($tx))[1], '127.0.0.1', 'right host');
is(($t->endpoint($tx))[2], 3000,        'right port');

# Simple endpoint with SOCKS proxy
$tx = $t->tx(GET => 'http://mojolicio.us');
$tx->req->proxy('socks://127.0.0.1:3000');
is(($t->endpoint($tx))[0], 'http',         'right scheme');
is(($t->endpoint($tx))[1], 'mojolicio.us', 'right host');
is(($t->endpoint($tx))[2], 80,             'right port');

# Simple WebSocket endpoint with proxy
$tx = $t->websocket('ws://mojolicio.us');
$tx->req->proxy('http://127.0.0.1:3000');
is(($t->endpoint($tx))[0], 'http',         'right scheme');
is(($t->endpoint($tx))[1], 'mojolicio.us', 'right host');
is(($t->endpoint($tx))[2], 80,             'right port');

# HTTPS endpoint
$tx = $t->tx(GET => 'HTTPS://mojolicio.us');
is(($t->endpoint($tx))[0], 'https',        'right scheme');
is(($t->endpoint($tx))[1], 'mojolicio.us', 'right host');
is(($t->endpoint($tx))[2], 443,            'right port');

# HTTPS endpoint with proxy
$tx = $t->tx(GET => 'https://mojolicio.us');
$tx->req->proxy('http://127.0.0.1:3000');
is(($t->endpoint($tx))[0], 'https',        'right scheme');
is(($t->endpoint($tx))[1], 'mojolicio.us', 'right host');
is(($t->endpoint($tx))[2], 443,            'right port');

# HTTPS endpoint with SOCKS proxy
$tx = $t->tx(GET => 'https://mojolicio.us');
$tx->req->proxy('socks://127.0.0.1:3000');
is(($t->endpoint($tx))[0], 'https',        'right scheme');
is(($t->endpoint($tx))[1], 'mojolicio.us', 'right host');
is(($t->endpoint($tx))[2], 443,            'right port');

# TLS WebSocket endpoint with proxy
$tx = $t->websocket('WSS://mojolicio.us');
$tx->req->proxy('http://127.0.0.1:3000');
is(($t->endpoint($tx))[0], 'https',        'right scheme');
is(($t->endpoint($tx))[1], 'mojolicio.us', 'right host');
is(($t->endpoint($tx))[2], 443,            'right port');

# Simple peer
$tx = $t->tx(GET => 'mojolicio.us');
is(($t->peer($tx))[0], 'http',         'right scheme');
is(($t->peer($tx))[1], 'mojolicio.us', 'right host');
is(($t->peer($tx))[2], 80,             'right port');

# Simple peer with proxy
$tx = $t->tx(GET => 'http://mojolicio.us');
$tx->req->proxy('http://127.0.0.1:3000');
is(($t->peer($tx))[0], 'http',      'right scheme');
is(($t->peer($tx))[1], '127.0.0.1', 'right host');
is(($t->peer($tx))[2], 3000,        'right port');

# Simple peer with SOCKS proxy
$tx = $t->tx(GET => 'http://mojolicio.us');
$tx->req->proxy('socks://127.0.0.1:3000');
is(($t->peer($tx))[0], 'socks',     'right scheme');
is(($t->peer($tx))[1], '127.0.0.1', 'right host');
is(($t->peer($tx))[2], 3000,        'right port');

# Simple peer with proxy (no port)
$tx = $t->tx(GET => 'http://mojolicio.us');
$tx->req->proxy('http://127.0.0.1');
is(($t->peer($tx))[0], 'http',      'right scheme');
is(($t->peer($tx))[1], '127.0.0.1', 'right host');
is(($t->peer($tx))[2], 80,          'right port');

# Simple peer with HTTPS proxy (no port)
$tx = $t->tx(GET => 'http://mojolicio.us');
$tx->req->proxy('HTTPS://127.0.0.1');
is(($t->peer($tx))[0], 'https',     'right scheme');
is(($t->peer($tx))[1], '127.0.0.1', 'right host');
is(($t->peer($tx))[2], 443,         'right port');

# Simple WebSocket peer with proxy
$tx = $t->websocket('ws://mojolicio.us');
$tx->req->proxy('http://127.0.0.1:3000');
is(($t->peer($tx))[0], 'http',      'right scheme');
is(($t->peer($tx))[1], '127.0.0.1', 'right host');
is(($t->peer($tx))[2], 3000,        'right port');

# HTTPS peer
$tx = $t->tx(GET => 'https://mojolicio.us');
is(($t->peer($tx))[0], 'https',        'right scheme');
is(($t->peer($tx))[1], 'mojolicio.us', 'right host');
is(($t->peer($tx))[2], 443,            'right port');

# HTTPS peer with proxy
$tx = $t->tx(GET => 'https://mojolicio.us');
$tx->req->proxy('http://127.0.0.1:3000');
is(($t->peer($tx))[0], 'http',      'right scheme');
is(($t->peer($tx))[1], '127.0.0.1', 'right host');
is(($t->peer($tx))[2], 3000,        'right port');

# HTTPS peer with SOCKS proxy
$tx = $t->tx(GET => 'https://mojolicio.us');
$tx->req->proxy('socks://127.0.0.1:3000');
is(($t->peer($tx))[0], 'socks',     'right scheme');
is(($t->peer($tx))[1], '127.0.0.1', 'right host');
is(($t->peer($tx))[2], 3000,        'right port');

# TLS WebSocket peer with proxy
$tx = $t->websocket('wss://mojolicio.us');
$tx->req->proxy('http://127.0.0.1:3000');
is(($t->peer($tx))[0], 'http',      'right scheme');
is(($t->peer($tx))[1], '127.0.0.1', 'right host');
is(($t->peer($tx))[2], 3000,        'right port');

# WebSocket handshake
$tx = $t->websocket('ws://127.0.0.1:3000/echo');
ok !$tx->is_websocket, 'not a WebSocket';
is $tx->req->url->to_abs, 'http://127.0.0.1:3000/echo', 'right URL';
is $tx->req->method, 'GET', 'right method';
is $tx->req->headers->connection, 'Upgrade', 'right "Connection" value';
is length(b64_decode $tx->req->headers->sec_websocket_key), 16,
  '16 byte "Sec-WebSocket-Key" value';
ok !$tx->req->headers->sec_websocket_protocol,
  'no "Sec-WebSocket-Protocol" header';
ok $tx->req->headers->sec_websocket_version,
  'has "Sec-WebSocket-Version" value';
is $tx->req->headers->upgrade, 'websocket', 'right "Upgrade" value';
is $t->upgrade($tx), undef, 'not upgraded';
Mojo::Transaction::WebSocket->new(handshake => $tx)->server_handshake;
$tx->res->code(101);
$tx = $t->upgrade($tx);
ok $tx->is_websocket, 'is a WebSocket';

# WebSocket handshake with header
$tx = $t->websocket('wss://127.0.0.1:3000/echo' => {DNT => 1});
is $tx->req->url->to_abs, 'https://127.0.0.1:3000/echo', 'right URL';
is $tx->req->method, 'GET', 'right method';
is $tx->req->headers->dnt,        1,         'right "DNT" value';
is $tx->req->headers->connection, 'Upgrade', 'right "Connection" value';
is length(b64_decode $tx->req->headers->sec_websocket_key), 16,
  '16 byte "Sec-WebSocket-Key" value';
ok !$tx->req->headers->sec_websocket_protocol,
  'no "Sec-WebSocket-Protocol" header';
ok $tx->req->headers->sec_websocket_version,
  'has "Sec-WebSocket-Version" value';
is $tx->req->headers->upgrade, 'websocket', 'right "Upgrade" value';

# WebSocket handshake with protocol
$tx = $t->websocket('wss://127.0.0.1:3000/echo' => ['foo']);
is $tx->req->url->to_abs, 'https://127.0.0.1:3000/echo', 'right URL';
is $tx->req->method, 'GET', 'right method';
is $tx->req->headers->connection, 'Upgrade', 'right "Connection" value';
is length(b64_decode $tx->req->headers->sec_websocket_key), 16,
  '16 byte "Sec-WebSocket-Key" value';
is $tx->req->headers->sec_websocket_protocol, 'foo',
  'right "Sec-WebSocket-Protocol" value';
ok $tx->req->headers->sec_websocket_version,
  'has "Sec-WebSocket-Version" value';
is $tx->req->headers->upgrade, 'websocket', 'right "Upgrade" value';

# WebSocket handshake with header and protocols
$tx = $t->websocket('wss://127.0.0.1:3000/echo' => {DNT => 1} =>
    ['v1.bar.example.com', 'foo', 'v2.baz.example.com']);
is $tx->req->url->to_abs, 'https://127.0.0.1:3000/echo', 'right URL';
is $tx->req->method, 'GET', 'right method';
is $tx->req->headers->dnt,        1,         'right "DNT" value';
is $tx->req->headers->connection, 'Upgrade', 'right "Connection" value';
is length(b64_decode $tx->req->headers->sec_websocket_key), 16,
  '16 byte "Sec-WebSocket-Key" value';
is $tx->req->headers->sec_websocket_protocol,
  'v1.bar.example.com, foo, v2.baz.example.com',
  'right "Sec-WebSocket-Protocol" value';
ok $tx->req->headers->sec_websocket_version,
  'has "Sec-WebSocket-Version" value';
is $tx->req->headers->upgrade, 'websocket', 'right "Upgrade" value';

# Proxy CONNECT
$tx = $t->tx(GET => 'HTTPS://sri:secr3t@mojolicio.us');
$tx->req->proxy('http://sri:secr3t@127.0.0.1:3000');
ok !$tx->req->headers->authorization,       'no "Authorization" header';
ok !$tx->req->headers->proxy_authorization, 'no "Proxy-Authorization" header';
$tx->req->fix_headers;
is $tx->req->headers->authorization, 'Basic c3JpOnNlY3IzdA==',
  'right "Authorization" header';
is $tx->req->headers->proxy_authorization, 'Basic c3JpOnNlY3IzdA==',
  'right "Proxy-Authorization" header';
$tx = $t->proxy_connect($tx);
is $tx->req->method, 'CONNECT', 'right method';
is $tx->req->url->to_abs, 'https://mojolicio.us', 'right URL';
is $tx->req->proxy->to_abs, 'http://sri:secr3t@127.0.0.1:3000',
  'right proxy URL';
ok !$tx->req->headers->authorization,       'no "Authorization" header';
ok !$tx->req->headers->proxy_authorization, 'no "Proxy-Authorization" header';
ok !$tx->req->headers->host,                'no "Host" header';
$tx->req->fix_headers;
ok !$tx->req->headers->authorization, 'no "Authorization" header';
is $tx->req->headers->proxy_authorization, 'Basic c3JpOnNlY3IzdA==',
  'right "Proxy-Authorization" header';
is $tx->req->headers->host, 'mojolicio.us', 'right "Host" header';
is $t->proxy_connect($tx), undef, 'already a CONNECT request';
$tx->req->method('Connect');
is $t->proxy_connect($tx), undef, 'already a CONNECT request';
$tx = $t->tx(GET => 'https://mojolicio.us');
$tx->req->proxy('socks://127.0.0.1:3000');
is $t->proxy_connect($tx), undef, 'using a SOCKS proxy';

# Simple 301 redirect
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo' => {Accept => 'application/json'});
$tx->res->code(301);
$tx->res->headers->location('http://example.com/bar');
is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
is $tx->req->body, '', 'no content';
$tx = $t->redirect($tx);
is $tx->req->method, 'GET', 'right method';
is $tx->req->url->to_abs,     'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, 'application/json',       'right "Accept" value';
is $tx->req->headers->location, undef, 'no "Location" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# 301 redirect with content
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo' => {Accept => '*/*'} => 'whatever');
$tx->res->code(301);
$tx->res->headers->location('http://example.com/bar');
is $tx->req->headers->accept, '*/*', 'right "Accept" value';
is $tx->req->body, 'whatever', 'right content';
$tx = $t->redirect($tx);
is $tx->req->method, 'GET', 'right method';
is $tx->req->url->to_abs, 'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, '*/*', 'right "Accept" value';
is $tx->req->headers->location, undef, 'no "Location" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# 301 redirect with content (DELETE)
$tx = $t->tx(
  DELETE => 'http://mojolicio.us/foo' => {Accept => '*/*'} => 'whatever');
$tx->res->code(301);
$tx->res->headers->location('http://example.com/bar');
is $tx->req->headers->accept, '*/*', 'right "Accept" value';
is $tx->req->body, 'whatever', 'right content';
$tx = $t->redirect($tx);
is $tx->req->method, 'DELETE', 'right method';
is $tx->req->url->to_abs, 'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, '*/*', 'right "Accept" value';
is $tx->req->headers->location, undef, 'no "Location" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# Simple 302 redirect
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo' => {Accept => 'application/json'});
$tx->res->code(302);
$tx->res->headers->location('http://example.com/bar');
is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
is $tx->req->body, '', 'no content';
$tx = $t->redirect($tx);
is $tx->req->method, 'GET', 'right method';
is $tx->req->url->to_abs,     'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, 'application/json',       'right "Accept" value';
is $tx->req->headers->location, undef, 'no "Location" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# 302 redirect (lowecase HEAD)
$tx = $t->tx(head => 'http://mojolicio.us/foo');
$tx->res->code(302);
$tx->res->headers->location('http://example.com/bar');
$tx = $t->redirect($tx);
is $tx->req->method, 'HEAD', 'right method';
is $tx->req->url->to_abs, 'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, undef, 'no "Accept" value';
is $tx->req->headers->location, undef, 'no "Location" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# 302 redirect (dynamic)
$tx = $t->tx(POST => 'http://mojolicio.us/foo');
$tx->res->code(302);
$tx->res->headers->location('http://example.com/bar');
$tx->req->content->write_chunk('whatever' => sub { shift->finish });
$tx = $t->redirect($tx);
is $tx->req->method, 'GET', 'right method';
is $tx->req->url->to_abs, 'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, undef, 'no "Accept" value';
is $tx->req->headers->location, undef, 'no "Location" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# 302 redirect with content
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo' => {Accept => '*/*'} => 'whatever');
$tx->req->fix_headers->headers->content_type('text/plain');
$tx->res->code(302);
$tx->res->headers->location('http://example.com/bar');
is $tx->req->headers->accept,       '*/*',        'right "Accept" value';
is $tx->req->headers->content_type, 'text/plain', 'right "Content-Type" value';
is $tx->req->headers->content_length, 8, 'right "Content-Length" value';
is $tx->req->body, 'whatever', 'right content';
$tx = $t->redirect($tx);
is $tx->req->method, 'GET', 'right method';
is $tx->req->url->to_abs, 'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, '*/*', 'right "Accept" value';
is $tx->req->headers->content_type,   undef, 'no "Content-Type" value';
is $tx->req->headers->content_length, undef, 'no "Content-Length" value';
is $tx->req->headers->location,       undef, 'no "Location" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# Simple 303 redirect
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo' => {Accept => 'application/json'});
$tx->res->code(303);
$tx->res->headers->location('http://example.com/bar');
is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
is $tx->req->body, '', 'no content';
$tx = $t->redirect($tx);
is $tx->req->method, 'GET', 'right method';
is $tx->req->url->to_abs,     'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, 'application/json',       'right "Accept" value';
is $tx->req->headers->location, undef, 'no "Location" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# 303 redirect (dynamic)
$tx = $t->tx(POST => 'http://mojolicio.us/foo');
$tx->res->code(303);
$tx->res->headers->location('http://example.com/bar');
$tx->req->content->write_chunk('whatever' => sub { shift->finish });
$tx = $t->redirect($tx);
is $tx->req->method, 'GET', 'right method';
is $tx->req->url->to_abs, 'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, undef, 'no "Accept" value';
is $tx->req->headers->location, undef, 'no "Location" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# 303 redirect (additional headers)
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo' => {
    Accept        => 'application/json',
    Authorization => 'one',
    Cookie        => 'two',
    Host          => 'three',
    Referer       => 'four'
  }
);
$tx->res->code(303);
$tx->res->headers->location('http://example.com/bar');
is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
is $tx->req->headers->authorization, 'one',   'right "Authorization" value';
is $tx->req->headers->cookie,        'two',   'right "Cookie" value';
is $tx->req->headers->host,          'three', 'right "Host" value';
is $tx->req->headers->referrer,      'four',  'right "Referer" value';
is $tx->req->body, '', 'no content';
$tx = $t->redirect($tx);
is $tx->req->method, 'GET', 'right method';
is $tx->req->url->to_abs,     'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, 'application/json',       'right "Accept" value';
is $tx->req->headers->authorization, undef, 'no "Authorization" value';
is $tx->req->headers->cookie,        undef, 'no "Cookie" value';
is $tx->req->headers->host,          undef, 'no "Host" value';
is $tx->req->headers->location,      undef, 'no "Location" value';
is $tx->req->headers->referrer,      undef, 'no "Referer" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# Simple 307 redirect
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo' => {Accept => 'application/json'});
$tx->res->code(307);
$tx->res->headers->location('http://example.com/bar');
is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
is $tx->req->body, '', 'no content';
$tx = $t->redirect($tx);
is $tx->req->method, 'POST', 'right method';
is $tx->req->url->to_abs,     'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, 'application/json',       'right "Accept" value';
is $tx->req->headers->location, undef, 'no "Location" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# 307 redirect with content
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo' => {Accept => '*/*'} => 'whatever');
$tx->res->code(307);
$tx->res->headers->location('http://example.com/bar');
is $tx->req->headers->accept, '*/*', 'right "Accept" value';
is $tx->req->body, 'whatever', 'right content';
$tx = $t->redirect($tx);
is $tx->req->method, 'POST', 'right method';
is $tx->req->url->to_abs, 'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, '*/*', 'right "Accept" value';
is $tx->req->headers->location, undef, 'no "Location" value';
is $tx->req->body, 'whatever', 'right content';
is $tx->res->code, undef,      'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# 307 redirect (dynamic)
$tx = $t->tx(POST => 'http://mojolicio.us/foo');
$tx->res->code(307);
$tx->res->headers->location('http://example.com/bar');
$tx->req->content->write_chunk('whatever' => sub { shift->finish });
is $t->redirect($tx), undef, 'unsupported redirect';

# 307 redirect (additional headers)
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo' => {
    Accept        => 'application/json',
    Authorization => 'one',
    Cookie        => 'two',
    Host          => 'three',
    Referer       => 'four'
  }
);
$tx->res->code(307);
$tx->res->headers->location('http://example.com/bar');
is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
is $tx->req->headers->authorization, 'one',   'right "Authorization" value';
is $tx->req->headers->cookie,        'two',   'right "Cookie" value';
is $tx->req->headers->host,          'three', 'right "Host" value';
is $tx->req->headers->referrer,      'four',  'right "Referer" value';
is $tx->req->body, '', 'no content';
$tx = $t->redirect($tx);
is $tx->req->method, 'POST', 'right method';
is $tx->req->url->to_abs,     'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, 'application/json',       'right "Accept" value';
is $tx->req->headers->authorization, undef, 'no "Authorization" value';
is $tx->req->headers->cookie,        undef, 'no "Cookie" value';
is $tx->req->headers->host,          undef, 'no "Host" value';
is $tx->req->headers->location,      undef, 'no "Location" value';
is $tx->req->headers->referrer,      undef, 'no "Referer" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# Simple 308 redirect
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo' => {Accept => 'application/json'});
$tx->res->code(308);
$tx->res->headers->location('http://example.com/bar');
is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
is $tx->req->body, '', 'no content';
$tx = $t->redirect($tx);
is $tx->req->method, 'POST', 'right method';
is $tx->req->url->to_abs,     'http://example.com/bar', 'right URL';
is $tx->req->headers->accept, 'application/json',       'right "Accept" value';
is $tx->req->headers->location, undef, 'no "Location" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# 308 redirect with content
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo' => {Accept => '*/*'} => 'whatever');
$tx->res->code(308);
$tx->res->headers->location('https://example.com/bar');
is $tx->req->headers->accept, '*/*', 'right "Accept" value';
is $tx->req->body, 'whatever', 'right content';
$tx = $t->redirect($tx);
is $tx->req->method, 'POST', 'right method';
is $tx->req->url->to_abs, 'https://example.com/bar', 'right URL';
is $tx->req->headers->accept,   '*/*', 'right "Accept" value';
is $tx->req->headers->location, undef, 'no "Location" value';
is $tx->req->body, 'whatever', 'right content';
is $tx->res->code, undef,      'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# 308 redirect (dynamic)
$tx = $t->tx(POST => 'http://mojolicio.us/foo');
$tx->res->code(308);
$tx->res->headers->location('http://example.com/bar');
$tx->req->content->write_chunk('whatever' => sub { shift->finish });
is $t->redirect($tx), undef, 'unsupported redirect';

# 309 redirect (unsupported)
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo' => {Accept => 'application/json'});
$tx->res->code(309);
$tx->res->headers->location('http://example.com/bar');
is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
is $tx->req->body, '', 'no content';
is $t->redirect($tx), undef, 'unsupported redirect';

# 302 redirect with bad location
$tx = $t->tx(GET => 'http://mojolicio.us/foo');
$tx->res->code(302);
$tx->res->headers->location('data:image/png;base64,helloworld123');
is $t->redirect($tx), undef, 'unsupported redirect';

# 302 redirect (relative path and query)
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo/bar?a=b' => {Accept => 'application/json'});
$tx->res->code(302);
$tx->res->headers->location('baz?f%23oo=bar');
is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
is $tx->req->body, '', 'no content';
$tx = $t->redirect($tx);
is $tx->req->method, 'GET', 'right method';
is $tx->req->url->to_abs, 'http://mojolicio.us/foo/baz?f%23oo=bar',
  'right URL';
is $tx->req->url->query,        'f%23oo=bar',       'right query';
is $tx->req->headers->accept,   'application/json', 'right "Accept" value';
is $tx->req->headers->location, undef,              'no "Location" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# 302 redirect (absolute path and query)
$tx = $t->tx(
  POST => 'http://mojolicio.us/foo/bar?a=b' => {Accept => 'application/json'});
$tx->res->code(302);
$tx->res->headers->location('/baz?f%23oo=bar');
is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
is $tx->req->body, '', 'no content';
$tx = $t->redirect($tx);
is $tx->req->method, 'GET', 'right method';
is $tx->req->url->to_abs, 'http://mojolicio.us/baz?f%23oo=bar', 'right URL';
is $tx->req->url->query, 'f%23oo=bar', 'right query';
is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
is $tx->req->headers->location, undef, 'no "Location" value';
is $tx->req->body, '',    'no content';
is $tx->res->code, undef, 'no status';
is $tx->res->headers->location, undef, 'no "Location" value';

# Abstract methods
eval { Mojo::Transaction->client_read };
like $@, qr/Method "client_read" not implemented by subclass/, 'right error';
eval { Mojo::Transaction->client_write };
like $@, qr/Method "client_write" not implemented by subclass/, 'right error';
eval { Mojo::Transaction->server_read };
like $@, qr/Method "server_read" not implemented by subclass/, 'right error';
eval { Mojo::Transaction->server_write };
like $@, qr/Method "server_write" not implemented by subclass/, 'right error';

done_testing();
