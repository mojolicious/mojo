#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More tests => 24;

# Aw, he looks like a little insane drunken angel.
package MyTestApp::I18N::de;

use base 'MyTestApp::I18N';

our %Lexicon = (hello => 'hallo');

package main;

use Mojolicious::Lite;
use Test::Mojo;

# I18N plugin
plugin i18n => {namespace => 'MyTestApp::I18N'};

# GET /
get '/' => 'index';

# GET /english
get '/english' => 'english';

# GET /german
get '/german' => 'german';

# GET /mixed
get '/mixed' => 'mixed';

# GET /nothing
get '/nothing' => 'nothing';

# GET /unknown
get '/unknown' => 'unknown';

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
$t->get_ok('/english' => {'Accept-Language' => 'de'})->status_is(200)
  ->content_is("helloen\n");

# German (manual)
$t->get_ok('/german' => {'Accept-Language' => 'en-US'})->status_is(200)
  ->content_is("hallode\n");

# Mixed (manual)
$t->get_ok('/mixed' => {'Accept-Language' => 'de, en-US'})->status_is(200)
  ->content_is("hallode\nhelloen\n");

# Nothing
$t->get_ok('/nothing')->status_is(200)->content_is("helloen\n");

# Unknown (manual)
$t->get_ok('/unknown')->status_is(200)->content_is("unknownde\nunknownen\n");

# Unknwon (manual)
$t->get_ok('/unknown' => {'Accept-Language' => 'de, en-US'})->status_is(200)
  ->content_is("unknownde\nunknownen\n");

__DATA__
@@ index.html.ep
<%=l 'hello' %><%= languages %>

@@ english.html.ep
% languages 'en';
<%=l 'hello' %><%= languages %>

@@ german.html.ep
% languages 'de';
<%=l 'hello' %><%= languages %>

@@ mixed.html.ep
% languages 'de';
<%=l 'hello' %><%= languages %>
% languages 'en';
<%=l 'hello' %><%= languages %>

@@ nothing.html.ep
<%=l 'hello' %><%= languages %>

@@ unknown.html.ep
% languages 'de';
<%=l 'unknown' %><%= languages %>
% languages 'en';
<%=l 'unknown' %><%= languages %>
