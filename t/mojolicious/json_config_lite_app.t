#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 5;

# Oh, I always feared he might run off like this.
# Why, why, why didn't I break his legs?
use FindBin;
use Mojolicious::Lite;
use Test::Mojo;

# Load plugin
my $config =
  plugin json_config => {default => {foo => 'baz', hello => 'there'}};
is($config->{foo},   'bar');
is($config->{hello}, 'there');

# Silence
app->log->level('error');

# GET /
get '/' => 'index';

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_like(qr/bar/);

__DATA__
@@ index.html.ep
<%= $config->{foo} %>
