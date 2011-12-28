use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More;
use Mojo::IOLoop::Server;
plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.37 required for this test!'
  unless Mojo::IOLoop::Server::TLS;
plan tests => 38;

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

my $t = Test::Mojo->new;

# Use HTTPS
$t->reset_session->test_server('https');

# GET /login
$t->get_ok('/login?name=sri')->status_is(200)->content_is('Welcome sri!');
ok $t->tx->res->cookie('mojolicious')->expires, 'session cookie expires';

# GET /again
$t->get_ok('/again')->status_is(200)->content_is('Welcome back sri!');

# GET /logout
$t->get_ok('/logout')->status_is(200)->content_is('Bye sri!');

# GET /again (expired session)
$t->get_ok('/again')->status_is(200)->content_is('Welcome back anonymous!');

# GET /logout (no session)
$t->get_ok('/logout')->status_is(200)->content_is('Bye anonymous!');

# Use HTTP
$t->reset_session->test_server('http');

# GET /login
$t->get_ok('/login?name=sri')->status_is(200)->content_is('Welcome sri!');

# GET /again
$t->get_ok('/again')->status_is(200)->content_is('Welcome back anonymous!');

# Use HTTPS again (without expiration)
$t->reset_session->test_server('https');
app->sessions->default_expiration(0);

# GET /login
$t->get_ok('/login?name=sri')->status_is(200)->content_is('Welcome sri!');
ok !$t->tx->res->cookie('mojolicious')->expires,
  'session cookie does not expire';

# GET /again
$t->get_ok('/again')->status_is(200)->content_is('Welcome back sri!');

# GET /logout
$t->get_ok('/logout')->status_is(200)->content_is('Bye sri!');

# GET /again (expired session)
$t->get_ok('/again')->status_is(200)->content_is('Welcome back anonymous!');

# GET /logout (no session)
$t->get_ok('/logout')->status_is(200)->content_is('Bye anonymous!');
