#!/usr/bin/env perl

use Mojolicious::Lite;
use Mojo::IOLoop;

# Default for config file tests
app->defaults(secret => 'Insecure too!');

# Delay dispatching
hook around_dispatch => sub {
  my ($next, $c) = @_;
  Mojo::IOLoop->timer(0 => sub { $next->() });
};

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
