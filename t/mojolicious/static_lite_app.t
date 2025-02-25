use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::Mojo;
use Test::More;
use Mojo::Asset::Memory;
use Mojo::Date;
use Mojo::File qw(curfile);
use Mojolicious::Lite;

hook after_static => sub { shift->app->log->debug('Static file served') };

get '/hello3.txt' => sub { shift->reply->static('hello2.txt') };

post '/hello4.txt' => sub {
  my $c = shift;
  $c->res->headers->content_type('text/html');
  $c->reply->static('hello2.txt');
};

options '/hello.txt' => sub { shift->render(text => 'Options!') };

get '/etag' => sub {
  my $c = shift;
  $c->is_fresh(etag => 'abc') ? $c->rendered(304) : $c->render(text => 'I ♥ Mojolicious!');
};

get '/etag_weak' => sub {
  my $c = shift;
  $c->is_fresh(etag => 'W/"abc"') ? $c->rendered(304) : $c->render(text => 'I ♥ Mojolicious!');
};

get '/asset' => sub {
  my $c   = shift;
  my $mem = Mojo::Asset::Memory->new->add_chunk('I <3 Assets!');
  $c->reply->asset($mem);
};

get '/file' => sub {
  my $c = shift;
  $c->reply->file(curfile->sibling('templates2', '42.html.ep'));
};

my $t = Test::Mojo->new;

subtest 'Freshness (Etag)' => sub {
  my $c = $t->app->build_controller;
  ok !$c->is_fresh, 'content is stale';
  $c->res->headers->etag('"abc"');
  $c->req->headers->if_none_match('"abc"');
  ok $c->is_fresh, 'content is fresh (strong If-None-Match + strong ETag)';
  $c->res->headers->etag('W/"abc"');
  ok $c->is_fresh, 'content is fresh (strong If-None-Match + weak ETag)';
  $c->req->headers->if_none_match('W/"abc"');
  ok $c->is_fresh, 'content is fresh (weak If-None-Match + weak ETag)';
  $c->res->headers->etag('"abc"');
  ok !$c->is_fresh, 'content is not fresh (weak If-None-Match + strong ETag)';
  $c->res->headers->etag('"abc"');
  $c->req->headers->if_none_match('"fooie"', 'W/"abc"');
  ok !$c->is_fresh, 'content is not fresh (multiple If-None-Match + strong ETag)';
  $c->res->headers->etag('W/"abc"');
  $c->req->headers->if_none_match('W/"fooie"', '"abc"');
  ok $c->is_fresh, 'content is fresh (multiple If-None-Match + weak ETag)';
};

subtest 'Freshness (Last-Modified)' => sub {
  my $c    = $t->app->build_controller;
  my $date = Mojo::Date->new(23);
  $c->res->headers->last_modified($date);
  $c->req->headers->if_modified_since($date);
  ok $c->is_fresh, 'content is fresh';
};

subtest 'Freshness (Etag and Last-Modified)' => sub {
  my $c    = $t->app->build_controller;
  my $date = Mojo::Date->new(23);
  $c->req->headers->if_none_match('"abc"');
  $c->req->headers->if_modified_since($date);
  ok $c->is_fresh(etag => 'abc', last_modified => $date->epoch), 'content is fresh';
  is $c->res->headers->etag,          '"abc"', 'right "ETag" value';
  is $c->res->headers->last_modified, "$date", 'right "Last-Modified" value';

  $c = $t->app->build_controller;
  ok !$c->is_fresh(last_modified => $date->epoch), 'content is stale';
  is $c->res->headers->etag,          undef,   'no "ETag" value';
  is $c->res->headers->last_modified, "$date", 'right "Last-Modified" value';
};

subtest 'Freshness (multiple Etag values)' => sub {
  my $c = $t->app->build_controller;
  $c->req->headers->if_none_match('"cba", "abc"');
  ok $c->is_fresh(etag => 'abc'), 'content is fresh';
  $c = $t->app->build_controller;
  $c->req->headers->if_none_match('"abc", "cba"');
  ok $c->is_fresh(etag => 'abc'), 'content is fresh';
  $c = $t->app->build_controller;
  $c->req->headers->if_none_match(' "xyz" , "abc","cba" ');
  ok $c->is_fresh(etag => 'abc'), 'content is fresh';
  $c = $t->app->build_controller;
  $c->req->headers->if_none_match('"cba", "abc"');
  ok !$c->is_fresh(etag => 'cab'), 'content is stale';
};

subtest 'Static file' => sub {
  my $logs = $t->app->log->capture('trace');
  $t->get_ok('/hello.txt')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_exists_not('Cache-Control')
    ->header_is('Accept-Ranges'  => 'bytes')
    ->header_is('Content-Length' => 31)
    ->content_is("Hello Mojo from a static file!\n");
  like $logs,   qr/Static file served/, 'right message';
  unlike $logs, qr/200 OK/,             'no status message';
  undef $logs;
};

subtest 'Static file (HEAD)' => sub {
  $t->head_ok('/hello.txt')
    ->status_is(200)
    ->header_is(Server           => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges'  => 'bytes')
    ->header_is('Content-Length' => 31)
    ->content_is('');
};

subtest 'Route for method other than GET and HEAD' => sub {
  $t->options_ok('/hello.txt')
    ->status_is(200)
    ->header_is(Server           => 'Mojolicious (Perl)')
    ->header_is('Content-Length' => 8)
    ->content_is('Options!');
};

subtest 'Unknown method' => sub {
  $t->put_ok('/hello.txt')->status_is(404)->header_is(Server => 'Mojolicious (Perl)');
};

subtest 'Partial static file' => sub {
  $t->get_ok('/hello.txt' => {Range => 'bytes=2-8'})
    ->status_is(206)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_exists_not('Cache-Control')
    ->header_is('Accept-Ranges'  => 'bytes')
    ->header_is('Content-Length' => 7)
    ->header_is('Content-Range'  => 'bytes 2-8/31')
    ->content_is('llo Moj');
};

subtest 'Partial static file, no end' => sub {
  $t->get_ok('/hello.txt' => {Range => 'bytes=8-'})
    ->status_is(206)
    ->header_is(Server           => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges'  => 'bytes')
    ->header_is('Content-Length' => 23)
    ->header_is('Content-Range'  => 'bytes 8-30/31')
    ->content_is("jo from a static file!\n");
};

subtest 'Partial static file, no start' => sub {
  $t->get_ok('/hello.txt' => {Range => 'bytes=-8'})
    ->status_is(206)
    ->header_is(Server           => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges'  => 'bytes')
    ->header_is('Content-Length' => 9)
    ->header_is('Content-Range'  => 'bytes 0-8/31')
    ->content_is('Hello Moj');
};

subtest 'Partial static file, starting at first byte' => sub {
  $t->get_ok('/hello.txt' => {Range => 'bytes=0-8'})
    ->status_is(206)
    ->header_is(Server           => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges'  => 'bytes')
    ->header_is('Content-Length' => 9)
    ->header_is('Content-Range'  => 'bytes 0-8/31')
    ->content_is('Hello Moj');
};

subtest 'Partial static file, invalid range' => sub {
  $t->get_ok('/hello.txt' => {Range => 'bytes=8-1'})
    ->status_is(416)
    ->header_is(Server          => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges' => 'bytes')
    ->content_is('');
};

subtest 'Partial static file, first byte' => sub {
  $t->get_ok('/hello.txt' => {Range => 'bytes=0-0'})
    ->status_is(206)
    ->header_is(Server           => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges'  => 'bytes')
    ->header_is('Content-Length' => 1)
    ->header_is('Content-Range'  => 'bytes 0-0/31')
    ->content_is('H');
};

subtest 'Partial static file, end outside of range' => sub {
  $t->get_ok('/hello.txt' => {Range => 'bytes=25-31'})
    ->status_is(206)
    ->header_is(Server           => 'Mojolicious (Perl)')
    ->header_is('Content-Length' => 6)
    ->header_is('Content-Range'  => 'bytes 25-30/31')
    ->header_is('Accept-Ranges'  => 'bytes')
    ->content_is("file!\n");
};

subtest 'Partial static file, end way outside of range' => sub {
  $t->get_ok('/hello.txt' => {Range => 'bytes=25-300'})
    ->status_is(206)
    ->header_is(Server           => 'Mojolicious (Perl)')
    ->header_is('Content-Length' => 6)
    ->header_is('Content-Range'  => 'bytes 25-30/31')
    ->header_is('Accept-Ranges'  => 'bytes')
    ->content_is("file!\n");
};

subtest 'Partial static file, invalid range' => sub {
  $t->get_ok('/hello.txt' => {Range => 'bytes=32-33'})
    ->status_is(416)
    ->header_is(Server          => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges' => 'bytes')
    ->content_is('');
};

subtest 'Render single byte static file' => sub {
  $t->get_ok('/hello3.txt')
    ->status_is(200)
    ->header_is(Server           => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges'  => 'bytes')
    ->header_is('Content-Length' => 1)
    ->content_is('X');
};

subtest 'Render partial single byte static file' => sub {
  $t->get_ok('/hello3.txt' => {Range => 'bytes=0-0'})
    ->status_is(206)
    ->header_is(Server           => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges'  => 'bytes')
    ->header_is('Content-Length' => 1)
    ->header_is('Content-Range'  => 'bytes 0-0/1')
    ->content_is('X');
};

subtest 'Render static file with custom content type' => sub {
  $t->post_ok('/hello4.txt')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_type_is('text/html')
    ->header_is('Content-Length' => 1)
    ->content_is('X');
};

subtest 'Fresh content' => sub {
  $t->get_ok('/etag')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_is(ETag   => '"abc"')
    ->content_is('I ♥ Mojolicious!');
  $t->get_ok('/etag_weak')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_is(ETag   => 'W/"abc"')
    ->content_is('I ♥ Mojolicious!');
  $t->get_ok('/etag' => {'If-None-Match' => 'W/"abc"'})
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_is(ETag   => '"abc"')
    ->content_is('I ♥ Mojolicious!');
};

subtest 'Stale content' => sub {
  $t->get_ok('/etag' => {'If-None-Match' => '"abc"'})
    ->status_is(304)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_is(ETag   => '"abc"')
    ->content_is('');
  $t->get_ok('/etag_weak' => {'If-None-Match' => '"abc"'})
    ->status_is(304)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_is(ETag   => 'W/"abc"')
    ->content_is('');
  $t->get_ok('/etag_weak' => {'If-None-Match' => 'W/"abc"'})
    ->status_is(304)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_is(ETag   => 'W/"abc"')
    ->content_is('');
};

subtest 'Fresh asset' => sub {
  $t->get_ok('/asset')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('I <3 Assets!');
};

subtest 'Stale asset' => sub {
  my $etag = $t->tx->res->headers->etag;
  $t->get_ok('/asset' => {'If-None-Match' => $etag})
    ->status_is(304)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is('');
};

subtest 'Partial asset' => sub {
  $t->get_ok('/asset' => {'Range' => 'bytes=3-5'})
    ->status_is(206)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_exists_not('Cache-Control')
    ->content_is('3 A');
};

subtest 'File' => sub {
  $t->get_ok('/file' => {'Range' => 'bytes=4-9'})
    ->status_is(206)
    ->content_type_is('application/octet-stream')
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is('answer');
};

subtest 'Empty file' => sub {
  $t->get_ok('/hello4.txt')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is('');
};

subtest 'Partial empty file' => sub {
  $t->get_ok('/hello4.txt' => {Range => 'bytes=0-0'})
    ->status_is(416)
    ->header_is(Server          => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges' => 'bytes')
    ->content_is('');
};

subtest 'Hidden inline file' => sub {
  $t->get_ok('/hidden')->status_is(404)->content_unlike(qr/Unreachable file/);
};

subtest 'Base64 static inline file, If-Modified-Since' => sub {
  my $modified = Mojo::Date->new->epoch($^T - 1);
  $t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
    ->status_is(200)
    ->header_is(Server          => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges' => 'bytes')
    ->content_is("test 123\nlalala");
  $modified = $t->tx->res->headers->last_modified;
  $t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
    ->status_is(304)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is('');
};

subtest 'Base64 static inline file' => sub {
  $t->get_ok('/static.txt')
    ->status_is(200)
    ->header_is(Server          => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges' => 'bytes')
    ->content_is("test 123\nlalala");
};

subtest 'Base64 static inline file, If-Modified-Since' => sub {
  my $modified = Mojo::Date->new->epoch($^T - 1);
  $t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
    ->status_is(200)
    ->header_is(Server          => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges' => 'bytes')
    ->content_is("test 123\nlalala");
  $modified = $t->tx->res->headers->last_modified;
  $t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
    ->status_is(304)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is('');
};

subtest 'Base64 partial inline file' => sub {
  $t->get_ok('/static.txt' => {Range => 'bytes=2-5'})
    ->status_is(206)
    ->header_is(Server           => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges'  => 'bytes')
    ->header_is('Content-Range'  => 'bytes 2-5/15')
    ->header_is('Content-Length' => 4)
    ->content_is('st 1');
};

subtest 'Base64 partial inline file, invalid range' => sub {
  $t->get_ok('/static.txt' => {Range => 'bytes=45-50'})
    ->status_is(416)
    ->header_is(Server          => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges' => 'bytes')
    ->content_is('');
};

subtest 'UTF-8 encoded inline file' => sub {
  $t->get_ok('/static_utf8.txt')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("I ♥ Unicode\n");
};

subtest 'Assets' => sub {
  my $c = $t->app->build_controller;
  is $c->url_for_asset('/unknown.css')->path,         '/assets/unknown.css',                        'right asset path';
  is $c->url_for_asset('foo.css')->path,              '/assets/foo.ab1234cd5678ef.css',             'right asset path';
  is $c->url_for_asset('/foo.css')->path,             '/assets/foo.ab1234cd5678ef.css',             'right asset path';
  is $c->url_for_asset('/foo.js')->path,              '/assets/foo.ab1234cd5678ef.js',              'right asset path';
  is $c->url_for_asset('/foo/bar/baz.js')->path,      '/assets/foo/bar/baz.development.js',         'right asset path';
  is $c->url_for_asset('/foo/bar.js')->path,          '/assets/foo/bar.321.js',                     'right asset path';
  is $c->url_for_asset('/foo/bar/test.min.js')->path, '/assets/foo/bar/test.ab1234cd5678ef.min.js', 'right asset path';
  is $c->url_for_asset('/foo/bar/yada.css')->path,    '/assets/foo/bar/yada.css',                   'right asset path';

  $t->get_ok('/assets/foo.ab1234cd5678ef.css')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_is('Cache-Control', 'no-cache')
    ->content_like(qr/\* foo\.css asset/);
  $t->get_ok('/assets/foo.ab1234cd5678ef.js')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_is('Cache-Control', 'no-cache')
    ->content_like(qr/\* foo\.js asset/);
  $t->get_ok('/assets/foo/bar.321.js')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_is('Cache-Control', 'no-cache')
    ->content_like(qr/\* foo\/bar\.js asset/);
  $t->get_ok('/assets/foo/bar/baz.development.js')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_is('Cache-Control', 'no-cache')
    ->content_like(qr/\* foo\/bar\/baz\.js development asset/);
  $t->get_ok('/assets/foo/bar/baz.123.js')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_is('Cache-Control', 'no-cache')
    ->content_like(qr/\* foo\/bar\/baz\.js asset/);
  $t->get_ok('/assets/foo/bar/test.ab1234cd5678ef.min.js')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_is('Cache-Control', 'no-cache')
    ->content_like(qr/\* foo\/bar\/test\.min\.js asset/);
  $t->get_ok('/assets/foo/bar/yada.css')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_is('Cache-Control', 'no-cache')
    ->content_like(qr/\* foo\/bar\/yada\.css asset/);

  $t->app->mode('production');
  $t->get_ok('/assets/foo.ab1234cd5678ef.css')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->header_exists_not('Cache-Control')
    ->content_like(qr/\* foo\.css asset/);
};

subtest 'File' => sub {
  my $c = $t->app->build_controller;
  is $c->url_for_file('/unknown.css')->path, '/unknown.css', 'right file path';
  is $c->url_for_file('/foo/bar.css')->path, '/foo/bar.css', 'right file path';
};

done_testing();

__DATA__
@@ hidden
Unreachable file.

@@ static.txt (base64)
dGVzdCAxMjMKbGFsYWxh

@@ static_utf8.txt
I ♥ Unicode
