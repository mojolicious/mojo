use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::IOLoop::Server;
plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.37 required for this test!'
  unless Mojo::IOLoop::Server::TLS;
plan tests => 40;

# "Look at these low, low prices on famous brand-name electronics!
#  Don't be a sap, Dad. These are just crappy knockoffs.
#  Pfft. I know a genuine Panaphonics when I see it.
#  And look, there's a Magnetbox and Sorny."
use Mojo::IOLoop;
use Mojo::UserAgent;
use Mojolicious::Lite;
use Test::Mojo;

# Silence
app->log->level('fatal');

# Secure sessions
app->sessions->secure(1);

# GET /login
get '/login' => sub {
  my $self = shift;
  my $name = $self->param('name') || 'anonymous';
  $self->session(name => $name);
  $self->render_text("Welcome $name!");
};

# GET /again
get '/again' => sub {
  my $self = shift;
  my $name = $self->session('name') || 'anonymous';
  $self->render_text("Welcome back $name!");
};

# GET /logout
get '/logout' => sub {
  my $self = shift;
  $self->session(expires => 1);
  $self->redirect_to('login');
};

# Use HTTPS
my $t = Test::Mojo->new;
$t->ua->max_redirects(5);
$t->reset_session->ua->app_url('https');

# GET /login
$t->get_ok('/login?name=sri' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome sri!');
ok $t->tx->res->cookie('mojolicious')->expires, 'session cookie expires';
ok $t->tx->res->cookie('mojolicious')->secure,  'session cookie is secure';

# GET /again
$t->get_ok('/again' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome back sri!');

# GET /logout
$t->get_ok('/logout' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome anonymous!');

# GET /again (expired session)
$t->get_ok('/again' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome back anonymous!');

# GET /logout (no session)
$t->get_ok('/logout' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome anonymous!');

# Use HTTP
$t->reset_session->ua->app_url('http');

# GET /login
$t->reset_session->get_ok('/login?name=sri')->status_is(200)
  ->content_is('Welcome sri!');

# GET /again
$t->get_ok('/again')->status_is(200)->content_is('Welcome back anonymous!');

# Use HTTPS again (without expiration)
$t->reset_session->ua->app_url('https');
app->sessions->default_expiration(0);

# GET /login
$t->get_ok('/login?name=sri' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome sri!');
ok !$t->tx->res->cookie('mojolicious')->expires,
  'session cookie does not expire';
ok $t->tx->res->cookie('mojolicious')->secure, 'session cookie is secure';

# GET /again
$t->get_ok('/again' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome back sri!');

# GET /logout
$t->get_ok('/logout' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome anonymous!');

# GET /again (expired session)
$t->get_ok('/again' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome back anonymous!');

# GET /logout (no session)
$t->get_ok('/logout' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome anonymous!');
