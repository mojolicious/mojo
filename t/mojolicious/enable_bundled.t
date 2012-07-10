#!/usr/bin/env perl
use Mojo::Base -strict;
use Test::More tests => 4;
use Test::Mojo;
use Mojolicious::Lite;

my $t = Test::Mojo->new();

# default
$t->get_ok('/favicon.ico')->status_is(200);

# disable it
app->static->enable_bundled(0);
$t->get_ok('/favicon.ico')->status_is(404);
