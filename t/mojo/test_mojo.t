use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use Mojolicious::Lite;


get '/csrf_token' => sub {
  my $c = shift;
  $c->render(text => $c->csrf_token);
};


post '/session' => sub {
  my $c = shift;
  $c->session('foo' => $c->param('foo'));
  $c->render(text => 'ok');
};

get '/session' => sub {
  my $c = shift;
  $c->render(text => $c->session('foo'));
};

post '/private' => sub {
  my $c = shift;

  return $c->render(text => 'access denied', status => 401)
    unless $c->session('user') // '' eq 'Cartman';

  return $c->render(text => 'bad csrf token', status => 403)
    if $c->validation->csrf_protect->has_error;

  $c->render(text => 'Cartman ok');
};

my $t = Test::Mojo->new;

# Session
is $t->session('foo' => 'bar')->session('foo'), 'bar';
$t->get_ok('/session')->content_is('bar');
is $t->post_ok('/session' => form => {foo => 'Bender'})->session('foo'),
  'Bender';

# csrf_token
$t->get_ok('/csrf_token')->content_is($t->csrf_token);

# real world test
$t->post_ok('/private')->status_is('401');
$t->session(user => 'Cartman')->post_ok('/private')->status_is('403');
$t->post_ok('/private?csrf_token=' . $t->csrf_token)->status_is('200');

done_testing;
