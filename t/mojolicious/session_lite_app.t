use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 40;

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
  my $name = $self->param('name');
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
  my $name = $self->session('name') || 'anonymous';
  $self->session(expires => 1);
  $self->render_text("Bye $name!");
};

# Emulate HTTPS
{
  my $t = Test::Mojo->new;
  local $ENV{MOJO_REVERSE_PROXY} = 1;

  # GET /login (HTTPS)
  $t->get_ok('/login?name=sri' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
    ->content_is('Welcome sri!');
  ok $t->tx->res->cookie('mojolicious')->expires, 'session cookie expires';
  ok $t->tx->res->cookie('mojolicious')->secure,  'session cookie is secure';

  # GET /again (HTTPS)
  $t->get_ok('/again' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
    ->content_is('Welcome back sri!');

  # GET /logout (HTTPS)
  $t->get_ok('/logout' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
    ->content_is('Bye sri!');

  # GET /again (HTTPS, expired session)
  $t->get_ok('/again' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
    ->content_is('Welcome back anonymous!');

  # GET /logout (HTTPS, no session)
  $t->get_ok('/logout' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
    ->content_is('Bye anonymous!');

  # Use HTTP
  $t->reset_session;

  # GET /login (HTTP)
  $t->reset_session->get_ok('/login?name=sri')->status_is(200)
    ->content_is('Welcome sri!');

  # GET /again (HTTP)
  $t->get_ok('/again')->status_is(200)->content_is('Welcome back anonymous!');

  # Use HTTPS again (without expiration)
  $t->reset_session;
  app->sessions->default_expiration(0);

  # GET /login (HTTPS)
  $t->get_ok('/login?name=sri' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
    ->content_is('Welcome sri!');
  ok !$t->tx->res->cookie('mojolicious')->expires,
    'session cookie does not expire';
  ok $t->tx->res->cookie('mojolicious')->secure, 'session cookie is secure';

  # GET /again (HTTPS)
  $t->get_ok('/again' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
    ->content_is('Welcome back sri!');

  # GET /logout (HTTPS)
  $t->get_ok('/logout' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
    ->content_is('Bye sri!');

  # GET /again (HTTPS, expired session)
  $t->get_ok('/again' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
    ->content_is('Welcome back anonymous!');

  # GET /logout (HTTPS, no session)
  $t->get_ok('/logout' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
    ->content_is('Bye anonymous!');
}
