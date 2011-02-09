#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll and kqueue
BEGIN { $ENV{MOJO_POLL} = 1 }

# Development
my $backup;
BEGIN { $backup = $ENV{MOJO_MODE} || ''; $ENV{MOJO_MODE} = 'development' }

use Test::More tests => 16;

# "This calls for a party, baby.
#  I'm ordering 100 kegs, 100 hookers and 100 Elvis impersonators that aren't
#  above a little hooking should the occasion arise."
use Mojolicious::Lite;
use Test::Mojo;

app->renderer->root(app->home->rel_dir('does_not_exist'));

# GET /dead_template
get '/dead_template';

# GET /dead_included_template
get '/dead_included_template';

# GET /dead_action
get '/dead_action' => sub { die 'dead action!' };

# GET /double_dead_action
get '/double_dead_action' => sub {
  eval { die 'double dead action!' };
  die $@;
};

my $t = Test::Mojo->new;

# GET /dead_template
$t->get_ok('/dead_template')->status_is(500)->content_like(qr/1\./)
  ->content_like(qr/dead\ template!/);

# GET /dead_included_template
$t->get_ok('/dead_included_template')->status_is(500)->content_like(qr/1\./)
  ->content_like(qr/dead\ template!/);

# GET /dead_action
$t->get_ok('/dead_action')->status_is(500)->content_like(qr/26\./)
  ->content_like(qr/dead\ action!/);

# GET /double_dead_action
$t->get_ok('/double_dead_action')->status_is(500)->content_like(qr/30\./)
  ->content_like(qr/double\ dead\ action!/);

$ENV{MOJO_MODE} = $backup;

__DATA__
@@ dead_template.html.ep
% die 'dead template!';

@@ dead_included_template.html.ep
this
%= include 'dead_template'
works!
