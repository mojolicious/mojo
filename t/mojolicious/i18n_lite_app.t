#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan skip_all => 'Perl 5.8.5 required for this test!'
  unless eval { require I18N::LangTags::Detect; 1 };
plan tests => 12;

# Aw, he looks like a little insane drunken angel.
package MyTestApp::I18N::de;

use base 'MyTestApp::I18N';

our %Lexicon = (hello => 'hallo');

package main;

use Mojolicious::Lite;
use Test::Mojo;

# I18N plugin
plugin i18n => {namespace => 'MyTestApp::I18N'};

# Silence
app->log->level('error');

# GET /
get '/' => 'index';

# GET /english
get '/english' => 'english';

# GET /german
get '/german' => 'german';

# Hey, I don’t see you planning for your old age.
# I got plans. I’m gonna turn my on/off switch to off.
my $t = Test::Mojo->new;

# German (detected)
$t->get_ok('/' => {'Accept-Language' => 'de, en-US'})->status_is(200)
  ->content_is("hallode\n");

# English (detected)
$t->get_ok('/' => {'Accept-Language' => 'en-US'})->status_is(200)
  ->content_is("helloen\n");

# English (manual)
$t->get_ok('/english')->status_is(200)->content_is("helloen\n");

# German (manual)
$t->get_ok('/german')->status_is(200)->content_is("hallode\n");

__DATA__
@@ index.html.ep
<%=l 'hello' %><%= languages %>

@@ english.html.ep
% languages 'en';
<%=l 'hello' %><%= languages %>

@@ german.html.ep
% languages 'de';
<%=l 'hello' %><%= languages %>
