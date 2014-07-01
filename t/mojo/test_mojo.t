use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

# Custom secret
app->secrets(['very secr3t!']);

get '/csrf_token' => sub {
  my $c = shift;
  $c->render(text => $c->csrf_token);
};

post '/session' => sub {
  my $c = shift;
  $c->session('foo' => 'Bender');
  $c->render(text => 'ok');
};

get '/session' => sub {
  my $c = shift;
  $c->render(text => $c->session('foo'));
};

get '/private' => sub {
  my $c = shift;

  return $c->render(text => 'access denied', status => 401)
    unless $c->session('user') // '' eq 'Cartman';

  return $c->render(text => 'bad csrf token', status => 403)
    if $c->validation->csrf_protect->has_error;

  $c->render(text => 'Cartman ok');
};

my $t = Test::Mojo->new;

# Session
is $t->session('foo' => 'bar')->session('foo'), 'bar', 'Right session value';
$t->get_ok('/session')
  ->content_is('bar', 'Right session available in controller');
is $t->post_ok('/session')->session('foo'), 'Bender',
  'Session is changed right way by application';

# csrf_token
$t->get_ok('/csrf_token')->content_is($t->csrf_token);

# missing session
$t->get_ok('/private')
  ->status_is('401', 'Right status 401 (authorization needed)');

# session is ok, but csrf_token is missing
$t->session(user => 'Cartman')->get_ok('/private')
  ->status_is('403', 'Right status 403 (missing csrf_token)');

# all fine
$t->get_ok('/private?csrf_token=' . $t->csrf_token)
  ->status_is('200', 'Right status');

done_testing;
