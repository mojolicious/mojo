#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan tests => 7;

# Oh, I always feared he might run off like this.
# Why, why, why didn't I break his legs?
use FindBin;
use Mojolicious::Lite;
use Test::Mojo;

# Silence
app->log->level('error');

# Load plugin
my $config =
  plugin json_config => {default => {foo => 'baz', hello => 'there'}};
is($config->{foo},   'bar');
is($config->{hello}, 'there');

# GET /
get '/' => 'index';

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_like(qr/bar/);

# No file, default only
$config =
  plugin json_config => {file => 'nonexisted', default => {foo => 'qux'}};
is($config->{foo}, 'qux');

# No file, no default
ok(not eval { plugin json_config => {file => 'nonexisted'}; });

__DATA__
@@ index.html.ep
<%= $config->{foo} %>
