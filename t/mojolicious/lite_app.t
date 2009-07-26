#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 48;

# Wait you're the only friend I have...
# You really want a robot for a friend?
# Yeah ever since I was six.
# Well, ok but I don't want people thinking we're robosexuals,
# so if anyone asks you're my debugger.
use Mojo::Client;
use Mojo::Transaction;
use Mojolicious::Lite;

# Something
sub something {'Just works!'}

# Silence
app->log->level('error');

# GET /foo
get '/foo' => sub {
    my $self = shift;
    $self->render(text => 'Yea baby!');
};

# POST /template
post '/template' => 'index';

# * /something
any '/something' => sub {
    my $self = shift;
    $self->render(text => something());
};

# GET|POST /something/else
any [qw/get post/] => '/something/else' => sub {
    my $self = shift;
    $self->render(text => 'Yay!');
};

# GET /regex/*
get '/regex/:test' => [test => qr/\d+/] => sub {
    my $self = shift;
    $self->render(text => $self->stash('test'));
};

# POST /bar/*
post '/bar/:test' => {test => 'default'} => sub {
    my $self = shift;
    $self->render(text => $self->stash('test'));
};

# Oh Fry, I love you more than the moon, and the stars,
# and the POETIC IMAGE NUMBER 137 NOT FOUND
my $client = Mojo::Client->new;

# GET /foo
my $tx = Mojo::Transaction->new_get('/foo');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Yea baby!');

# POST /template
$tx = Mojo::Transaction->new_post('/template');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Just works!');

# GET /something
$tx = Mojo::Transaction->new_get('/something');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Just works!');

# POST /something
$tx = Mojo::Transaction->new_post('/something');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Just works!');

# DELETE /something
$tx = Mojo::Transaction->new_delete('/something');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Just works!');

# GET /something/else
$tx = Mojo::Transaction->new_get('/something/else');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Yay!');

# POST /something/else
$tx = Mojo::Transaction->new_post('/something/else');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Yay!');

# DELETE /something/else
$tx = Mojo::Transaction->new_delete('/something/else');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            404);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/File Not Found/);

# GET /regex/23
$tx = Mojo::Transaction->new_get('/regex/23');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            '23');

# GET /regex/foo
$tx = Mojo::Transaction->new_get('/regex/foo');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            404);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
like($tx->res->body, qr/File Not Found/);

# POST /bar
$tx = Mojo::Transaction->new_post('/bar');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'default');

# GET /bar/baz
$tx = Mojo::Transaction->new_post('/bar/baz');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'baz');

__DATA__
@@ index.html.eplite
%= something()
