#!/usr/bin/env perl

use Mojolicious::Lite;

# Default for config file tests
app->defaults(secret => 'Insecure!');

# Helpers sharing the same name in different embedded applications
helper same_name => sub {'myapp'};

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

get '/' => 'index';

get '/echo' => sub {
  my $c = shift;
  $c->render(text => 'echo: ' . ($c->stash('message') || 'nothing!'));
};

get '/stream' => sub {
  shift->write_chunk(
    'he' => sub {
      shift->write_chunk('ll' => sub { shift->finish('o!') });
    }
  );
};

get '/url/☃' => sub {
  my $c     = shift;
  my $route = $c->url_for({format => 'json'});
  my $rel   = $c->url_for('/☃/stream');
  $c->render(text => "$route -> $rel!");
};

get '/host' => (message => 'it works!') => sub {
  my $c = shift;
  $c->render(text => $c->url_for->base->host);
};

get '/one' => sub { shift->render(text => 'One') };

get '/one/two' => {text => 'Two'};

get '/template/:template';

websocket '/url_for' => sub {
  my $c = shift;
  $c->on(
    message => sub {
      my ($c, $msg) = @_;
      $c->send($c->url_for($msg)->to_abs);
    }
  );
} => 'ws_test';

app->start;
__DATA__

@@ menubar.html.ep
%= same_name
<%= $config->{just} %><%= $config->{one} %><%= $config->{two} %>
