#!/usr/bin/env perl

# "You may have to "metaphorically" make a deal with the "devil".
#  And by "devil", I mean Robot Devil.
#  And by "metaphorically", I mean get your coat."
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
