#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll and kqueue
BEGIN { $ENV{MOJO_POLL} = 1 }

use Test::More tests => 6;

# This calls for a party, baby.
# I'm ordering 100 kegs, 100 hookers and 100 Elvis impersonators that aren't
# above a little hooking should the occasion arise.
use Mojolicious::Lite;
use Test::Mojo;

app->renderer->root(app->home->rel_dir('does_not_exist'));

# GET /dead_template
get '/dead_template' => '*';

get '/dead_action' => sub { die 'dead action!' };

my $t = Test::Mojo->new;

# GET /dead_template
$t->get_ok('/dead_template')->status_is(500)
  ->content_like(qr/1.*die.*dead\ template!/);

# GET /dead_action
$t->get_ok('/dead_action')->status_is(500)
  ->content_like(qr/22.*die.*dead\ action!/);

__DATA__
@@ dead_template.html.ep
% die 'dead template!';
