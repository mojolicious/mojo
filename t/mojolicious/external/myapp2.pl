#!/usr/bin/env perl

# "You may have to "metaphorically" make a deal with the "devil".
#  And by "devil", I mean Robot Devil.
#  And by "metaphorically", I mean get your coat."
use Mojolicious::Lite;

# Secret for config file tests
app->secret('Insecure too!');

# GET /
get '/' => sub {
  my $self = shift;
  $self->render_text($self->render_partial('menubar') . app->secret);
};

app->start;
__DATA__

@@ menubar.html.ep
%= stash('message') || 'works 4!'
