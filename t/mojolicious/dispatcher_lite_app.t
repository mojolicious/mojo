use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

use FindBin;
use lib "$FindBin::Bin/lib";

use Mojo::Message::Response;
use Mojolicious::Lite;
use Test::Mojo;

# Internal redirect
hook around_dispatch => sub {
  my ($next, $c) = @_;
  $next->();
  if ($c->res->code == 404) {
    $c->req->url->path($c->param('wrap') ? '/wrap/again' : '/');
    delete @{$c->stash}{keys %{$c->stash}};
    $c->tx->res(Mojo::Message::Response->new);
    $next->();
  }
};

# Wrap whole application
hook around_dispatch => sub {
  my ($next, $c) = @_;
  return $c->render(text => 'Wrapped again!')
    if $c->req->url->path->contains('/wrap/again');
  $next->();
};

# Wrap whole application again
hook around_dispatch => sub {
  my ($next, $c) = @_;
  return $c->render(text => 'Wrapped!')
    if $c->req->url->path->contains('/wrap');
  $next->();
};

# Custom dispatcher /hello.txt
hook before_dispatch => sub {
  my $c = shift;
  $c->render(text => 'Custom static file works!')
    if $c->req->url->path->contains('/hello.txt');
};

# Custom dispatcher /custom
hook before_dispatch => sub {
  my $c = shift;
  $c->render_maybe
    or $c->render(text => $c->param('a'), status => 205)
    if $c->req->url->path->contains('/custom');
};

# Custom dispatcher /custom_too
hook before_routes => sub {
  my $c = shift;
  $c->render(text => 'this works too')
    if $c->req->url->path->contains('/custom_too');
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
    $c->tx->res(
      Mojo::Message::Response->new(code => 201)->body('Conditional response!')
    );
    $c->rendered and return undef;
  }
);

# Never called if custom dispatchers work
get '/custom' => sub { shift->render(text => 'does not work') };

# Custom response
get '/res.txt' => (res => 1) => sub {
  $_->tx->res(
    Mojo::Message::Response->new(code => 202)->body('Custom response!'));
  $_->rendered;
};

# Allow rendering of return value
under '/' => {return => 1} => sub {1};

# Return and render argument
get '/' => sub { return pop } => 'works';

my $t = Test::Mojo->new;

# Normal route
$t->get_ok('/')->status_is(200)
  ->header_isnt('Cache-Control' => 'max-age=3600, must-revalidate')
  ->content_is('works');

# Normal static file
$t->get_ok('/test.txt')->status_is(200)
  ->header_is('Cache-Control' => 'max-age=3600, must-revalidate')
  ->content_is("Normal static file!\n");

# Override static file
$t->get_ok('/hello.txt')->status_is(200)
  ->content_is('Custom static file works!');

# Custom dispatcher
$t->get_ok('/custom?a=works+too')->status_is(205)->content_is('works too');

# Static file
$t->get_ok('/res.txt')->status_is(200)
  ->header_is('Cache-Control' => 'max-age=3600, must-revalidate')
  ->content_is("Static response!\n");

# Custom response
$t->get_ok('/res.txt?route=1')->status_is(202)
  ->header_isnt('Cache-Control' => 'max-age=3600, must-revalidate')
  ->content_is('Custom response!');

# Conditional response
$t->get_ok('/res.txt?route=1&res=1')->status_is(201)
  ->header_isnt('Cache-Control' => 'max-age=3600, must-revalidate')
  ->content_is('Conditional response!');

# Another custom dispatcher
$t->get_ok('/custom_too')->status_is(200)
  ->header_isnt('Cache-Control' => 'max-age=3600, must-revalidate')
  ->content_is('this works too');

# First wrapper
$t->get_ok('/wrap')->status_is(200)->content_is('Wrapped!');

# Second wrapper
$t->get_ok('/wrap/again')->status_is(200)->content_is('Wrapped again!');

# Internal redirect to root
$t->get_ok('/not_found')->status_is(200)->content_is('works');

# Internal redirect to second wrapper
$t->get_ok('/not_found?wrap=1')->status_is(200)->content_is('Wrapped again!');

done_testing();

__DATA__
@@ res.txt
Static response!
@@ test.txt
Normal static file!
