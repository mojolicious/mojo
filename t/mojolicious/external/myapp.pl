#!/usr/bin/env perl

use utf8;

use Mojolicious::Lite;

# Default for config file tests
app->defaults(secret => 'Insecure!');

# Load plugin
plugin 'Config';

# Message condition
app->routes->add_condition(
  message => sub {
    my ($route, $c, $captures, $msg) = @_;
    $c->res->headers->header('X-Message' => $msg);
    return 1;
  }
);

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
    'he' => sub {
      shift->write_chunk('ll' => sub { shift->finish('o!') });
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
get '/host' => (message => 'it works!') => sub {
  my $self = shift;
  $self->render(text => $self->url_for->base->host);
};

# GET /one
get '/one' => sub { shift->render_text('One') };

# GET /one/two
get '/one/two' => {text => 'Two'};

app->start;
__DATA__

@@ menubar.html.ep
<%= $config->{just} %><%= $config->{one} %><%= $config->{two} %>
