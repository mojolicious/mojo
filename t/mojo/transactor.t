use Mojo::Base -strict;

use Test::More;
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::File qw(tempdir);
use Mojo::Promise;
use Mojo::Transaction::WebSocket;
use Mojo::URL;
use Mojo::UserAgent::Transactor;
use Mojo::Util      qw(b64_decode encode);
use Mojo::WebSocket qw(server_handshake);

# Custom content generator
my $t = Mojo::UserAgent::Transactor->new;
$t->add_generator(
  reverse => sub {
    my ($t, $tx, $content) = @_;
    $tx->req->body(scalar reverse $content);
  }
);

subtest 'Compression' => sub {
  local $ENV{MOJO_GZIP} = 1;
  my $t = Mojo::UserAgent::Transactor->new;
  ok $t->compressed, 'compressed';
  is $t->tx(GET => '/')->req->headers->accept_encoding, 'gzip', 'right value';
  is $t->tx(GET => '/')->res->content->auto_decompress, undef,  'no value';

  $ENV{MOJO_GZIP} = 0;
  $t = Mojo::UserAgent::Transactor->new;
  ok !$t->compressed, 'not compressed';
  is $t->tx(GET => '/')->req->headers->accept_encoding, undef, 'no value';
  is $t->tx(GET => '/')->res->content->auto_decompress, 0,     'right value';
};

subtest 'Simple GET' => sub {
  my $tx = $t->tx(GET => 'mojolicious.org/foo.html?bar=baz');
  is $tx->req->url->to_abs,              'http://mojolicious.org/foo.html?bar=baz', 'right URL';
  is $tx->req->method,                   'GET',                                     'right method';
  is $tx->req->headers->accept_encoding, 'gzip',                                    'right "Accept-Encoding" value';
  is $tx->req->headers->user_agent,      'Mojolicious (Perl)',                      'right "User-Agent" value';
};

subtest 'GET with escaped slash' => sub {
  my $url = Mojo::URL->new('http://mojolicious.org');
  $url->path->parts(['foo/bar']);
  my $tx = $t->tx(GET => $url);
  is $tx->req->url->to_string,       $url->to_string,       'URLs are equal';
  is $tx->req->url->path->to_string, $url->path->to_string, 'paths are equal';
  is $tx->req->url->path->to_string, 'foo%2Fbar',           'right path';
  is $tx->req->method,               'GET',                 'right method';
};

subtest 'POST with header' => sub {
  $t->name('MyUA 1.0');
  my $tx = $t->tx(POST => 'https://mojolicious.org' => {DNT => 1});
  is $tx->req->url->to_abs,              'https://mojolicious.org', 'right URL';
  is $tx->req->method,                   'POST',                    'right method';
  is $tx->req->headers->dnt,             1,                         'right "DNT" value';
  is $tx->req->headers->accept_encoding, 'gzip',                    'right "Accept-Encoding" value';
  is $tx->req->headers->user_agent,      'MyUA 1.0',                'right "User-Agent" value';
};

subtest 'POST with header and content' => sub {
  my $tx = $t->tx(POST => 'https://mojolicious.org' => {DNT => 1} => 'test');
  is $tx->req->url->to_abs,  'https://mojolicious.org', 'right URL';
  is $tx->req->method,       'POST',                    'right method';
  is $tx->req->headers->dnt, 1,                         'right "DNT" value';
  is $tx->req->body,         'test',                    'right content';
};

subtest 'DELETE with content' => sub {
  my $tx = $t->tx(DELETE => 'https://mojolicious.org' => 'test');
  is $tx->req->url->to_abs,  'https://mojolicious.org', 'right URL';
  is $tx->req->method,       'DELETE',                  'right method';
  is $tx->req->headers->dnt, undef,                     'no "DNT" value';
  is $tx->req->body,         'test',                    'right content';
};

subtest 'PUT with custom content generator' => sub {
  my $tx = $t->tx(PUT => 'mojolicious.org', reverse => 'hello!');
  is $tx->req->url->to_abs,  'http://mojolicious.org', 'right URL';
  is $tx->req->method,       'PUT',                    'right method';
  is $tx->req->headers->dnt, undef,                    'no "DNT" value';
  is $tx->req->body,         '!olleh',                 'right content';
  $tx = $t->tx(PUT => 'mojolicious.org', {DNT => 1}, reverse => 'hello!');
  is $tx->req->url->to_abs,  'http://mojolicious.org', 'right URL';
  is $tx->req->method,       'PUT',                    'right method';
  is $tx->req->headers->dnt, 1,                        'right "DNT" value';
  is $tx->req->body,         '!olleh',                 'right content';
};

subtest 'Simple JSON POST' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => json => {test => 123});
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, 'application/json',       'right "Content-Type" value';
  is_deeply $tx->req->json, {test => 123}, 'right content';
  $tx = $t->tx(POST => 'http://example.com/foo' => json => [1, 2, 3]);
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, 'application/json',       'right "Content-Type" value';
  is_deeply $tx->req->json, [1, 2, 3], 'right content';
};

subtest 'JSON POST with headers' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => {DNT => 1}, json => {test => 123});
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->dnt,          1,                        'right "DNT" value';
  is $tx->req->headers->content_type, 'application/json',       'right "Content-Type" value';
  is_deeply $tx->req->json, {test => 123}, 'right content';
};

subtest 'JSON POST with custom content type' => sub {
  my $tx = $t->tx(
    POST => 'http://example.com/foo' => {DNT => 1, 'content-type' => 'application/something'} => json => [1, 2],);
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->dnt,          1,                        'right "DNT" value';
  is $tx->req->headers->content_type, 'application/something',  'right "Content-Type" value';
  is_deeply $tx->req->json, [1, 2], 'right content';
};

subtest 'Simple form (POST)' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => form => {test => 123});
  is $tx->req->url->to_abs,           'http://example.com/foo',            'right URL';
  is $tx->req->method,                'POST',                              'right method';
  is $tx->req->headers->content_type, 'application/x-www-form-urlencoded', 'right "Content-Type" value';
  is $tx->req->body,                  'test=123',                          'right content';
};

subtest 'Simple form (GET)' => sub {
  my $tx = $t->tx(GET => 'http://example.com/foo' => form => {test => 123});
  is $tx->req->url->to_abs,           'http://example.com/foo?test=123', 'right URL';
  is $tx->req->method,                'GET',                             'right method';
  is $tx->req->headers->content_type, undef,                             'no "Content-Type" value';
  is $tx->req->body,                  '',                                'no content';
};

subtest 'Simple form with multiple values' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => form => {a => [1, 2, 3], b => 4});
  is $tx->req->url->to_abs,           'http://example.com/foo',            'right URL';
  is $tx->req->method,                'POST',                              'right method';
  is $tx->req->headers->content_type, 'application/x-www-form-urlencoded', 'right "Content-Type" value';
  ok !$tx->is_empty, 'transaction is not empty';
  is $tx->req->body, 'a=1&a=2&a=3&b=4', 'right content';
};

subtest 'Existing query string (lowercase HEAD)' => sub {
  my $tx = $t->tx(head => 'http://example.com?foo=bar' => form => {baz => [1, 2]});
  is $tx->req->url->to_abs,           'http://example.com?foo=bar&baz=1&baz=2', 'right URL';
  is $tx->req->method,                'head',                                   'right method';
  is $tx->req->headers->content_type, undef,                                    'no "Content-Type" value';
  ok $tx->is_empty, 'transaction is empty';
  is $tx->req->body, '', 'no content';
};

subtest 'UTF-8 query' => sub {
  my $tx = $t->tx(GET => 'http://example.com/foo' => form => {a => '☃', b => '♥'});
  is $tx->req->url->to_abs,           'http://example.com/foo?a=%E2%98%83&b=%E2%99%A5', 'right URL';
  is $tx->req->method,                'GET',                                            'right method';
  is $tx->req->headers->content_type, undef,                                            'no "Content-Type" value';
  is $tx->req->body,                  '',                                               'no content';
};

subtest 'UTF-8 form' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => form => {'♥' => '☃'});
  is $tx->req->url->to_abs,           'http://example.com/foo',            'right URL';
  is $tx->req->method,                'POST',                              'right method';
  is $tx->req->headers->content_type, 'application/x-www-form-urlencoded', 'right "Content-Type" value';
  is $tx->req->body,                  '%E2%99%A5=%E2%98%83',               'right content';
  is $tx->req->param('♥'),            '☃',                                 'right value';
};

subtest 'UTF-8 form with header and custom content type' => sub {
  my $tx
    = $t->tx(POST => 'http://example.com/foo' => {Accept => '*/*', 'Content-Type' => 'application/mojo-form'} => form =>
      {'♥' => '☃', nothing => undef});
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, 'application/mojo-form',  'right "Content-Type" value';
  is $tx->req->headers->accept,       '*/*',                    'right "Accept" value';
  is $tx->req->body,                  '%E2%99%A5=%E2%98%83',    'right content';
};

subtest 'Form (shift_jis)' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => form => {'やった' => 'やった'} => charset => 'shift_jis');
  is $tx->req->url->to_abs,           'http://example.com/foo',                'right URL';
  is $tx->req->method,                'POST',                                  'right method';
  is $tx->req->headers->content_type, 'application/x-www-form-urlencoded',     'right "Content-Type" value';
  is $tx->req->body,                  '%82%E2%82%C1%82%BD=%82%E2%82%C1%82%BD', 'right content';
  is $tx->req->default_charset('shift_jis')->param('やった'), 'やった',              'right value';
};

subtest 'UTF-8 multipart form' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => {'Content-Type' => 'multipart/form-data'} => form =>
      {'♥' => '☃', nothing => undef});
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, 'multipart/form-data',    'right "Content-Type" value';
  like $tx->req->content->parts->[0]->headers->content_disposition, qr/"@{[encode 'UTF-8', '♥']}"/,
    'right "Content-Disposition" value';
  is $tx->req->content->parts->[0]->asset->slurp, encode('UTF-8', '☃'), 'right part';
  ok !$tx->req->content->parts->[0]->asset->is_file,      'stored in memory';
  ok !$tx->req->content->parts->[0]->asset->auto_upgrade, 'no upgrade';
  is $tx->req->content->parts->[1], undef, 'no more parts';
  is $tx->req->param('♥'),          '☃',   'right value';
};

subtest 'Multipart form (shift_jis)' => sub {
  my $tx
    = $t->tx(
    POST => 'http://example.com/foo' => {'Content-Type' => 'multipart/form-data'} => form => {'やった' => 'やった'} =>
      charset => 'shift_jis');
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, 'multipart/form-data',    'right "Content-Type" value';
  like $tx->req->content->parts->[0]->headers->content_disposition, qr/"@{[encode 'shift_jis', 'やった']}"/,
    'right "Content-Disposition" value';
  is $tx->req->content->parts->[0]->asset->slurp, encode('shift_jis', 'やった'), 'right part';
  ok !$tx->req->content->parts->[0]->asset->is_file,      'stored in memory';
  ok !$tx->req->content->parts->[0]->asset->auto_upgrade, 'no upgrade';
  is $tx->req->content->parts->[1],                        undef, 'no more parts';
  is $tx->req->default_charset('shift_jis')->param('やった'), 'やった', 'right value';
};

subtest 'Multipart form with multiple values' => sub {
  my $tx = $t->tx(
    POST => 'http://example.com/foo' => {'Content-Type' => 'multipart/form-data'} => form => {a => [1, 2, 3], b => 4});
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, 'multipart/form-data',    'right "Content-Type" value';
  like $tx->req->content->parts->[0]->headers->content_disposition, qr/"a"/, 'right "Content-Disposition" value';
  is $tx->req->content->parts->[0]->asset->slurp, 1, 'right part';
  like $tx->req->content->parts->[1]->headers->content_disposition, qr/"a"/, 'right "Content-Disposition" value';
  is $tx->req->content->parts->[1]->asset->slurp, 2, 'right part';
  like $tx->req->content->parts->[2]->headers->content_disposition, qr/"a"/, 'right "Content-Disposition" value';
  is $tx->req->content->parts->[2]->asset->slurp, 3, 'right part';
  like $tx->req->content->parts->[3]->headers->content_disposition, qr/"b"/, 'right "Content-Disposition" value';
  is $tx->req->content->parts->[3]->asset->slurp, 4,     'right part';
  is $tx->req->content->parts->[4],               undef, 'no more parts';
  is_deeply $tx->req->every_param('a'), [1, 2, 3], 'right values';
  is $tx->req->param('b'), 4, 'right value';
};

subtest 'Multipart form with real file and custom header' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => form => {mytext => {file => __FILE__, DNT => 1}});
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, 'multipart/form-data',    'right "Content-Type" value';
  like $tx->req->content->parts->[0]->headers->content_disposition, qr/"mytext"/, 'right "Content-Disposition" value';
  like $tx->req->content->parts->[0]->headers->content_disposition, qr/"transactor.t"/,
    'right "Content-Disposition" value';
  like $tx->req->content->parts->[0]->asset->slurp, qr/mytext/, 'right part';
  ok $tx->req->content->parts->[0]->asset->is_file,           'stored in file';
  ok !$tx->req->content->parts->[0]->headers->header('file'), 'no "file" header';
  is $tx->req->content->parts->[0]->headers->dnt, 1,     'right "DNT" header';
  is $tx->req->content->parts->[1],               undef, 'no more parts';
};

subtest 'Multipart form with custom Content-Disposition header' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => form =>
      {mytext => {file => __FILE__, 'Content-Disposition' => 'form-data; name="works"'}});
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, 'multipart/form-data',    'right "Content-Type" value';
  unlike $tx->req->content->parts->[0]->headers->content_disposition, qr/"transactor.t"/,
    'different "Content-Disposition" value';
  is $tx->req->content->parts->[0]->headers->content_disposition, 'form-data; name="works"',
    'right "Content-Disposition" value';
  like $tx->req->content->parts->[0]->asset->slurp, qr/mytext/, 'right part';
  ok $tx->req->content->parts->[0]->asset->is_file,           'stored in file';
  ok !$tx->req->content->parts->[0]->headers->header('file'), 'no "file" header';
  is $tx->req->content->parts->[1], undef, 'no more parts';
};

subtest 'Multipart form with asset and custom content type' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => {'Content-Type' => 'multipart/mojo-form'} => form =>
      {mytext => {file => Mojo::Asset::File->new(path => __FILE__)}});
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, 'multipart/mojo-form',    'right "Content-Type" value';
  like $tx->req->content->parts->[0]->headers->content_disposition, qr/"mytext"/, 'right "Content-Disposition" value';
  like $tx->req->content->parts->[0]->headers->content_disposition, qr/"transactor.t"/,
    'right "Content-Disposition" value';
  like $tx->req->content->parts->[0]->asset->slurp, qr/mytext/, 'right part';
  ok $tx->req->content->parts->[0]->asset->is_file, 'stored in file';
  is $tx->req->content->parts->[1], undef, 'no more parts';
};

subtest 'Multipart form with in-memory content' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => form => {mytext => {content => 'lalala'}});
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, 'multipart/form-data',    'right "Content-Type" value';
  like $tx->req->content->parts->[0]->headers->content_disposition, qr/mytext/, 'right "Content-Disposition" value';
  ok !$tx->req->content->parts->[0]->headers->header('content'), 'no "content" header';
  is $tx->req->content->parts->[0]->asset->slurp, 'lalala', 'right part';
  ok !$tx->req->content->parts->[0]->asset->is_file,      'stored in memory';
  ok !$tx->req->content->parts->[0]->asset->auto_upgrade, 'no upgrade';
  is $tx->req->content->parts->[1], undef, 'no more parts';
};

subtest 'Multipart form with filename ("0")' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => form => {0 => {content => 'whatever', filename => '0'}});
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, 'multipart/form-data',    'right "Content-Type" value';
  like $tx->req->content->parts->[0]->headers->content_disposition, qr/0/, 'right "Content-Disposition" value';
  ok !$tx->req->content->parts->[0]->headers->header('filename'), 'no "filename" header';
  is $tx->req->content->parts->[0]->asset->slurp, 'whatever', 'right part';
  is $tx->req->content->parts->[1],               undef,      'no more parts';
  is $tx->req->upload('0')->filename,             '0',        'right filename';
  is $tx->req->upload('0')->size,                 8,          'right size';
  is $tx->req->upload('0')->slurp,                'whatever', 'right content';
};

subtest 'Multipart form with asset and filename (UTF-8)' => sub {
  my $snowman = encode 'UTF-8', '☃';
  my $tx      = $t->tx(POST => 'http://example.com/foo' => form =>
      {'"☃"' => {file => Mojo::Asset::Memory->new->add_chunk('snowman'), filename => '"☃".jpg'}});
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, 'multipart/form-data',    'right "Content-Type" value';
  like $tx->req->content->parts->[0]->headers->content_disposition, qr/$snowman/, 'right "Content-Disposition" value';
  is $tx->req->content->parts->[0]->asset->slurp, 'snowman',     'right part';
  is $tx->req->content->parts->[1],               undef,         'no more parts';
  is $tx->req->upload('%22☃%22')->filename,       '%22☃%22.jpg', 'right filename';
  is $tx->req->upload('%22☃%22')->size,           7,             'right size';
  is $tx->req->upload('%22☃%22')->slurp,          'snowman',     'right content';
};

subtest 'Multipart form with multiple uploads sharing the same name' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => form =>
      {mytext => [{content => 'just', filename => 'one.txt'}, {content => 'works', filename => 'two.txt'}]});
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, 'multipart/form-data',    'right "Content-Type" value';
  like $tx->req->content->parts->[0]->headers->content_disposition, qr/mytext/,   'right "Content-Disposition" value';
  like $tx->req->content->parts->[0]->headers->content_disposition, qr/one\.txt/, 'right "Content-Disposition" value';
  is $tx->req->content->parts->[0]->asset->slurp, 'just', 'right part';
  like $tx->req->content->parts->[1]->headers->content_disposition, qr/mytext/,   'right "Content-Disposition" value';
  like $tx->req->content->parts->[1]->headers->content_disposition, qr/two\.txt/, 'right "Content-Disposition" value';
  is $tx->req->content->parts->[1]->asset->slurp, 'works', 'right part';
  is $tx->req->content->parts->[2],               undef,   'no more parts';
};

subtest 'Multipart request (long)' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => multipart => [{content => 'just'}, {content => 'works'}]);
  is $tx->req->url->to_abs,                                       'http://example.com/foo', 'right URL';
  is $tx->req->method,                                            'POST',                   'right method';
  is $tx->req->headers->content_type,                             undef,                    'no "Content-Type" value';
  is $tx->req->content->parts->[0]->headers->content_disposition, undef,   'no "Content-Disposition" value';
  is $tx->req->content->parts->[0]->asset->slurp,                 'just',  'right part';
  is $tx->req->content->parts->[1]->headers->content_disposition, undef,   'no "Content-Disposition" value';
  is $tx->req->content->parts->[1]->asset->slurp,                 'works', 'right part';
  is $tx->req->content->parts->[2],                               undef,   'no more parts';
};

subtest 'Multipart request (short)' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => multipart => ['just', 'works']);
  is $tx->req->url->to_abs,                                       'http://example.com/foo', 'right URL';
  is $tx->req->method,                                            'POST',                   'right method';
  is $tx->req->headers->content_type,                             undef,                    'no "Content-Type" value';
  is $tx->req->content->parts->[0]->headers->content_disposition, undef,   'no "Content-Disposition" value';
  is $tx->req->content->parts->[0]->asset->slurp,                 'just',  'right part';
  is $tx->req->content->parts->[1]->headers->content_disposition, undef,   'no "Content-Disposition" value';
  is $tx->req->content->parts->[1]->asset->slurp,                 'works', 'right part';
  is $tx->req->content->parts->[2],                               undef,   'no more parts';
};

subtest 'Multipart request with asset' => sub {
  my $tx = $t->tx(
    POST => 'http://example.com/foo' => multipart => [{file => Mojo::Asset::Memory->new->add_chunk('snowman')}]);
  is $tx->req->url->to_abs,                                       'http://example.com/foo', 'right URL';
  is $tx->req->method,                                            'POST',                   'right method';
  is $tx->req->headers->content_type,                             undef,                    'no "Content-Type" value';
  is $tx->req->content->parts->[0]->headers->content_disposition, undef,     'no "Content-Disposition" value';
  is $tx->req->content->parts->[0]->asset->slurp,                 'snowman', 'right part';
  is $tx->req->content->parts->[1],                               undef,     'no more parts';
};

subtest 'Multipart request with real file and custom header' => sub {
  my $tx = $t->tx(POST => 'http://example.com/foo' => multipart => [{file => __FILE__, DNT => 1}]);
  is $tx->req->url->to_abs,           'http://example.com/foo', 'right URL';
  is $tx->req->method,                'POST',                   'right method';
  is $tx->req->headers->content_type, undef,                    'no "Content-Type" value';
  like $tx->req->content->parts->[0]->asset->slurp, qr/mytext/, 'right part';
  ok $tx->req->content->parts->[0]->asset->is_file, 'stored in file';
  is $tx->req->content->parts->[0]->headers->header('file'),      undef, 'no "file" header';
  is $tx->req->content->parts->[0]->headers->content_disposition, undef, 'no "Content-Disposition" value';
  is $tx->req->content->parts->[0]->headers->dnt,                 1,     'right "DNT" header';
  is $tx->req->content->parts->[1],                               undef, 'no more parts';
};

subtest 'Simple endpoint' => sub {
  my $tx = $t->tx(GET => 'mojolicious.org');
  is(($t->endpoint($tx))[0], 'http',            'right scheme');
  is(($t->endpoint($tx))[1], 'mojolicious.org', 'right host');
  is(($t->endpoint($tx))[2], 80,                'right port');
};

subtest 'Simple endpoint with proxy' => sub {
  my $tx = $t->tx(GET => 'http://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('http://127.0.0.1:3000'));
  is(($t->endpoint($tx))[0], 'http',      'right scheme');
  is(($t->endpoint($tx))[1], '127.0.0.1', 'right host');
  is(($t->endpoint($tx))[2], 3000,        'right port');
};

subtest 'Simple endpoint with deactivated proxy' => sub {
  my $tx = $t->tx(GET => 'http://mojolicious.org');
  $tx->req->via_proxy(0)->proxy(Mojo::URL->new('http://127.0.0.1:3000'));
  is(($t->endpoint($tx))[0], 'http',            'right scheme');
  is(($t->endpoint($tx))[1], 'mojolicious.org', 'right host');
  is(($t->endpoint($tx))[2], 80,                'right port');
};

subtest 'Simple endpoint with SOCKS proxy' => sub {
  my $tx = $t->tx(GET => 'http://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('socks://127.0.0.1:3000'));
  is(($t->endpoint($tx))[0], 'http',            'right scheme');
  is(($t->endpoint($tx))[1], 'mojolicious.org', 'right host');
  is(($t->endpoint($tx))[2], 80,                'right port');
};

subtest 'Simple WebSocket endpoint with proxy' => sub {
  my $tx = $t->websocket('ws://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('http://127.0.0.1:3000'));
  is(($t->endpoint($tx))[0], 'http',            'right scheme');
  is(($t->endpoint($tx))[1], 'mojolicious.org', 'right host');
  is(($t->endpoint($tx))[2], 80,                'right port');
};

subtest 'HTTPS endpoint' => sub {
  my $tx = $t->tx(GET => 'HTTPS://mojolicious.org');
  is(($t->endpoint($tx))[0], 'https',           'right scheme');
  is(($t->endpoint($tx))[1], 'mojolicious.org', 'right host');
  is(($t->endpoint($tx))[2], 443,               'right port');
};

subtest 'HTTPS endpoint with proxy' => sub {
  my $tx = $t->tx(GET => 'https://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('http://127.0.0.1:3000'));
  is(($t->endpoint($tx))[0], 'https',           'right scheme');
  is(($t->endpoint($tx))[1], 'mojolicious.org', 'right host');
  is(($t->endpoint($tx))[2], 443,               'right port');
};

subtest 'HTTPS endpoint with SOCKS proxy' => sub {
  my $tx = $t->tx(GET => 'https://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('socks://127.0.0.1:3000'));
  is(($t->endpoint($tx))[0], 'https',           'right scheme');
  is(($t->endpoint($tx))[1], 'mojolicious.org', 'right host');
  is(($t->endpoint($tx))[2], 443,               'right port');
};

subtest 'TLS WebSocket endpoint with proxy' => sub {
  my $tx = $t->websocket('WSS://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('http://127.0.0.1:3000'));
  is(($t->endpoint($tx))[0], 'https',           'right scheme');
  is(($t->endpoint($tx))[1], 'mojolicious.org', 'right host');
  is(($t->endpoint($tx))[2], 443,               'right port');
};

subtest 'Simple peer' => sub {
  my $tx = $t->tx(GET => 'mojolicious.org');
  is(($t->peer($tx))[0], 'http',            'right scheme');
  is(($t->peer($tx))[1], 'mojolicious.org', 'right host');
  is(($t->peer($tx))[2], 80,                'right port');
};

subtest 'Simple peer with proxy' => sub {
  my $tx = $t->tx(GET => 'http://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('http://127.0.0.1:3000'));
  is(($t->peer($tx))[0], 'http',      'right scheme');
  is(($t->peer($tx))[1], '127.0.0.1', 'right host');
  is(($t->peer($tx))[2], 3000,        'right port');
};

subtest 'Simple peer with deactivated proxy' => sub {
  my $tx = $t->tx(GET => 'http://mojolicious.org');
  $tx->req->via_proxy(0)->proxy(Mojo::URL->new('http://127.0.0.1:3000'));
  is(($t->peer($tx))[0], 'http',            'right scheme');
  is(($t->peer($tx))[1], 'mojolicious.org', 'right host');
  is(($t->peer($tx))[2], 80,                'right port');
};

subtest 'Simple peer with SOCKS proxy' => sub {
  my $tx = $t->tx(GET => 'http://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('socks://127.0.0.1:3000'));
  is(($t->peer($tx))[0], 'socks',     'right scheme');
  is(($t->peer($tx))[1], '127.0.0.1', 'right host');
  is(($t->peer($tx))[2], 3000,        'right port');
};

subtest 'Simple peer with proxy (no port)' => sub {
  my $tx = $t->tx(GET => 'http://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('http://127.0.0.1'));
  is(($t->peer($tx))[0], 'http',      'right scheme');
  is(($t->peer($tx))[1], '127.0.0.1', 'right host');
  is(($t->peer($tx))[2], 80,          'right port');
};

subtest 'Simple peer with HTTPS proxy (no port)' => sub {
  my $tx = $t->tx(GET => 'http://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('HTTPS://127.0.0.1'));
  is(($t->peer($tx))[0], 'https',     'right scheme');
  is(($t->peer($tx))[1], '127.0.0.1', 'right host');
  is(($t->peer($tx))[2], 443,         'right port');
};

subtest 'Simple WebSocket peer with proxy' => sub {
  my $tx = $t->websocket('ws://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('http://127.0.0.1:3000'));
  is(($t->peer($tx))[0], 'http',      'right scheme');
  is(($t->peer($tx))[1], '127.0.0.1', 'right host');
  is(($t->peer($tx))[2], 3000,        'right port');
};

subtest 'HTTPS peer' => sub {
  my $tx = $t->tx(GET => 'https://mojolicious.org');
  is(($t->peer($tx))[0], 'https',           'right scheme');
  is(($t->peer($tx))[1], 'mojolicious.org', 'right host');
  is(($t->peer($tx))[2], 443,               'right port');
};

subtest 'HTTPS peer with proxy' => sub {
  my $tx = $t->tx(GET => 'https://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('http://127.0.0.1:3000'));
  is(($t->peer($tx))[0], 'http',      'right scheme');
  is(($t->peer($tx))[1], '127.0.0.1', 'right host');
  is(($t->peer($tx))[2], 3000,        'right port');
};

subtest 'HTTPS peer with SOCKS proxy' => sub {
  my $tx = $t->tx(GET => 'https://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('socks://127.0.0.1:3000'));
  is(($t->peer($tx))[0], 'socks',     'right scheme');
  is(($t->peer($tx))[1], '127.0.0.1', 'right host');
  is(($t->peer($tx))[2], 3000,        'right port');
};

subtest 'TLS WebSocket peer with proxy' => sub {
  my $tx = $t->websocket('wss://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('http://127.0.0.1:3000'));
  is(($t->peer($tx))[0], 'http',      'right scheme');
  is(($t->peer($tx))[1], '127.0.0.1', 'right host');
  is(($t->peer($tx))[2], 3000,        'right port');
};

subtest 'WebSocket handshake' => sub {
  my $tx = $t->websocket('ws://127.0.0.1:3000/echo');
  ok !$tx->is_websocket, 'not a WebSocket';
  is $tx->req->url->to_abs,                                   'http://127.0.0.1:3000/echo', 'right URL';
  is $tx->req->method,                                        'GET',                        'right method';
  is $tx->req->headers->connection,                           'Upgrade',                    'right "Connection" value';
  is length(b64_decode $tx->req->headers->sec_websocket_key), 16, '16 byte "Sec-WebSocket-Key" value';
  ok !$tx->req->headers->sec_websocket_protocol, 'no "Sec-WebSocket-Protocol" header';
  ok $tx->req->headers->sec_websocket_version,   'has "Sec-WebSocket-Version" value';
  is $tx->req->headers->upgrade, 'websocket', 'right "Upgrade" value';
  is $t->upgrade($tx),           undef,       'not upgraded';
  server_handshake $tx;
  $tx->res->code(101);
  $tx = $t->upgrade($tx);
  ok $tx->is_websocket, 'is a WebSocket';
};

subtest 'WebSocket handshake with header' => sub {
  my $tx = $t->websocket('wss://127.0.0.1:3000/echo' => {DNT => 1});
  is $tx->req->url->to_abs,                                   'https://127.0.0.1:3000/echo', 'right URL';
  is $tx->req->method,                                        'GET',                         'right method';
  is $tx->req->headers->dnt,                                  1,                             'right "DNT" value';
  is $tx->req->headers->connection,                           'Upgrade',                     'right "Connection" value';
  is length(b64_decode $tx->req->headers->sec_websocket_key), 16, '16 byte "Sec-WebSocket-Key" value';
  ok !$tx->req->headers->sec_websocket_protocol, 'no "Sec-WebSocket-Protocol" header';
  ok $tx->req->headers->sec_websocket_version,   'has "Sec-WebSocket-Version" value';
  is $tx->req->headers->upgrade, 'websocket', 'right "Upgrade" value';
};

subtest 'WebSocket handshake with protocol' => sub {
  my $tx = $t->websocket('wss://127.0.0.1:3000/echo' => ['foo']);
  is $tx->req->url->to_abs,                                   'https://127.0.0.1:3000/echo', 'right URL';
  is $tx->req->method,                                        'GET',                         'right method';
  is $tx->req->headers->connection,                           'Upgrade',                     'right "Connection" value';
  is length(b64_decode $tx->req->headers->sec_websocket_key), 16,    '16 byte "Sec-WebSocket-Key" value';
  is $tx->req->headers->sec_websocket_protocol,               'foo', 'right "Sec-WebSocket-Protocol" value';
  ok $tx->req->headers->sec_websocket_version, 'has "Sec-WebSocket-Version" value';
  is $tx->req->headers->upgrade, 'websocket', 'right "Upgrade" value';
};

subtest 'WebSocket handshake with header and protocols' => sub {
  my $tx
    = $t->websocket('wss://127.0.0.1:3000/echo' => {DNT => 1} => ['v1.bar.example.com', 'foo', 'v2.baz.example.com']);
  is $tx->req->url->to_abs,                                   'https://127.0.0.1:3000/echo', 'right URL';
  is $tx->req->method,                                        'GET',                         'right method';
  is $tx->req->headers->dnt,                                  1,                             'right "DNT" value';
  is $tx->req->headers->connection,                           'Upgrade',                     'right "Connection" value';
  is length(b64_decode $tx->req->headers->sec_websocket_key), 16, '16 byte "Sec-WebSocket-Key" value';
  is $tx->req->headers->sec_websocket_protocol, 'v1.bar.example.com, foo, v2.baz.example.com',
    'right "Sec-WebSocket-Protocol" value';
  ok $tx->req->headers->sec_websocket_version, 'has "Sec-WebSocket-Version" value';
  is $tx->req->headers->upgrade, 'websocket', 'right "Upgrade" value';
};

subtest 'WebSocket handshake with UNIX domain socket' => sub {
  my $tx = $t->websocket('ws+unix://%2Ftmp%2Fmyapp.sock/echo' => {DNT => 1});
  is $tx->req->url->to_abs,         'http+unix://%2Ftmp%2Fmyapp.sock/echo', 'right URL';
  is $tx->req->method,              'GET',                                  'right method';
  is $tx->req->headers->dnt,        1,                                      'right "DNT" value';
  is $tx->req->headers->connection, 'Upgrade',                              'right "Connection" value';
  is length(b64_decode $tx->req->headers->sec_websocket_key), 16,           '16 byte "Sec-WebSocket-Key" value';
  ok !$tx->req->headers->sec_websocket_protocol, 'no "Sec-WebSocket-Protocol" header';
  ok $tx->req->headers->sec_websocket_version,   'has "Sec-WebSocket-Version" value';
  is $tx->req->headers->upgrade, 'websocket', 'right "Upgrade" value';
};

subtest 'Proxy CONNECT' => sub {
  my $tx = $t->tx(GET => 'HTTPS://sri:secr3t@mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('http://sri:secr3t@127.0.0.1:3000'));
  ok !$tx->req->headers->authorization,       'no "Authorization" header';
  ok !$tx->req->headers->proxy_authorization, 'no "Proxy-Authorization" header';
  $tx->req->fix_headers;
  is $tx->req->headers->authorization,       'Basic c3JpOnNlY3IzdA==', 'right "Authorization" header';
  is $tx->req->headers->proxy_authorization, 'Basic c3JpOnNlY3IzdA==', 'right "Proxy-Authorization" header';
  $tx = $t->proxy_connect($tx);
  is $tx->req->method,        'CONNECT',                 'right method';
  is $tx->req->url->to_abs,   'https://mojolicious.org', 'right URL';
  is $tx->req->proxy->to_abs, 'http://127.0.0.1:3000',   'right proxy URL';
  ok !$tx->req->headers->authorization,       'no "Authorization" header';
  ok !$tx->req->headers->proxy_authorization, 'no "Proxy-Authorization" header';
  ok !$tx->req->headers->host,                'no "Host" header';
  $tx->req->fix_headers;
  ok !$tx->req->headers->authorization, 'no "Authorization" header';
  is $tx->req->headers->proxy_authorization, 'Basic c3JpOnNlY3IzdA==', 'right "Proxy-Authorization" header';
  is $tx->req->headers->host,                'mojolicious.org',        'right "Host" header';
  is $t->proxy_connect($tx),                 undef,                    'already a CONNECT request';
  $tx->req->method('Connect');
  is $t->proxy_connect($tx), undef, 'already a CONNECT request';
  $tx = $t->tx(GET => 'https://mojolicious.org');
  $tx->req->proxy(Mojo::URL->new('socks://127.0.0.1:3000'));
  is $t->proxy_connect($tx), undef, 'using a SOCKS proxy';
  $tx = $t->tx(GET => 'https://mojolicious.org');
  ok $tx->req->via_proxy, 'proxy use is enabled by default';
  $tx->req->via_proxy(0)->proxy(Mojo::URL->new('http://127.0.0.1:3000'));
  is $t->proxy_connect($tx), undef, 'proxy use is disabled';
};

subtest 'Simple 301 redirect' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo' => {Accept => 'application/json'});
  $tx->res->code(301);
  $tx->res->headers->location('http://example.com/bar');
  is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
  is $tx->req->body,            '',                 'no content';
  $tx = $t->redirect($tx);
  is $tx->req->method,              'GET',                    'right method';
  is $tx->req->url->to_abs,         'http://example.com/bar', 'right URL';
  is $tx->req->headers->user_agent, 'MyUA 1.0',               'right "User-Agent" value';
  is $tx->req->headers->accept,     'application/json',       'right "Accept" value';
  is $tx->req->headers->location,   undef,                    'no "Location" value';
  is $tx->req->body,                '',                       'no content';
  is $tx->res->code,                undef,                    'no status';
  is $tx->res->headers->location,   undef,                    'no "Location" value';
};

subtest '301 redirect with content' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo' => {Accept => '*/*'} => 'whatever');
  $tx->res->code(301);
  $tx->res->headers->location('http://example.com/bar');
  is $tx->req->headers->accept, '*/*',      'right "Accept" value';
  is $tx->req->body,            'whatever', 'right content';
  $tx = $t->redirect($tx);
  is $tx->req->method,            'GET',                    'right method';
  is $tx->req->url->to_abs,       'http://example.com/bar', 'right URL';
  is $tx->req->headers->accept,   '*/*',                    'right "Accept" value';
  is $tx->req->headers->location, undef,                    'no "Location" value';
  is $tx->req->body,              '',                       'no content';
  is $tx->res->code,              undef,                    'no status';
  is $tx->res->headers->location, undef,                    'no "Location" value';
};

subtest '301 redirect with content (DELETE)' => sub {
  my $tx = $t->tx(DELETE => 'http://mojolicious.org/foo' => {Accept => '*/*'} => 'whatever');
  $tx->res->code(301);
  $tx->res->headers->location('http://example.com/bar');
  is $tx->req->headers->accept, '*/*',      'right "Accept" value';
  is $tx->req->body,            'whatever', 'right content';
  $tx = $t->redirect($tx);
  is $tx->req->method,            'DELETE',                 'right method';
  is $tx->req->url->to_abs,       'http://example.com/bar', 'right URL';
  is $tx->req->headers->accept,   '*/*',                    'right "Accept" value';
  is $tx->req->headers->location, undef,                    'no "Location" value';
  is $tx->req->body,              '',                       'no content';
  is $tx->res->code,              undef,                    'no status';
  is $tx->res->headers->location, undef,                    'no "Location" value';
};

subtest 'Simple 302 redirect' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo' => {Accept => 'application/json'});
  $tx->res->code(302);
  $tx->res->headers->location('http://example.com/bar');
  is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
  is $tx->req->body,            '',                 'no content';
  $tx = $t->redirect($tx);
  is $tx->req->method,            'GET',                    'right method';
  is $tx->req->url->to_abs,       'http://example.com/bar', 'right URL';
  is $tx->req->headers->accept,   'application/json',       'right "Accept" value';
  is $tx->req->headers->location, undef,                    'no "Location" value';
  is $tx->req->body,              '',                       'no content';
  is $tx->res->code,              undef,                    'no status';
  is $tx->res->headers->location, undef,                    'no "Location" value';
};

subtest '302 redirect (lowercase HEAD)' => sub {
  my $tx = $t->tx(head => 'http://mojolicious.org/foo');
  $tx->res->code(302);
  $tx->res->headers->location('http://example.com/bar');
  $tx = $t->redirect($tx);
  is $tx->req->method,            'HEAD',                   'right method';
  is $tx->req->url->to_abs,       'http://example.com/bar', 'right URL';
  is $tx->req->headers->accept,   undef,                    'no "Accept" value';
  is $tx->req->headers->location, undef,                    'no "Location" value';
  is $tx->req->body,              '',                       'no content';
  is $tx->res->code,              undef,                    'no status';
  is $tx->res->headers->location, undef,                    'no "Location" value';
};

subtest '302 redirect (dynamic)' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo');
  $tx->res->code(302);
  $tx->res->headers->location('http://example.com/bar');
  $tx->req->content->write_chunk('whatever' => sub { shift->finish });
  $tx = $t->redirect($tx);
  is $tx->req->method,            'GET',                    'right method';
  is $tx->req->url->to_abs,       'http://example.com/bar', 'right URL';
  is $tx->req->headers->accept,   undef,                    'no "Accept" value';
  is $tx->req->headers->location, undef,                    'no "Location" value';
  is $tx->req->body,              '',                       'no content';
  is $tx->res->code,              undef,                    'no status';
  is $tx->res->headers->location, undef,                    'no "Location" value';
};

subtest '302 redirect with content' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo' => {Accept => '*/*'} => 'whatever');
  $tx->req->fix_headers->headers->content_type('text/plain');
  $tx->res->code(302);
  $tx->res->headers->location('http://example.com/bar');
  is $tx->req->headers->accept,         '*/*',        'right "Accept" value';
  is $tx->req->headers->content_type,   'text/plain', 'right "Content-Type" value';
  is $tx->req->headers->content_length, 8,            'right "Content-Length" value';
  is $tx->req->body,                    'whatever',   'right content';
  $tx = $t->redirect($tx);
  is $tx->req->method,                  'GET',                    'right method';
  is $tx->req->url->to_abs,             'http://example.com/bar', 'right URL';
  is $tx->req->headers->accept,         '*/*',                    'right "Accept" value';
  is $tx->req->headers->content_type,   undef,                    'no "Content-Type" value';
  is $tx->req->headers->content_length, undef,                    'no "Content-Length" value';
  is $tx->req->headers->location,       undef,                    'no "Location" value';
  is $tx->req->body,                    '',                       'no content';
  is $tx->res->code,                    undef,                    'no status';
  is $tx->res->headers->location,       undef,                    'no "Location" value';
};

subtest 'Simple 303 redirect' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo' => {Accept => 'application/json'});
  $tx->res->code(303);
  $tx->res->headers->location('http://example.com/bar');
  is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
  is $tx->req->body,            '',                 'no content';
  $tx = $t->redirect($tx);
  is $tx->req->method,            'GET',                    'right method';
  is $tx->req->url->to_abs,       'http://example.com/bar', 'right URL';
  is $tx->req->headers->accept,   'application/json',       'right "Accept" value';
  is $tx->req->headers->location, undef,                    'no "Location" value';
  is $tx->req->body,              '',                       'no content';
  is $tx->res->code,              undef,                    'no status';
  is $tx->res->headers->location, undef,                    'no "Location" value';
};

subtest '303 redirect (dynamic)' => sub {
  my $tx = $t->tx(PUT => 'http://mojolicious.org/foo');
  $tx->res->code(303);
  $tx->res->headers->location('http://example.com/bar');
  $tx->req->content->write_chunk('whatever' => sub { shift->finish });
  $tx = $t->redirect($tx);
  is $tx->req->method,            'GET',                    'right method';
  is $tx->req->url->to_abs,       'http://example.com/bar', 'right URL';
  is $tx->req->headers->accept,   undef,                    'no "Accept" value';
  is $tx->req->headers->location, undef,                    'no "Location" value';
  is $tx->req->body,              '',                       'no content';
  is $tx->res->code,              undef,                    'no status';
  is $tx->res->headers->location, undef,                    'no "Location" value';
};

subtest '303 redirect (additional headers)' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo' =>
      {Accept => 'application/json', Authorization => 'one', Cookie => 'two', Host => 'three', Referer => 'four'});
  $tx->res->code(303);
  $tx->res->headers->location('http://example.com/bar');
  is $tx->req->headers->accept,        'application/json', 'right "Accept" value';
  is $tx->req->headers->authorization, 'one',              'right "Authorization" value';
  is $tx->req->headers->cookie,        'two',              'right "Cookie" value';
  is $tx->req->headers->host,          'three',            'right "Host" value';
  is $tx->req->headers->referrer,      'four',             'right "Referer" value';
  is $tx->req->body,                   '',                 'no content';
  $tx = $t->redirect($tx);
  is $tx->req->method,                 'GET',                    'right method';
  is $tx->req->url->to_abs,            'http://example.com/bar', 'right URL';
  is $tx->req->headers->accept,        'application/json',       'right "Accept" value';
  is $tx->req->headers->authorization, undef,                    'no "Authorization" value';
  is $tx->req->headers->cookie,        undef,                    'no "Cookie" value';
  is $tx->req->headers->host,          undef,                    'no "Host" value';
  is $tx->req->headers->location,      undef,                    'no "Location" value';
  is $tx->req->headers->referrer,      undef,                    'no "Referer" value';
  is $tx->req->body,                   '',                       'no content';
  is $tx->res->code,                   undef,                    'no status';
  is $tx->res->headers->location,      undef,                    'no "Location" value';
};

subtest 'Simple 307 redirect' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo' => {Accept => 'application/json'});
  $tx->res->code(307);
  $tx->res->headers->location('http://example.com/bar');
  is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
  is $tx->req->body,            '',                 'no content';
  $tx = $t->redirect($tx);
  is $tx->req->method,            'POST',                   'right method';
  is $tx->req->url->to_abs,       'http://example.com/bar', 'right URL';
  is $tx->req->headers->accept,   'application/json',       'right "Accept" value';
  is $tx->req->headers->location, undef,                    'no "Location" value';
  is $tx->req->body,              '',                       'no content';
  is $tx->res->code,              undef,                    'no status';
  is $tx->res->headers->location, undef,                    'no "Location" value';
};

subtest '307 redirect with content' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo' => {Accept => '*/*'} => 'whatever');
  $tx->res->code(307);
  $tx->res->headers->location('http://example.com/bar');
  is $tx->req->headers->accept, '*/*',      'right "Accept" value';
  is $tx->req->body,            'whatever', 'right content';
  $tx = $t->redirect($tx);
  is $tx->req->method,            'POST',                   'right method';
  is $tx->req->url->to_abs,       'http://example.com/bar', 'right URL';
  is $tx->req->headers->accept,   '*/*',                    'right "Accept" value';
  is $tx->req->headers->location, undef,                    'no "Location" value';
  is $tx->req->body,              'whatever',               'right content';
  is $tx->res->code,              undef,                    'no status';
  is $tx->res->headers->location, undef,                    'no "Location" value';
};

subtest '307 redirect (dynamic)' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo');
  $tx->res->code(307);
  $tx->res->headers->location('http://example.com/bar');
  $tx->req->content->write_chunk('whatever' => sub { shift->finish });
  is $t->redirect($tx), undef, 'unsupported redirect';
};

subtest '307 redirect (additional headers)' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo' =>
      {Accept => 'application/json', Authorization => 'one', Cookie => 'two', Host => 'three', Referer => 'four'});
  $tx->res->code(307);
  $tx->res->headers->location('http://example.com/bar');
  is $tx->req->headers->accept,        'application/json', 'right "Accept" value';
  is $tx->req->headers->authorization, 'one',              'right "Authorization" value';
  is $tx->req->headers->cookie,        'two',              'right "Cookie" value';
  is $tx->req->headers->host,          'three',            'right "Host" value';
  is $tx->req->headers->referrer,      'four',             'right "Referer" value';
  is $tx->req->body,                   '',                 'no content';
  $tx = $t->redirect($tx);
  is $tx->req->method,                 'POST',                   'right method';
  is $tx->req->url->to_abs,            'http://example.com/bar', 'right URL';
  is $tx->req->headers->accept,        'application/json',       'right "Accept" value';
  is $tx->req->headers->authorization, undef,                    'no "Authorization" value';
  is $tx->req->headers->cookie,        undef,                    'no "Cookie" value';
  is $tx->req->headers->host,          undef,                    'no "Host" value';
  is $tx->req->headers->location,      undef,                    'no "Location" value';
  is $tx->req->headers->referrer,      undef,                    'no "Referer" value';
  is $tx->req->body,                   '',                       'no content';
  is $tx->res->code,                   undef,                    'no status';
  is $tx->res->headers->location,      undef,                    'no "Location" value';
};

subtest 'Simple 308 redirect' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo' => {Accept => 'application/json'});
  $tx->res->code(308);
  $tx->res->headers->location('http://example.com/bar');
  is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
  is $tx->req->body,            '',                 'no content';
  $tx = $t->redirect($tx);
  is $tx->req->method,            'POST',                   'right method';
  is $tx->req->url->to_abs,       'http://example.com/bar', 'right URL';
  is $tx->req->headers->accept,   'application/json',       'right "Accept" value';
  is $tx->req->headers->location, undef,                    'no "Location" value';
  is $tx->req->body,              '',                       'no content';
  is $tx->res->code,              undef,                    'no status';
  is $tx->res->headers->location, undef,                    'no "Location" value';
};

subtest '308 redirect with content' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo' => {Accept => '*/*'} => 'whatever');
  $tx->res->code(308);
  $tx->res->headers->location('https://example.com/bar');
  is $tx->req->headers->accept, '*/*',      'right "Accept" value';
  is $tx->req->body,            'whatever', 'right content';
  $tx = $t->redirect($tx);
  is $tx->req->method,            'POST',                    'right method';
  is $tx->req->url->to_abs,       'https://example.com/bar', 'right URL';
  is $tx->req->headers->accept,   '*/*',                     'right "Accept" value';
  is $tx->req->headers->location, undef,                     'no "Location" value';
  is $tx->req->body,              'whatever',                'right content';
  is $tx->res->code,              undef,                     'no status';
  is $tx->res->headers->location, undef,                     'no "Location" value';
};

subtest '308 redirect (dynamic)' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo');
  $tx->res->code(308);
  $tx->res->headers->location('http://example.com/bar');
  $tx->req->content->write_chunk('whatever' => sub { shift->finish });
  is $t->redirect($tx), undef, 'unsupported redirect';
};

subtest '309 redirect (unsupported)' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo' => {Accept => 'application/json'});
  $tx->res->code(309);
  $tx->res->headers->location('http://example.com/bar');
  is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
  is $tx->req->body,            '',                 'no content';
  is $t->redirect($tx),         undef,              'unsupported redirect';
};

subtest '302 redirect with bad location' => sub {
  my $tx = $t->tx(GET => 'http://mojolicious.org/foo');
  $tx->res->code(302);
  $tx->res->headers->location('data:image/png;base64,helloworld123');
  is $t->redirect($tx), undef, 'unsupported redirect';
  $tx = $t->tx(GET => 'http://mojolicious.org/foo');
  $tx->res->code(302);
  $tx->res->headers->location('http:');
  is $t->redirect($tx), undef, 'unsupported redirect';
};

subtest '302 redirect with multiple locations' => sub {
  my $tx = $t->tx(GET => 'http://mojolicious.org/foo');
  $tx->res->code(302);
  $tx->res->headers->add(Location => 'http://example.com/1.html');
  $tx->res->headers->add(Location => 'http://example.com/2.html');
  $tx = $t->redirect($tx);
  is $tx->req->method,            'GET',                       'right method';
  is $tx->req->url->to_abs,       'http://example.com/1.html', 'right URL';
  is $tx->req->headers->location, undef,                       'no "Location" value';
  is $tx->req->body,              '',                          'no content';
  is $tx->res->code,              undef,                       'no status';
  is $tx->res->headers->location, undef,                       'no "Location" value';
};

subtest '302 redirect (relative path and query)' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo/bar?a=b' => {Accept => 'application/json'});
  $tx->res->code(302);
  $tx->res->headers->location('baz?f%23oo=bar');
  is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
  is $tx->req->body,            '',                 'no content';
  $tx = $t->redirect($tx);
  is $tx->req->method,            'GET',                                       'right method';
  is $tx->req->url->to_abs,       'http://mojolicious.org/foo/baz?f%23oo=bar', 'right URL';
  is $tx->req->url->query,        'f%23oo=bar',                                'right query';
  is $tx->req->headers->accept,   'application/json',                          'right "Accept" value';
  is $tx->req->headers->location, undef,                                       'no "Location" value';
  is $tx->req->body,              '',                                          'no content';
  is $tx->res->code,              undef,                                       'no status';
  is $tx->res->headers->location, undef,                                       'no "Location" value';
};

subtest '302 redirect (absolute path and query)' => sub {
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo/bar?a=b' => {Accept => 'application/json'});
  $tx->res->code(302);
  $tx->res->headers->location('/baz?f%23oo=bar');
  is $tx->req->headers->accept, 'application/json', 'right "Accept" value';
  is $tx->req->body,            '',                 'no content';
  $tx = $t->redirect($tx);
  is $tx->req->method,            'GET',                                   'right method';
  is $tx->req->url->to_abs,       'http://mojolicious.org/baz?f%23oo=bar', 'right URL';
  is $tx->req->url->query,        'f%23oo=bar',                            'right query';
  is $tx->req->headers->accept,   'application/json',                      'right "Accept" value';
  is $tx->req->headers->location, undef,                                   'no "Location" value';
  is $tx->req->body,              '',                                      'no content';
  is $tx->res->code,              undef,                                   'no status';
  is $tx->res->headers->location, undef,                                   'no "Location" value';
};

subtest '302 redirect for CONNECT request' => sub {
  my $tx = $t->tx(CONNECT => 'http://mojolicious.org');
  $tx->res->code(302);
  $tx->res->headers->location('http://example.com/bar');
  is $t->redirect($tx), undef, 'unsupported redirect';
};

subtest '301 redirect without compression' => sub {
  my $t  = Mojo::UserAgent::Transactor->new(compressed => 0);
  my $tx = $t->tx(POST => 'http://mojolicious.org/foo' => {Accept => 'application/json'});
  $tx->res->code(301);
  $tx->res->headers->location('http://example.com/bar');
  is $tx->res->content->auto_decompress, 0, 'right value';
  $tx = $t->redirect($tx);
  is $tx->res->content->auto_decompress, 0,                        'right value';
  is $tx->req->method,                   'GET',                    'right method';
  is $tx->req->url->to_abs,              'http://example.com/bar', 'right URL';
  is $tx->req->headers->user_agent,      'Mojolicious (Perl)',     'right "User-Agent" value';
  is $tx->req->headers->accept,          'application/json',       'right "Accept" value';
  is $tx->req->headers->location,        undef,                    'no "Location" value';
  is $tx->req->body,                     '',                       'no content';
  is $tx->res->code,                     undef,                    'no status';
  is $tx->res->headers->location,        undef,                    'no "Location" value';
};

subtest 'Download' => sub {
  my $dir          = tempdir;
  my $no_file      = $dir->child('no_file');
  my $small_file   = $dir->child('small_file')->spew('x');
  my $large_file   = $dir->child('large_file')->spew('xxxxxxxxxxx');
  my $correct_file = $dir->child('correct_file')->spew('xxxxxxxxxx');
  my $t            = Mojo::UserAgent::Transactor->new;

  subtest 'Partial file exists' => sub {
    my $head = $t->tx(HEAD => 'http://mojolicious.org/release.tar.gz');
    $head->res->headers->content_length(10);
    $head->res->headers->accept_ranges('bytes');
    my $tx = $t->download($head, $small_file);
    is $tx->req->method,         'GET',                                   'right method';
    is $tx->req->url->to_abs,    'http://mojolicious.org/release.tar.gz', 'right URL';
    is $tx->req->headers->range, 'bytes=1-10',                            'right "Range" value';
  };

  subtest 'Partial file exists (with headers)' => sub {
    my $head = $t->tx(HEAD => 'http://mojolicious.org/release.tar.gz' => {Accept => 'application/json'});
    $head->res->headers->content_length(10);
    $head->res->headers->accept_ranges('bytes');
    my $tx = $t->download($head, $small_file);
    is $tx->req->method,          'GET',                                   'right method';
    is $tx->req->url->to_abs,     'http://mojolicious.org/release.tar.gz', 'right URL';
    is $tx->req->headers->range,  'bytes=1-10',                            'right "Range" value';
    is $tx->req->headers->accept, 'application/json',                      'right "Accept" value';
  };

  subtest 'Failed HEAD request' => sub {
    my $head = $t->tx(HEAD => 'http://mojolicious.org/release.tar.gz');
    $head->res->error({message => 'Failed to connect'});
    my $tx = $t->download($head, $no_file);
    is $tx->error->{message}, 'Failed to connect', 'right error';
  };

  subtest 'Empty HEAD response' => sub {
    my $head = $t->tx(HEAD => 'http://mojolicious.org/release.tar.gz');
    my $tx   = $t->download($head, $no_file);
    is $tx->req->method,         'GET',                                   'right method';
    is $tx->req->url->to_abs,    'http://mojolicious.org/release.tar.gz', 'right URL';
    is $tx->req->headers->range, undef,                                   'no "Range" value';
  };

  subtest 'Empty HEAD response (file exists)' => sub {
    my $head = $t->tx(HEAD => 'http://mojolicious.org/release.tar.gz');
    my $tx   = $t->download($head, $small_file);
    is $tx->error->{message}, 'Unknown file size', 'right error';
  };

  subtest 'Target file does not exist' => sub {
    my $head = $t->tx(HEAD => 'http://mojolicious.org/release.tar.gz');
    $head->res->headers->content_length(10);
    my $tx = $t->download($head, $no_file);
    is $tx->req->method,         'GET',                                   'right method';
    is $tx->req->url->to_abs,    'http://mojolicious.org/release.tar.gz', 'right URL';
    is $tx->req->headers->range, undef,                                   'no "Range" value';
  };

  subtest 'Partial file exists (unsupported server)' => sub {
    my $head = $t->tx(HEAD => 'http://mojolicious.org/release.tar.gz');
    $head->res->headers->content_length(10);
    my $tx = $t->download($head, $small_file);
    is $tx->error->{message}, 'Server does not support partial requests', 'right error';
  };

  subtest 'Partial file exists (larger than download)' => sub {
    my $head = $t->tx(HEAD => 'http://mojolicious.org/release.tar.gz');
    $head->res->headers->content_length(10);
    $head->res->headers->accept_ranges('bytes');
    my $tx = $t->download($head, $large_file);
    is $tx->error->{message}, 'File size mismatch', 'right error';
  };

  subtest 'Download already finished' => sub {
    my $head = $t->tx(HEAD => 'http://mojolicious.org/release.tar.gz');
    $head->res->headers->content_length(10);
    $head->res->headers->accept_ranges('bytes');
    my $tx = $t->download($head, $correct_file);
    is $tx->error->{message}, 'Download complete', 'right error';
  };
};

subtest 'Promisify' => sub {
  my $promise = Mojo::Promise->new;
  my (@results, @errors);
  $promise->then(sub { push @results, @_ }, sub { push @errors, @_ });
  my $tx = $t->tx(GET => '/');
  $t->promisify($promise, $tx);
  $promise->wait;
  is_deeply \@results, [$tx], 'promise resolved';
  is_deeply \@errors,  [],    'promise not rejected';
  $promise = Mojo::Promise->new;
  (@results, @errors) = ();
  $promise->then(sub { push @results, @_ }, sub { push @errors, @_ });
  $tx = $t->websocket('/');
  $t->promisify($promise, $tx);
  $promise->wait;
  is_deeply \@results, [],                             'promise not resolved';
  is_deeply \@errors,  ['WebSocket handshake failed'], 'promise rejected';
  $promise = Mojo::Promise->new;
  (@results, @errors) = ();
  $promise->then(sub { push @results, @_ }, sub { push @errors, @_ });
  $tx = $t->tx(GET => '/');
  $tx->res->error({message => 'Premature connection close'});
  $t->promisify($promise, $tx);
  $promise->wait;
  is_deeply \@results, [],                             'promise not resolved';
  is_deeply \@errors,  ['Premature connection close'], 'promise rejected';
};

subtest 'Abstract methods' => sub {
  eval { Mojo::Transaction->client_read };
  like $@, qr/Method "client_read" not implemented by subclass/, 'right error';
  eval { Mojo::Transaction->client_write };
  like $@, qr/Method "client_write" not implemented by subclass/, 'right error';
  eval { Mojo::Transaction->server_read };
  like $@, qr/Method "server_read" not implemented by subclass/, 'right error';
  eval { Mojo::Transaction->server_write };
  like $@, qr/Method "server_write" not implemented by subclass/, 'right error';
};

done_testing();
