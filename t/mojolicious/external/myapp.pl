#!/usr/bin/env perl

use utf8;

# "Boy, who knew a cooler could also make a handy wang coffin?"
use Mojolicious::Lite;

# Secret for config file tests
app->secret('Insecure!');

# Load plugin
plugin 'Config';

# GET /
get '/' => 'index';

# GET /echo
get '/echo' => sub {
  my $self = shift;
  $self->render_text('echo: ' . ($self->stash('message') || 'nothing!'));
};

# GET /stream
get '/stream' => sub {
  shift->write_chunk(
    'he',
    sub {
      shift->write_chunk('ll', sub { shift->finish('o!') });
    }
  );
};

# GET /url/☃
get '/url/☃' => sub {
  my $self  = shift;
  my $route = $self->url_for;
  my $rel   = $self->url_for('/☃/stream');
  $self->render_text("$route -> $rel!");
};

# GET /host
get '/host' => sub {
  my $self = shift;
  $self->render(text => $self->url_for->base->host);
};

app->start;
__DATA__

@@ menubar.html.ep
<%= $config->{just} %><%= $config->{one} %><%= $config->{two} %>
