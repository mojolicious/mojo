#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use utf8;

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan tests => 381;

# Wait you're the only friend I have...
# You really want a robot for a friend?
# Yeah ever since I was six.
# Well, ok but I don't want people thinking we're robosexuals,
# so if anyone asks you're my debugger.
use Mojo::ByteStream 'b';
use Mojo::Client;
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojo::Cookie::Response;
use Mojo::JSON;
use Mojo::Transaction::HTTP;
use Mojolicious::Lite;
use Test::Mojo;

# Silence
app->log->level('error');

# Test with lite templates
app->renderer->default_handler('epl');

# Header condition plugin
plugin 'header_condition';

# GET /
get '/' => 'root';

# GET /root
get '/root.html' => 'root_path';

# GET /template.txt
get '/template.txt' => 'template';

# GET /address
get '/address' => sub {
    my $self = shift;
    $self->render_text($self->tx->remote_address);
};

# POST /upload
post '/upload' => sub {
    my $self = shift;
    my $body = $self->res->body || '';
    $self->res->body("called, $body");
    return if $self->req->has_error;
    if (my $u = $self->req->upload('Вячеслав')) {
        $self->stash(rendered => 1);
        $self->res->body($self->res->body . $u->filename . $u->size);
    }
};

# GET /foo_relaxed/*
get '/foo_relaxed/(.test)' => sub {
    my $self = shift;
    $self->render_text($self->stash('test'));
};

# GET /foo_wildcard/*
get '/foo_wildcard/(*test)' => sub {
    my $self = shift;
    $self->render_text($self->stash('test'));
};

# GET /with/header/condition
get '/with/header/condition' => (headers => {'X-Secret-Header' => 'bar'}) =>
  'with_header_condition';

# POST /with/header/condition
post '/with/header/condition' => (headers => {'X-Secret-Header' => 'bar'}) =>
  sub {
    my $self = shift;
    $self->render_text(
        'foo ' . $self->req->headers->header('X-Secret-Header'));
  };

# POST /with/body/and/desc
post '/with/body/and/desc' => sub {
    my $self = shift;
    return if $self->req->body ne 'body';
    $self->render_text('bar');
};

# POST /with/body/and/headers/desc
post '/with/body/and/headers/desc' => sub {
    my $self = shift;
    return
      if $self->req->headers->header('with') ne 'header'
          || $self->req->body ne 'body';
    $self->render_text('bar');
};

# GET /template_inheritance
get '/template_inheritance' =>
  sub { shift->render(template => 'template_inheritance') };

# GET /layout_without_inheritance
get '/layout_without_inheritance' => sub {
    shift->render(
        template => 'layouts/template_inheritance',
        handler  => 'ep'
    );
};

# GET /double_inheritance
get '/double_inheritance' =>
  sub { shift->render(template => 'double_inheritance') };

# GET /outerlayout
get '/outerlayout' => sub {
    my $self = shift;
    $self->render(
        template => 'outerlayout',
        layout   => 'layout',
        handler  => 'ep'
    );
};

# GET /outerlayouttwo
get '/outerlayouttwo' => {layout => 'layout'} => sub {
    my $self = shift;
    is($self->stash->{layout}, 'layout');
    $self->render(handler => 'ep');
    is($self->stash->{layout}, 'layout');
} => 'outerlayout';

# GET /outerinnerlayout
get '/outerinnerlayout' => sub {
    my $self = shift;
    $self->render(
        template => 'outerinnerlayout',
        layout   => 'layout',
        handler  => 'ep'
    );
};

# GET /session_cookie
get '/session_cookie' => sub {
    my $self = shift;
    $self->render_text('Cookie set!');
    $self->res->cookies(
        Mojo::Cookie::Response->new(
            path  => '/session_cookie',
            name  => 'session',
            value => '23'
        )
    );
};

# GET /session_cookie/2
get '/session_cookie/2' => sub {
    my $self    = shift;
    my $session = $self->req->cookie('session');
    my $value   = $session ? $session->value : 'missing';
    $self->render_text("Session is $value!");
};

# GET /foo
get '/foo' => sub {
    my $self = shift;
    $self->render_text('Yea baby!');
};

# GET /layout
get '/layout' => sub {
    shift->render_text('Yea baby!', layout => 'layout', handler => 'epl');
};

# POST /template
post '/template' => 'index';

# * /something
any '/something' => sub {
    my $self = shift;
    $self->render_text('Just works!');
};

# GET|POST /something/else
any [qw/get post/] => '/something/else' => sub {
    my $self = shift;
    $self->render_text('Yay!');
};

# GET /regex/*
get '/regex/:test' => [test => qr/\d+/] => sub {
    my $self = shift;
    $self->render_text($self->stash('test'));
};

# POST /bar/*
post '/bar/:test' => {test => 'default'} => sub {
    my $self = shift;
    $self->render_text($self->stash('test'));
};

# GET /firefox/*
get '/firefox/:stuff' => (agent => qr/Firefox/) => sub {
    my $self = shift;
    $self->render_text($self->url_for('foxy', stuff => 'foo'));
} => 'foxy';

# POST /utf8
post '/utf8' => 'form';

# POST /malformed_UTF-8
post '/malformed_utf8' => sub {
    my $c = shift;
    $c->render_text(b($c->param('foo'))->url_escape->to_string);
};

# GET /json
get '/json' => sub { shift->render_json({foo => [1, -2, 3, 'bar']}) };

# GET /autostash
get '/autostash' => sub { shift->render(handler => 'ep', foo => 'bar') } =>
  'autostash';

# GET /helper
get '/helper' => sub { shift->render(handler => 'ep') } => 'helper';
app->renderer->add_helper(
    agent => sub { scalar shift->req->headers->user_agent });

# GET /eperror
get '/eperror' => sub { shift->render(handler => 'ep') } => 'eperror';

# GET /subrequest
get '/subrequest' => sub {
    my $self = shift;
    $self->pause;
    $self->client->post(
        '/template' => sub {
            my $client = shift;
            $self->render_text($client->tx->success->body);
            $self->finish;
        }
    )->process;
};

# GET /subrequest_simple
get '/subrequest_simple' => sub {
    my $self = shift;
    my $tx   = $self->client->post('/template');
    $self->render_text($tx->res->body);
};

# GET /subrequest_sync
get '/subrequest_sync' => sub {
    my $self = shift;
    $self->client->post(
        '/template' => sub {
            my $client = shift;
            $client->post(
                '/template' => sub {
                    my $client = shift;
                    $self->render_text($client->res->body);
                }
            )->process;
        }
    )->process;
};

# GET /subrequest_async
get '/subrequest_async' => sub {
    my $self = shift;
    $self->pause;
    $self->client->async->post(
        '/template' => sub {
            my $client = shift;
            $self->render_text($client->res->body);
            $self->finish;
        }
    )->process;
};

# GET /redirect_url
get '/redirect_url' => sub {
    shift->redirect_to('http://127.0.0.1/foo')->render_text('Redirecting!');
};

# GET /redirect_path
get '/redirect_path' => sub {
    shift->redirect_to('/foo/bar')->render_text('Redirecting!');
};

# GET /redirect_named
get '/redirect_named' => sub {
    shift->redirect_to('index', format => 'txt')->render_text('Redirecting!');
};

# GET /koi8-r
app->types->type('koi8-r' => 'text/html; charset=koi8-r');
get '/koi8-r' => sub {
    app->renderer->encoding('koi8-r');
    shift->render('encoding', format => 'koi8-r', handler => 'ep');
    app->renderer->encoding(undef);
};

# GET /hello3.txt
get '/hello3.txt' => sub { shift->render_static('hello2.txt') };

ladder sub {
    my $self = shift;
    return unless $self->req->headers->header('X-Bender');
    $self->res->headers->header('X-Ladder' => 23);
    return 1;
};

# GET /with_ladder
get '/with_ladder' => sub {
    my $self = shift;
    $self->render_text('Ladders are cool!');
};

# GET /with_ladder_too
get '/with_ladder_too' => sub {
    my $self = shift;
    $self->render_text('Ladders are cool too!');
};

ladder sub {
    my $self = shift;

    # Authenticated
    my $name = $self->param('name') || '';
    return 1 if $name eq 'Bender';

    # Not authenticated
    $self->render('param_auth_denied');
    return;
};

# GET /param_auth
get '/param_auth' => 'param_auth';

# GET /param_auth/too
get '/param_auth/too' =>
  sub { shift->render_text('You could be Bender too!') };

ladder sub {
    my $self = shift;
    $self->stash(_name => 'stash');
    $self->cookie(foo => 'cookie', {expires => (time + 60)});
    $self->signed_cookie(bar => 'signed_cookie', {expires => (time + 120)});
    $self->cookie(bad => 'bad_cookie--12345678');
    return 1;
};

# GET /bridge2stash
get '/bridge2stash' =>
  sub { shift->render(template => 'bridge2stash', handler => 'ep'); };

# Oh Fry, I love you more than the moon, and the stars,
# and the POETIC IMAGE NUMBER 137 NOT FOUND
my $client = app->client;
my $t      = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/root.html/root.html/root.html/root.html/root.html');

# HEAD /
$t->head_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 50)->content_is('');

# GET / (with body)
$t->get_ok('/', '1234' x 1024)->status_is(200)
  ->content_is('/root.html/root.html/root.html/root.html/root.html');

# GET /root
$t->get_ok('/root.html')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('/.html');

# GET /.html
$t->get_ok('/.html')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/root.html/root.html/root.html/root.html/root.html');

# GET /address (reverse proxy)
my $backup = $ENV{MOJO_REVERSE_PROXY};
$ENV{MOJO_REVERSE_PROXY} = 1;
$t->get_ok('/address', {'X-Forwarded-For' => '192.168.2.2, 192.168.2.1'})
  ->status_is(200)->content_is('192.168.2.1');
$ENV{MOJO_REVERSE_PROXY} = $backup;

# POST /upload (huge upload without appropriate max message size)
$backup = $ENV{MOJO_MAX_MESSAGE_SIZE} || '';
$ENV{MOJO_MAX_MESSAGE_SIZE} = 2048;
my $backup2 = app->log->level;
app->log->level('fatal');
my $tx   = Mojo::Transaction::HTTP->new;
my $part = Mojo::Content::Single->new;
my $name = b('Вячеслав')->url_escape;
$part->headers->content_disposition(
    qq/form-data; name="$name"; filename="$name.jpg"/);
$part->headers->content_type('image/jpeg');
$part->asset->add_chunk('1234' x 1024);
my $content = Mojo::Content::MultiPart->new;
$content->headers($tx->req->headers);
$content->headers->content_type('multipart/form-data');
$content->parts([$part]);
$tx->req->method('POST');
$tx->req->url->parse('/upload');
$tx->req->content($content);
$client->process($tx);
is($tx->res->code, 413);
is($tx->res->body, 'called, ');
app->log->level($backup2);
$ENV{MOJO_MAX_MESSAGE_SIZE} = $backup;

# POST /upload (huge upload with appropriate max message size)
$backup = $ENV{MOJO_MAX_MESSAGE_SIZE} || '';
$ENV{MOJO_MAX_MESSAGE_SIZE} = 1073741824;
$tx                         = Mojo::Transaction::HTTP->new;
$part                       = Mojo::Content::Single->new;
$name                       = b('Вячеслав')->url_escape;
$part->headers->content_disposition(
    qq/form-data; name="$name"; filename="$name.jpg"/);
$part->headers->content_type('image/jpeg');
$part->asset->add_chunk('1234' x 1024);
$content = Mojo::Content::MultiPart->new;
$content->headers($tx->req->headers);
$content->headers->content_type('multipart/form-data');
$content->parts([$part]);
$tx->req->method('POST');
$tx->req->url->parse('/upload');
$tx->req->content($content);
$client->process($tx);
is($tx->state,     'done');
is($tx->res->code, 200);
is(b($tx->res->body)->decode('UTF-8')->to_string,
    'called, Вячеслав.jpg4096');
$ENV{MOJO_MAX_MESSAGE_SIZE} = $backup;

# GET / (with body and max message size)
$backup = $ENV{MOJO_MAX_MESSAGE_SIZE} || '';
$ENV{MOJO_MAX_MESSAGE_SIZE} = 1024;
$backup2 = app->log->level;
app->log->level('fatal');
$t->get_ok('/', '1234' x 1024)->status_is(413)
  ->content_is('/root.html/root.html/root.html/root.html/root.html');
app->log->level($backup2);
$ENV{MOJO_MAX_MESSAGE_SIZE} = $backup;

# GET /foo_relaxed/123
$t->get_ok('/foo_relaxed/123')->status_is(200)->content_is('123');

# GET /foo_relaxed
$t->get_ok('/foo_relaxed/')->status_is(404);

# GET /foo_wildcard/123
$t->get_ok('/foo_wildcard/123')->status_is(200)->content_is('123');

# GET /foo_wildcard
$t->get_ok('/foo_wildcard/')->status_is(404);

# GET /with/header/condition
$t->get_ok('/with/header/condition', {'X-Secret-Header' => 'bar'})
  ->status_is(200)->content_like(qr/^Test ok/);

# GET /with/header/condition (not found)
$t->get_ok('/with/header/condition')->status_is(404)->content_like(qr/Oops!/);

# POST /with/header/condition
$t->post_ok('/with/header/condition', {'X-Secret-Header' => 'bar'}, 'bar')
  ->status_is(200)->content_is('foo bar');

# POST /with/header/condition (not found)
$t->post_ok('/with/header/condition', {}, 'bar')->status_is(404)
  ->content_like(qr/Oops!/);

# POST /with/body/and/desc
$t->post_ok('/with/body/and/desc', 'body', 'desc')->status_is(200)
  ->content_is('bar');

# POST /with/body/and/headers/and/desc
$t->post_ok('/with/body/and/headers/desc', {with => 'header'}, 'body', 'desc')
  ->status_is(200)->content_is('bar');

# GET /template_inheritance
$t->get_ok('/template_inheritance')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
    "<title>Welcome</title>\nSidebar!\nHello World!\nDefault footer!\n");

# GET /layout_without_inheritance
$t->get_ok('/layout_without_inheritance')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Default header!\nDefault sidebar!\nDefault footer!\n");

# GET /double_inheritance
$t->get_ok('/double_inheritance')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("<title>Welcome</title>\nSidebar too!\nDefault footer!\n");

# GET /outerlayout
$t->get_ok('/outerlayout')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("layouted Hello\n[\n  1,\n  2\n]\nthere<br/>!\n\n\n");

# GET /outerlayouttwo
$t->get_ok('/outerlayouttwo')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("layouted Hello\n[\n  1,\n  2\n]\nthere<br/>!\n\n\n");

# GET /outerinnerlayout
$t->get_ok('/outerinnerlayout')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
    "layouted Hello\nlayouted [\n  1,\n  2\n]\nthere<br/>!\n\n\n\n");

# GET /session_cookie
$t->get_ok('/session_cookie')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Cookie set!');

# GET /session_cookie/2
$t->get_ok('/session_cookie/2')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Session is 23!');

# GET /session_cookie/2 (retry)
$t->get_ok('/session_cookie/2')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Session is 23!');

# GET /session_cookie/2 (session reset)
$t->reset_session;
ok(!$t->tx);
$t->get_ok('/session_cookie/2')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Session is missing!');

# GET /foo
$t->get_ok('/foo')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Yea baby!');

# POST /template
$t->post_ok('/template')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# GET /something
$t->get_ok('/something')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# POST /something
$t->post_ok('/something')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# DELETE /something
$t->delete_ok('/something')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# GET /something/else
$t->get_ok('/something/else')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Yay!');

# POST /something/else
$t->post_ok('/something/else')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Yay!');

# DELETE /something/else
$t->delete_ok('/something/else')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Oops!/);

# GET /regex/23
$t->get_ok('/regex/23')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('23');

# GET /regex/foo
$t->get_ok('/regex/foo')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Oops!/);

# POST /bar
$t->post_ok('/bar')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('default');

# POST /bar/baz
$t->post_ok('/bar/baz')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('baz');

# GET /layout
$t->get_ok('/layout')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Yea baby! with layout\n");

# GET /firefox
$t->get_ok('/firefox/bar', {'User-Agent' => 'Firefox'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/firefox/foo');

# GET /firefox
$t->get_ok('/firefox/bar', {'User-Agent' => 'Explorer'})->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Oops!/);

# POST /utf8
$t->post_form_ok('/utf8', 'UTF-8' => {name => 'Вячеслав'})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 40)->content_type_is('text/html')
  ->content_is(b("Вячеслав Тихановский\n")->encode('UTF-8')
      ->to_string);

# POST /utf8 (multipart/form-data)
$t->post_form_ok(
    '/utf8',
    'UTF-8' => {name => 'Вячеслав'},
    {'Content-Type' => 'multipart/form-data'}
  )->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 40)->content_type_is('text/html')
  ->content_is(b("Вячеслав Тихановский\n")->encode('UTF-8')
      ->to_string);

# POST /malformed_utf8
my $level = app->log->level;
app->log->level('fatal');
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/malformed_utf8');
$tx->req->headers->content_type('application/x-www-form-urlencoded');
$tx->req->body('foo=%E1');
$client->queue(
    $tx => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojolicious (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojolicious (Perl)');
        is($tx->res->body,                            '%E1');
    }
)->process;
app->log->level($level);

# GET /json
$t->get_ok('/json')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_is('application/json')
  ->json_content_is({foo => [1, -2, 3, 'bar']});

# GET /autostash
$t->get_ok('/autostash?bar=23')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("layouted bar23\n");

# GET /helper
$t->get_ok('/helper')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
    '<br/>&lt;.../template(Mozilla/5.0 (compatible; Mojolicious; Perl))');

# GET /helper
$t->get_ok('/helper', {'User-Agent' => 'Explorer'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('<br/>&lt;.../template(Explorer)');

# GET /eperror
$level = app->log->level;
app->log->level('fatal');
$t->get_ok('/eperror')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Internal Server Error/);
app->log->level($level);

# GET /subrequest
$t->get_ok('/subrequest')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# GET /subrequest_simple
$t->get_ok('/subrequest_simple')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# GET /subrequest_sync
$t->get_ok('/subrequest_sync')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# GET /subrequest_async
$t->get_ok('/subrequest_async')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# GET /redirect_url
$t->get_ok('/redirect_url')->status_is(302)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is(Location => 'http://127.0.0.1/foo')->content_is('Redirecting!');

# GET /redirect_path
$t->get_ok('/redirect_path')->status_is(302)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is(Location       => '/foo/bar')->content_is('Redirecting!');

# GET /redirect_named
$t->get_ok('/redirect_named')->status_is(302)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is(Location       => '/template.txt')->content_is('Redirecting!');

# GET /redirect_named (with redirecting enabled in client)
$t->max_redirects(3);
$t->get_ok('/redirect_named')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is(Location       => undef)->content_is("Redirect works!\n");
$t->max_redirects(0);
Test::Mojo->new(tx => $t->redirects->[0])->status_is(302)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is(Location       => '/template.txt')->content_is('Redirecting!');

# GET /koi8-r
my $koi8 =
    'Этот человек наполняет меня надеждой.'
  . ' Ну, и некоторыми другими глубокими и приводящими в'
  . ' замешательство эмоциями.';
$t->get_ok('/koi8-r')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_is('text/html; charset=koi8-r')->content_like(qr/^$koi8/);

# GET /with_ladder
$t->get_ok('/with_ladder', {'X-Bender' => 'Rodriguez'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is('X-Ladder'     => 23)->content_is('Ladders are cool!');

# GET /with_ladder_too
$t->get_ok('/with_ladder_too', {'X-Bender' => 'Rodriguez'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is('X-Ladder'     => 23)->content_is('Ladders are cool too!');

# GET /with_ladder_too
$t->get_ok('/with_ladder_too')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Oops!/);

# GET /param_auth
$t->get_ok('/param_auth')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Not Bender!\n");

# GET /param_auth?name=Bender
$t->get_ok('/param_auth?name=Bender')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Bender!\n");

# GET /param_auth/too
$t->get_ok('/param_auth/too')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Not Bender!\n");

# GET /param_auth/too?name=Bender
$t->get_ok('/param_auth/too?name=Bender')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('You could be Bender too!');

# GET /hello.txt (static file)
$t->get_ok('/hello.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 30)
  ->content_is('Hello Mojo from a static file!');

# GET /hello.txt (partial static file)
$t->get_ok('/hello.txt', {'Range' => 'bytes=2-8'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 7)
  ->content_is('llo Moj');

# GET /hello.txt (partial static file, starting at first byte)
$t->get_ok('/hello.txt', {'Range' => 'bytes=0-8'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 9)
  ->content_is('Hello Moj');

# GET /hello.txt (partial static file, first byte)
$t->get_ok('/hello.txt', {'Range' => 'bytes=0-0'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 1)
  ->content_is('H');

# GET /hello3.txt (render_static and single byte file)
$t->get_ok('/hello3.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 1)
  ->content_is('X');

# GET /hello3.txt (render_static and partial single byte file)
$t->get_ok('/hello3.txt', {'Range' => 'bytes=0-0'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 1)
  ->content_is('X');

# GET /bridge2stash
$t->get_ok('/bridge2stash' => {'X-Flash' => 1})->status_is(200)
  ->content_is("stash too!!!!!!!!\n");

# GET /bridge2stash (with cookies, session and flash)
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is(
    "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!flash!/!\n"
  );

# GET /bridge2stash (with cookies and session but no flash)
$t->get_ok('/bridge2stash' => {'X-Flash2' => 1})->status_is(200)
  ->content_is(
    "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!!/!\n");

# GET /bridge2stash (with cookies and session cleared)
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is("stash too!cookie!signed_cookie!!bad_cookie--12345678!!!!\n");

__DATA__
@@ template.txt.epl
Redirect works!

@@ with_header_condition.html.epl
Test ok

@@ template_inheritance.html.ep
% layout 'template_inheritance';
%{ content header =>
<title>Welcome</title>
%}
%{ content sidebar =>
Sidebar!
%}
Hello World!

@@ layouts/template_inheritance.html.ep
% stash foo => 'Default';
%{= content header =>
Default header!
%}
%{= content sidebar =>
<%= stash 'foo' %> sidebar!
%}
%= content
%{= content footer =>
Default footer!
%}

@@ double_inheritance.html.ep
% extends 'template_inheritance';
%{ content sidebar =>
Sidebar too!
%}

@@ param_auth.html.epl
Bender!

@@ param_auth_denied.html.epl
Not Bender!

@@ root.html.epl
% my $self = shift;
%== $self->url_for('root_path')
%== $self->url_for('root_path')
%== $self->url_for('root_path')
%== $self->url_for('root_path')
%== $self->url_for('root_path')

@@ root_path.html.epl
%== shift->url_for('root');

@@ outerlayout.html.ep
Hello
<%= include 'outermenu' %>

@@ outermenu.html.ep
<%= dumper [1, 2] %>there<br/>!

@@ outerinnerlayout.html.ep
Hello
<%= include 'outermenu', layout => 'layout' %>

@@ not_found.html.epl
Oops!

@@ index.html.epl
Just works!\

@@ form.html.epl
<%= shift->param('name') %> Тихановский

@@ layouts/layout.html.epl
<%= shift->render_inner %> with layout

@@ autostash.html.ep
% $self->helper(layout => 'layout');
%= $foo
%= param 'bar'

@@ layouts/layout.html.ep
layouted <%== content %>

@@ helper.html.ep
%== '<br/>'
%= '<...'
%= url_for 'index'
(<%= agent %>)\

@@ eperror.html.ep
%= $c->foo('bar');

@@ bridge2stash.html.ep
% my $cookie = $self->req->cookie('mojolicious');
<%= stash('_name') %> too!<%= $self->cookie('foo') %>!\
<%= $self->signed_cookie('bar')%>!<%= $self->signed_cookie('bad')%>!\
<%= $self->cookie('bad') %>!<%= session 'foo' %>!\
<%= flash 'foo' %>!<%= $cookie->path if $cookie %>!
% $self->session(foo => 'session');
% $self->flash(foo => 'flash') if $self->req->headers->header('X-Flash');
% $self->stash->{session} = {} if $self->req->headers->header('X-Flash2');

__END__
This is not a template!
lalala
test
