#!/usr/bin/env perl

use strict;
use warnings;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 81;

# "Woohoo, time to go clubbin'! Baby seals here I come!"
use Mojolicious::Lite;
use Test::Mojo;

# GET /rest
get '/rest' => sub {
  my $self = shift;
  $self->respond_to(
    json => sub { $self->render_json({just => 'works'}) },
    html => sub { $self->render_data('<html><body>works') },
    xml  => sub { $self->render_data('<just>works</just>') }
  ) or $self->rendered(204);
};

# "Raise the solar sails! I'm going after that Mobius Dick!"
my $t = Test::Mojo->new;

# GET /rest
$t->get_ok('/rest')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# GET /rest (html format)
$t->get_ok('/rest.html')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# GET /rest (accept html)
$t->get_ok('/rest', {Accept => 'text/html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# GET /rest (accept html again)
$t->get_ok('/rest', {Accept => 'Text/Html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# GET /rest (accept html with format)
$t->get_ok('/rest.html', {Accept => 'text/html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# GET /rest (accept html with wrong format)
$t->get_ok('/rest.json', {Accept => 'text/html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# GET /rest (accept html with quality)
$t->get_ok('/rest', {Accept => 'text/html;q=9'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# GET /rest (json format)
$t->get_ok('/rest.json')->status_is(200)->content_type_is('application/json')
  ->json_content_is({just => 'works'});

# GET /rest (accept json)
$t->get_ok('/rest', {Accept => 'application/json'})->status_is(200)
  ->content_type_is('application/json')->json_content_is({just => 'works'});

# GET /rest (accept json again)
$t->get_ok('/rest', {Accept => 'APPLICATION/JSON'})->status_is(200)
  ->content_type_is('application/json')->json_content_is({just => 'works'});

# GET /rest (accept json with format)
$t->get_ok('/rest.json', {Accept => 'application/json'})->status_is(200)
  ->content_type_is('application/json')->json_content_is({just => 'works'});

# GET /rest (accept json with wrong format)
$t->get_ok('/rest.png', {Accept => 'application/json'})->status_is(200)
  ->content_type_is('application/json')->json_content_is({just => 'works'});

# GET /rest (accept json with quality)
$t->get_ok('/rest', {Accept => 'application/json;q=9'})->status_is(200)
  ->content_type_is('application/json')->json_content_is({just => 'works'});

# GET /rest (xml format)
$t->get_ok('/rest.xml')->status_is(200)->content_type_is('text/xml')
  ->text_is(just => 'works');

# GET /rest (accept xml)
$t->get_ok('/rest', {Accept => 'text/xml'})->status_is(200)
  ->content_type_is('text/xml')->text_is(just => 'works');

# GET /rest (accept xml again)
$t->get_ok('/rest', {Accept => 'TEXT/XML'})->status_is(200)
  ->content_type_is('text/xml')->text_is(just => 'works');

# GET /rest (accept xml with format)
$t->get_ok('/rest.xml', {Accept => 'text/xml'})->status_is(200)
  ->content_type_is('text/xml')->text_is(just => 'works');

# GET /rest (accept xml with wrong format)
$t->get_ok('/rest.txt', {Accept => 'text/xml'})->status_is(200)
  ->content_type_is('text/xml')->text_is(just => 'works');

# GET /rest (accept xml with quality)
$t->get_ok('/rest', {Accept => 'text/xml;q=9'})->status_is(200)
  ->content_type_is('text/xml')->text_is(just => 'works');

# GET /rest (unsupported)
$t->get_ok('/rest', {Accept => 'image/png'})->status_is(204)->content_is('');

# GET /nothing (does not exist)
$t->get_ok('/nothing', {Accept => 'image/png'})->status_is(404);
