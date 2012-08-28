#!/usr/bin/env perl

use Mojolicious::Lite;

# Default for config file tests
app->defaults(secret => 'Insecure too!');

# GET /
get '/' => sub {
  my $self = shift;
  $self->render_text(
    $self->render_partial('menubar') . app->defaults->{secret});
};

app->start;
__DATA__

@@ menubar.html.ep
%= stash('message') || 'works 4!'
