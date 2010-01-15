#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 3;

use Mojolicious::Lite;
use Test::Mojo;
use FindBin;

# JSON configuration plugin
plugin json_config => {file => "$FindBin::Bin/json_config_lite_app.json"};

# Silence
app->log->level('error');

get '/' => 'index';

my $t = Test::Mojo->new;

$t->get_ok('/')->status_is(200)->content_like(qr/bar/);

__DATA__
@@ index.html.ep
<%= $config->{foo} %>
