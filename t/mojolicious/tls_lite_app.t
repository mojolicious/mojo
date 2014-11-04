use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::Server;

plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.84 required for this test!'
  unless Mojo::IOLoop::Server::TLS;

use Mojo::IOLoop;
use Mojo::UserAgent;
use Mojolicious::Lite;
use Test::Mojo;

# Silence
app->log->level('fatal');

# Secure sessions
app->sessions->secure(1);

get '/login' => sub {
  my $c = shift;
  my $name = $c->param('name') || 'anonymous';
  $c->session(name => $name);
  $c->render(text => "Welcome $name!");
};

get '/again' => sub {
  my $c = shift;
  my $name = $c->session('name') || 'anonymous';
  $c->render(text => "Welcome back $name!");
};

get '/logout' => sub {
  my $c = shift;
  $c->session(expires => 1);
  $c->redirect_to('login');
};

# Use HTTPS
my $t = Test::Mojo->new;
$t->ua->max_redirects(5);
$t->reset_session->ua->server->url('https');

# Login
$t->get_ok('/login?name=sri' => {'X-Forwarded-Proto' => 'https'})
  ->status_is(200)->content_is('Welcome sri!');
ok $t->tx->res->cookie('mojolicious')->expires, 'session cookie expires';
ok $t->tx->res->cookie('mojolicious')->secure,  'session cookie is secure';

# Return
$t->get_ok('/again' => {'X-Forwarded-Proto' => 'https'})->status_is(200)
  ->content_is('Welcome back sri!');

# Logout
$t->get_ok('/logout' => {'X-Forwarded-Proto' => 'https'})->status_is(200)
  ->content_is('Welcome anonymous!');

# Expired session
$t->get_ok('/again' => {'X-Forwarded-Proto' => 'https'})->status_is(200)
  ->content_is('Welcome back anonymous!');

# No session
$t->get_ok('/logout' => {'X-Forwarded-Proto' => 'https'})->status_is(200)
  ->content_is('Welcome anonymous!');

# Use HTTP
$t->reset_session->ua->server->url('http');

# Login again
$t->reset_session->get_ok('/login?name=sri')->status_is(200)
  ->content_is('Welcome sri!');

# Return
$t->get_ok('/again')->status_is(200)->content_is('Welcome back anonymous!');

# Use HTTPS again (without expiration)
$t->reset_session->ua->server->url('https');
app->sessions->default_expiration(0);

# Login again
$t->get_ok('/login?name=sri' => {'X-Forwarded-Proto' => 'https'})
  ->status_is(200)->content_is('Welcome sri!');
ok !$t->tx->res->cookie('mojolicious')->expires,
  'session cookie does not expire';
ok $t->tx->res->cookie('mojolicious')->secure, 'session cookie is secure';

# Return
$t->get_ok('/again' => {'X-Forwarded-Proto' => 'https'})->status_is(200)
  ->content_is('Welcome back sri!');

# Logout
$t->get_ok('/logout' => {'X-Forwarded-Proto' => 'https'})->status_is(200)
  ->content_is('Welcome anonymous!');

# Expired session
$t->get_ok('/again' => {'X-Forwarded-Proto' => 'https'})->status_is(200)
  ->content_is('Welcome back anonymous!');

# No session
$t->get_ok('/logout' => {'X-Forwarded-Proto' => 'https'})->status_is(200)
  ->content_is('Welcome anonymous!');

done_testing();
