#!/usr/bin/env perl

use strict;
use warnings;

# "Boy, who knew a cooler could also make a handy wang coffin?"
use Mojolicious::Lite;

# Load plugin
plugin 'config';

# GET /
get '/' => 'index';

# GET /echo
get '/echo' => sub {
  my $self = shift;
  $self->render_text('echo: ' . ($self->stash('message') || 'nothing!'));
};

app->start;
__DATA__

@@ menubar.html.ep
<%= $config->{just} %>
