use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::Mojo;
use Test::More;

use Mojo::File qw(curfile);
use lib curfile->sibling('lib')->to_string;

use Mojo::Message::Response;
use Mojolicious::Lite;

# Internal redirect
hook around_dispatch => sub {
  my ($next, $c) = @_;
  $next->();
  if ($c->res->code && $c->res->code == 404) {
    $c->req->url->path($c->param('wrap') ? '/wrap/again' : '/');
    delete @{$c->stash}{keys %{$c->stash}};
    $c->tx->res(Mojo::Message::Response->new);
    $next->();
  }
};

# Wrap whole application
hook around_dispatch => sub {
  my ($next, $c) = @_;
  return $c->render(text => 'Wrapped again!') if $c->req->url->path->contains('/wrap/again');
  $next->();
};

# Wrap whole application again
hook around_dispatch => sub {
  my ($next, $c) = @_;
  return $c->render(text => 'Wrapped!') if $c->req->url->path->contains('/wrap');
  $next->();
};

# Custom dispatcher /hello.txt
hook before_dispatch => sub {
  my $c = shift;
  $c->render(text => 'Custom static file works!') if $c->req->url->path->contains('/hello.txt');
};

# Custom dispatcher /hello-delay.txt
hook before_dispatch => sub {
  my $c = shift;
  if ($c->req->url->path->contains('/hello-delay.txt')) {
    $c->render_later;
    Mojo::IOLoop->next_tick(sub {
      $c->render(text => 'Delayed!');
    });
  }
};

# Custom dispatcher /custom
hook before_dispatch => sub {
  my $c = shift;
  $c->render_maybe or $c->render(text => $c->param('a'), status => 205) if $c->req->url->path->contains('/custom');
};

# Custom dispatcher /custom_too
hook before_routes => sub {
  my $c = shift;
  $c->render(text => 'this works too') if $c->req->url->path->contains('/custom_too');
};

# Cleared response for /res.txt
hook before_routes => sub {
  my $c = shift;
  return unless $c->req->url->path->contains('/res.txt') && $c->param('route');
  $c->tx->res(Mojo::Message::Response->new);
};

# Set additional headers for static files
hook after_static => sub {
  my $c = shift;
  $c->res->headers->cache_control('max-age=3600, must-revalidate');
};

# Make controller available as $_
hook around_action => sub {
  my ($next, $c) = @_;
  local $_ = $c;
  return $next->();
};

# Plugin for rendering return values
plugin 'AroundPlugin';

# Pass argument to action
hook around_action => sub {
  my ($next, $c, $action) = @_;
  return $c->$action($c->current_route);
};

# Response generating condition "res" for /res.txt
app->routes->add_condition(
  res => sub {
    my ($route, $c) = @_;
    return 1 unless $c->param('res');
    $c->tx->res(Mojo::Message::Response->new(code => 201)->body('Conditional response!'));
    $c->rendered and return undef;
  }
);

# Never called if custom dispatchers work
get '/custom' => sub { shift->render(text => 'does not work') };

# Custom response
get '/res.txt' => (res => 1) => sub {
  $_->tx->res(Mojo::Message::Response->new(code => 202)->body('Custom response!'));
  $_->rendered;
};

# Allow rendering of return value
under '/' => {return => 1} => sub {1};

# Return and render argument
get '/' => sub { return pop } => 'works';

my $t = Test::Mojo->new;

subtest 'Normal route' => sub {
  $t->get_ok('/')->status_is(200)->header_isnt('Cache-Control' => 'max-age=3600, must-revalidate')->content_is('works');
};

subtest 'Normal static file' => sub {
  $t->get_ok('/test.txt')->status_is(200)->header_is('Cache-Control' => 'max-age=3600, must-revalidate')
    ->content_is("Normal static file!\n");
};

subtest 'Override static file' => sub {
  $t->get_ok('/hello.txt')->status_is(200)->content_is('Custom static file works!');
};

subtest 'render_later from before_dispatch' => sub {
  $t->get_ok('/hello-delay.txt')->status_is(200)->content_is('Delayed!');
};

subtest 'Custom dispatcher' => sub {
  $t->get_ok('/custom?a=works+too')->status_is(205)->content_is('works too');
};

subtest 'Static file' => sub {
  $t->get_ok('/res.txt')->status_is(200)->header_is('Cache-Control' => 'max-age=3600, must-revalidate')
    ->content_is("Static response!\n");
};

subtest ' Custom response' => sub {
  $t->get_ok('/res.txt?route=1')->status_is(202)->header_isnt('Cache-Control' => 'max-age=3600, must-revalidate')
    ->content_is('Custom response!');
};

subtest 'Conditional response' => sub {
  $t->get_ok('/res.txt?route=1&res=1')->status_is(201)->header_isnt('Cache-Control' => 'max-age=3600, must-revalidate')
    ->content_is('Conditional response!');
};

subtest 'Another custom dispatcher' => sub {
  $t->get_ok('/custom_too')->status_is(200)->header_isnt('Cache-Control' => 'max-age=3600, must-revalidate')
    ->content_is('this works too');
};

subtest 'First wrapper' => sub {
  $t->get_ok('/wrap')->status_is(200)->content_is('Wrapped!');
};

subtest 'Second wrapper' => sub {
  $t->get_ok('/wrap/again')->status_is(200)->content_is('Wrapped again!');
};

subtest 'Internal redirect to root' => sub {
  $t->get_ok('/not_found')->status_is(200)->content_is('works');
};

subtest 'Internal redirect to second wrapper' => sub {
  $t->get_ok('/not_found?wrap=1')->status_is(200)->content_is('Wrapped again!');
};

done_testing();

__DATA__
@@ res.txt
Static response!
@@ test.txt
Normal static file!
@@ hello-delay.txt
This is never rendered and overloaded by before_dispatch
