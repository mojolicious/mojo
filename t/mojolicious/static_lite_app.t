use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::Asset::Memory;
use Mojo::Date;
use Mojolicious::Lite;
use Test::Mojo;

get '/hello3.txt' => sub { shift->reply->static('hello2.txt') };

post '/hello4.txt' => sub {
  my $c = shift;
  $c->res->headers->content_type('text/html');
  $c->reply->static('hello2.txt');
};

options '/hello.txt' => sub { shift->render(text => 'Options!') };

get '/etag' => sub {
  my $c = shift;
  $c->is_fresh(etag => 'abc')
    ? $c->rendered(304)
    : $c->render(text => 'I ♥ Mojolicious!');
};

get '/asset' => sub {
  my $c   = shift;
  my $mem = Mojo::Asset::Memory->new->add_chunk('I <3 Assets!');
  $c->reply->asset($mem);
};

my $t = Test::Mojo->new;

# Freshness
my $c = $t->app->build_controller;
ok !$c->is_fresh, 'content is stale';
$c->res->headers->etag('"abc"');
$c->req->headers->if_none_match('"abc"');
ok $c->is_fresh, 'content is fresh';
$c = $t->app->build_controller;
my $date = Mojo::Date->new(23);
$c->res->headers->last_modified($date);
$c->req->headers->if_modified_since($date);
ok $c->is_fresh, 'content is fresh';
$c = $t->app->build_controller;
$c->req->headers->if_none_match('"abc"');
$c->req->headers->if_modified_since($date);
ok $c->is_fresh(etag => 'abc', last_modified => $date->epoch),
  'content is fresh';
is $c->res->headers->etag,          '"abc"', 'right "ETag" value';
is $c->res->headers->last_modified, "$date", 'right "Last-Modified" value';
$c = $t->app->build_controller;
ok !$c->is_fresh(last_modified => $date->epoch), 'content is stale';
is $c->res->headers->etag,          undef,   'no "ETag" value';
is $c->res->headers->last_modified, "$date", 'right "Last-Modified" value';

# Static file
$t->get_ok('/hello.txt')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 31)
  ->content_is("Hello Mojo from a static file!\n");

# Static file (HEAD)
$t->head_ok('/hello.txt')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 31)
  ->content_is('');

# Route for method other than GET and HEAD
$t->options_ok('/hello.txt')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 8)->content_is('Options!');

# Unknown method
$t->put_ok('/hello.txt')->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)');

# Partial static file
$t->get_ok('/hello.txt' => {Range => 'bytes=2-8'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 7)
  ->header_is('Content-Range' => 'bytes 2-8/31')->content_is('llo Moj');

# Partial static file, no end
$t->get_ok('/hello.txt' => {Range => 'bytes=8-'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 23)
  ->header_is('Content-Range' => 'bytes 8-30/31')
  ->content_is("jo from a static file!\n");

# Partial static file, no start
$t->get_ok('/hello.txt' => {Range => 'bytes=-8'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 9)
  ->header_is('Content-Range' => 'bytes 0-8/31')->content_is('Hello Moj');

# Partial static file, starting at first byte
$t->get_ok('/hello.txt' => {Range => 'bytes=0-8'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 9)
  ->header_is('Content-Range' => 'bytes 0-8/31')->content_is('Hello Moj');

# Partial static file, invalid range
$t->get_ok('/hello.txt' => {Range => 'bytes=8-1'})->status_is(416)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is('');

# Partial static file, first byte
$t->get_ok('/hello.txt' => {Range => 'bytes=0-0'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 1)
  ->header_is('Content-Range' => 'bytes 0-0/31')->content_is('H');

# Partial static file, end outside of range
$t->get_ok('/hello.txt' => {Range => 'bytes=25-31'})->status_is(206)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 6)
  ->header_is('Content-Range'  => 'bytes 25-30/31')
  ->header_is('Accept-Ranges'  => 'bytes')->content_is("file!\n");

# Partial static file, end way outside of range
$t->get_ok('/hello.txt' => {Range => 'bytes=25-300'})->status_is(206)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 6)
  ->header_is('Content-Range'  => 'bytes 25-30/31')
  ->header_is('Accept-Ranges'  => 'bytes')->content_is("file!\n");

# Partial static file, invalid range
$t->get_ok('/hello.txt' => {Range => 'bytes=32-33'})->status_is(416)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is('');

# Render single byte static file
$t->get_ok('/hello3.txt')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 1)
  ->content_is('X');

# Render partial single byte static file
$t->get_ok('/hello3.txt' => {Range => 'bytes=0-0'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 1)
  ->header_is('Content-Range' => 'bytes 0-0/1')->content_is('X');

# Render static file with custom content type
$t->post_ok('/hello4.txt')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/html')
  ->header_is('Content-Length' => 1)->content_is('X');

# Fresh content
$t->get_ok('/etag')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is(ETag => '"abc"')->content_is('I ♥ Mojolicious!');

# Stale content
$t->get_ok('/etag' => {'If-None-Match' => '"abc"'})->status_is(304)
  ->header_is(Server => 'Mojolicious (Perl)')->header_is(ETag => '"abc"')
  ->content_is('');

# Fresh asset
$t->get_ok('/asset')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('I <3 Assets!');
my $etag = $t->tx->res->headers->etag;

# Stale asset
$t->get_ok('/asset' => {'If-None-Match' => $etag})->status_is(304)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('');

# Partial asset
$t->get_ok('/asset' => {'Range' => 'bytes=3-5'})->status_is(206)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('3 A');

# Empty file
$t->get_ok('/hello4.txt')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 0)->content_is('');

# Partial empty file
$t->get_ok('/hello4.txt' => {Range => 'bytes=0-0'})->status_is(416)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is('');

# Hidden inline file
$t->get_ok('/hidden')->status_is(404)->content_unlike(qr/Unreachable file/);

# Base64 static inline file, If-Modified-Since
my $modified = Mojo::Date->new->epoch(time - 3600);
$t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("test 123\nlalala");
$modified = $t->tx->res->headers->last_modified;
$t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
  ->status_is(304)->header_is(Server => 'Mojolicious (Perl)')->content_is('');

# Base64 static inline file
$t->get_ok('/static.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("test 123\nlalala");

# Base64 static inline file, If-Modified-Since
$modified = Mojo::Date->new->epoch(time - 3600);
$t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("test 123\nlalala");
$modified = $t->tx->res->headers->last_modified;
$t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
  ->status_is(304)->header_is(Server => 'Mojolicious (Perl)')->content_is('');

# Base64 partial inline file
$t->get_ok('/static.txt' => {Range => 'bytes=2-5'})->status_is(206)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges'  => 'bytes')
  ->header_is('Content-Range'  => 'bytes 2-5/15')
  ->header_is('Content-Length' => 4)->content_is('st 1');

# Base64 partial inline file, invalid range
$t->get_ok('/static.txt' => {Range => 'bytes=45-50'})->status_is(416)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is('');

done_testing();

__DATA__
@@ hidden
Unreachable file.

@@ static.txt (base64)
dGVzdCAxMjMKbGFsYWxh
