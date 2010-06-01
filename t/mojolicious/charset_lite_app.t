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
plan tests => 34;

# In the game of chess you can never let your adversary see your pieces.
use Mojo::ByteStream 'b';
use Mojolicious::Lite;
use Test::Mojo;

my $yatta      = 'やった';
my $yatta_sjis = b($yatta)->encode('shift_jis')->to_string;

# Charset plugin
plugin charset => {charset => 'Shift_JIS'};

# Silence
app->log->level('error');

# GET /
get '/' => 'index';

# POST /
post '/' => sub {
    my $self = shift;
    $self->render_text("foo: " . $self->param('foo'));
};

# POST /data
post '/data' => sub {
    my $self = shift;
    $self->render_data($self->req->body, format => 'bin');
};

# GET /json
get '/json' => sub { shift->render_json({test => $yatta}) };

# GET /привет/мир
get '/привет/мир' => sub { shift->render_json({foo => $yatta}) };

my $t = Test::Mojo->new;

# Plain old ASCII
$t->post_form_ok('/', {foo => 'yatta'})->status_is(200)
  ->content_is('foo: yatta');

# Send raw Shift_JIS octets (like browsers do)
$t->post_form_ok('/', '', {foo => $yatta_sjis})->status_is(200)
  ->content_type_like(qr/Shift_JIS/)->content_like(qr/$yatta/);

# Send raw Shift_JIS octets (like browsers do, multipart message)
$t->post_form_ok(
    '/', '',
    {foo            => $yatta_sjis},
    {'Content-Type' => 'multipart/form-data'}
  )->status_is(200)->content_type_like(qr/Shift_JIS/)
  ->content_like(qr/$yatta/);

# Send as string
$t->post_form_ok('/', 'shift_jis', {foo => $yatta})->status_is(200)
  ->content_type_like(qr/Shift_JIS/)->content_like(qr/$yatta/);

# Send as string (multipart message)
$t->post_form_ok(
    '/', 'shift_jis',
    {foo            => $yatta},
    {'Content-Type' => 'multipart/form-data'}
  )->status_is(200)->content_type_like(qr/Shift_JIS/)
  ->content_like(qr/$yatta/);

# Templates in the DATA section should be written in UTF-8,
# and those in separate files in Shift_JIS (Mojo will do the decoding)
$t->get_ok('/')->status_is(200)->content_type_like(qr/Shift_JIS/)
  ->content_like(qr/$yatta/);

# Send and receive raw Shift_JIS octets (like browsers do)
$t->post_ok('/data', $yatta_sjis)->status_is(200)->content_is($yatta_sjis);

# JSON data
$t->get_ok('/json')->status_is(200)->content_type_is('application/json')
  ->json_content_is({test => $yatta});

# IRI
$t->get_ok('/привет/мир')->status_is(200)
  ->content_type_is('application/json')->json_content_is({foo => $yatta});

__DATA__
@@ index.html.ep
<p>やった</p>
