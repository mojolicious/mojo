use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::Date;
use Mojolicious::Lite;
use Test::Mojo;

# GET /hello3.txt
get '/hello3.txt' => sub { shift->render_static('hello2.txt') };

my $t = Test::Mojo->new;

# GET /hello.txt (static file)
$t->get_ok('/hello.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 31)
  ->content_is("Hello Mojo from a static file!\n");

# GET /hello.txt (partial static file)
$t->get_ok('/hello.txt' => {Range => 'bytes=2-8'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 7)
  ->header_is('Content-Range' => 'bytes 2-8/31')->content_is('llo Moj');

# GET /hello.txt (partial static file, no end)
$t->get_ok('/hello.txt' => {Range => 'bytes=8-'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 23)
  ->header_is('Content-Range' => 'bytes 8-30/31')
  ->content_is("jo from a static file!\n");

# GET /hello.txt (partial static file, starting at first byte)
$t->get_ok('/hello.txt' => {Range => 'bytes=0-8'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 9)
  ->header_is('Content-Range' => 'bytes 0-8/31')->content_is('Hello Moj');

# GET /hello.txt (partial static file, first byte)
$t->get_ok('/hello.txt' => {Range => 'bytes=0-0'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 1)
  ->header_is('Content-Range' => 'bytes 0-0/31')->content_is('H');

# GET /hello.txt (partial static file, invalid range)
$t->get_ok('/hello.txt' => {Range => 'bytes=32-33'})->status_is(416)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is('');

# GET /hello3.txt (render_static and single byte file)
$t->get_ok('/hello3.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 1)
  ->content_is('X');

# GET /hello3.txt (render_static and partial single byte file)
$t->get_ok('/hello3.txt' => {Range => 'bytes=0-0'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 1)
  ->header_is('Content-Range' => 'bytes 0-0/1')->content_is('X');

# GET /hello4.txt (empty file)
$t->get_ok('/hello4.txt')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 0)->content_is('');

# GET /hello4.txt (empty file, invalid range)
$t->get_ok('/hello4.txt' => {Range => 'bytes=0-0'})->status_is(416)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 0)->content_is('');

# GET /static.txt (base64 static inline file, If-Modified-Since)
my $modified = Mojo::Date->new->epoch(time - 3600);
$t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("test 123\nlalala");
$modified = $t->tx->res->headers->last_modified;
$t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
  ->status_is(304)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('');

# GET /static.txt (base64 static inline file)
$t->get_ok('/static.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("test 123\nlalala");

# GET /static.txt (base64 static inline file, If-Modified-Since)
$modified = Mojo::Date->new->epoch(time - 3600);
$t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("test 123\nlalala");
$modified = $t->tx->res->headers->last_modified;
$t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
  ->status_is(304)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('');

# GET /static.txt (base64 partial inline file)
$t->get_ok('/static.txt' => {Range => 'bytes=2-5'})->status_is(206)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges'  => 'bytes')
  ->header_is('Content-Range'  => 'bytes 2-5/15')
  ->header_is('Content-Length' => 4)->content_is('st 1');

# GET /static.txt (base64 partial inline file, invalid range)
$t->get_ok('/static.txt' => {Range => 'bytes=45-50'})->status_is(416)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is('');

done_testing();

__DATA__
@@ static.txt (base64)
dGVzdCAxMjMKbGFsYWxh
