#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use utf8;

use Test::More tests => 89;

# Wait you're the only friend I have...
# You really want a robot for a friend?
# Yeah ever since I was six.
# Well, ok but I don't want people thinking we're robosexuals,
# so if anyone asks you're my debugger.
use Mojo::ByteStream 'b';
use Mojo::Client;
use Mojo::JSON;
use Mojo::Transaction::Single;
use Mojolicious::Lite;

# Silence
app->log->level('error');

# GET /foo
get '/foo' => sub {
    my $self = shift;
    $self->render_text('Yea baby!');
};

# GET /layout
get '/layout' => sub { shift->render_text('Yea baby!', layout => 'layout') };

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

# Oh Fry, I love you more than the moon, and the stars,
# and the POETIC IMAGE NUMBER 137 NOT FOUND
my $app    = Mojolicious::Lite->new;
my $client = Mojo::Client->new;

# GET /foo
my $tx = Mojo::Transaction::Single->new_get('/foo');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Yea baby!');

# POST /template
$tx = Mojo::Transaction::Single->new_post('/template');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Just works!');

# GET /something
$tx = Mojo::Transaction::Single->new_get('/something');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Just works!');

# POST /something
$tx = Mojo::Transaction::Single->new_post('/something');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Just works!');

# DELETE /something
$tx = Mojo::Transaction::Single->new_delete('/something');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Just works!');

# GET /something/else
$tx = Mojo::Transaction::Single->new_get('/something/else');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Yay!');

# POST /something/else
$tx = Mojo::Transaction::Single->new_post('/something/else');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Yay!');

# DELETE /something/else
$tx = Mojo::Transaction::Single->new_delete('/something/else');
$client->process_app($app, $tx);
is($tx->res->code,                            404);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/File Not Found/);

# GET /regex/23
$tx = Mojo::Transaction::Single->new_get('/regex/23');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            '23');

# GET /regex/foo
$tx = Mojo::Transaction::Single->new_get('/regex/foo');
$client->process_app($app, $tx);
is($tx->res->code,                            404);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/File Not Found/);

# POST /bar
$tx = Mojo::Transaction::Single->new_post('/bar');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'default');

# GET /bar/baz
$tx = Mojo::Transaction::Single->new_post('/bar/baz');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'baz');

# GET /layout
$tx = Mojo::Transaction::Single->new_get('/layout');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            "Yea baby! with layout\n");

# GET /firefox
$tx = Mojo::Transaction::Single->new_get('/firefox/bar',
    'User-Agent' => 'Firefox');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            '/firefox/foo');

# GET /firefox
$tx = Mojo::Transaction::Single->new_get('/firefox/bar',
    'User-Agent' => 'Explorer');
$client->process_app($app, $tx);
is($tx->res->code,                            404);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/File Not Found/);

# POST /utf8
$tx = Mojo::Transaction::Single->new_post('/utf8');
$tx->req->headers->content_type('application/x-www-form-urlencoded');
$tx->req->body('name=%D0%92%D1%8F%D1%87%D0%B5%D1%81%D0%BB%D0%B0%D0%B2');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->headers->content_type,           'text/html');
is($tx->res->headers->content_length,         40);
is($tx->res->body, b(<<EOF)->encode('utf8')->to_string);
Вячеслав Тихановский
EOF

# GET /json
$tx = Mojo::Transaction::Single->new_get('/json');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->headers->content_type,           'application/json');
my $hash = Mojo::JSON->new->decode($tx->res->body);
is($hash->{foo}->[0], 1);
is($hash->{foo}->[1], -2);
is($hash->{foo}->[2], 3);
is($hash->{foo}->[3], 'bar');

# GET /autostash
$tx = Mojo::Transaction::Single->new_get('/autostash');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            "layouted bar\n");

# GET /helper
$tx = Mojo::Transaction::Single->new_get('/helper');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,
    '<br/>&lt;.../template(Mozilla/5.0 (compatible; Mojo; Perl))');

# GET /helper
$tx =
  Mojo::Transaction::Single->new_get('/helper', 'User-Agent' => 'Explorer');
$client->process_app($app, $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body, '<br/>&lt;.../template(Explorer)');

# GET /eperror
my $level = $app->log->level;
$app->log->level('fatal');
$tx = Mojo::Transaction::Single->new_get('/eperror');
$client->process_app($app, $tx);
$app->log->level($level);
is($tx->res->code,                            500);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');

__DATA__
@@ index.html.epl
Just works!\

@@ form.html.epl
<%= shift->req->param('name') %> Тихановский

@@ layouts/layout.html.epl
<%= shift->render_inner %> with layout

@@ autostash.html.ep
% layout 'layout';
%= $foo

@@ layouts/layout.html.ep
layouted <%== content %>

@@ helper.html.ep
%== '<br/>'
%= '<...'
%= url_for 'index'
(<%= agent %>)\

@@ eperror.html.ep
%= $c->foo('bar');

__END__
This is not a template!
lalala
test
