use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

app->static->prefix('/static');

get '/hello.txt' => {text => 'Just an action!'};

get '/helpers';

my $t = Test::Mojo->new;

subtest 'Action for static file path without prefix' => sub {
  $t->get_ok('/hello.txt')->status_is(200)->content_is('Just an action!');
};

subtest 'Static file' => sub {
  $t->get_ok('/static/hello.txt')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
    ->header_exists_not('Cache-Control')->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 31)
    ->content_is("Hello Mojo from a static file!\n");
};

subtest 'Static asset' => sub {
  $t->get_ok('/static/assets/foo.ab1234cd5678ef.css')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
    ->content_like(qr/\* foo\.css asset/);
};

subtest 'Bundled static file' => sub {
  $t->get_ok('/static/favicon.ico')->status_is(200)->content_type_is('image/x-icon');
};

subtest 'Bundled template' => sub {
  $t->get_ok('/doesnotexist')->status_is(404)->element_exists('link[href=/static/favicon.ico]')
    ->element_exists('link[href=/static/mojo/mojo.css]');
};

subtest 'Helpers with prefix' => sub {
  $t->get_ok('/helpers')->status_is(200)->content_is(<<EOF);
<link href="/static/favicon.ico" rel="icon">
<link href="/static/foo.ico" rel="icon">
<img src="/static/foo.png">
<script src="/static/foo.js"></script>
<link href="/static/foo.css" rel="stylesheet">
<script src="/static/assets/app.js"></script>
<link href="/static/assets/app.css" rel="stylesheet">
<img src="/static/assets/app.png">
<link href="/static/assets/foo.ab1234cd5678ef.css" rel="stylesheet">
EOF
};

subtest 'Hidden inline file' => sub {
  $t->get_ok('/static/hidden')->status_is(404)->content_unlike(qr/Unreachable file/);
};

subtest 'Base64 partial inline file' => sub {
  $t->get_ok('/static.txt')->status_is(404);
  $t->get_ok('/static/static.txt' => {Range => 'bytes=2-5'})->status_is(206)->header_is(Server => 'Mojolicious (Perl)')
    ->header_is('Accept-Ranges'  => 'bytes')->header_is('Content-Range' => 'bytes 2-5/15')
    ->header_is('Content-Length' => 4)->content_is('st 1');
};

subtest 'UTF-8 encoded inline file' => sub {
  $t->get_ok('/static_utf8.txt')->status_is(404);
  $t->get_ok('/static/static_utf8.txt')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("I ♥ Unicode\n");
};

subtest 'File' => sub {
  my $c = $t->app->build_controller;
  is $c->url_for_file('/unknown.css')->path, '/static/unknown.css', 'right file path';
  is $c->url_for_file('/foo/bar.css')->path, '/static/foo/bar.css', 'right file path';
};

done_testing();

__DATA__
@@helpers.html.ep
%= favicon
%= favicon '/foo.ico'
%= image '/foo.png'
%= javascript '/foo.js'
%= stylesheet '/foo.css'
%= asset_tag '/app.js'
%= asset_tag '/app.css'
%= asset_tag '/app.png'
%= asset_tag '/foo.css'

@@ hidden
Unreachable file.

@@ static.txt (base64)
dGVzdCAxMjMKbGFsYWxh

@@ static_utf8.txt
I ♥ Unicode
