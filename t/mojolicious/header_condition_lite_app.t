#!/usr/bin/env perl

# Copyright (C) 2010, David Davis, http://xant.us/

use strict;
use warnings;

use Test::More tests => 12;

use Mojolicious::Lite;
use Test::Mojo;

# Header condition plugin
plugin 'header_condition';

app->log->level('error');

get '/' => ( headers => { 'X-Secret-Header' => 'bar' } ) => 'index';

post '/' => ( headers => { 'X-Secret-Header' => 'bar' } ) => sub {
    my $self = shift;
    $self->render_text('foo '.$self->req->headers->header('X-Secret-Header'));
};

my $t = Test::Mojo->new;

$t->post_ok('/', { 'X-Secret-Header' => 'bar' }, 'bar')->status_is(200)->content_is('foo bar');
$t->post_ok('/', {}, 'bar')->status_is(404)->content_like(qr/Not Found/);

$t->get_ok('/', { 'X-Secret-Header' => 'bar' } )->status_is(200)->content_like(qr/^Test ok/);
$t->get_ok('/')->status_is(404)->content_like(qr/Not Found/);

__DATA__
@@ not_found.html.ep
Not Found
@@ index.html.ep
Test ok
