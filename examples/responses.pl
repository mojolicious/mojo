#
# Application demonstrating the various HTTP response variants for debugging
#
use Mojolicious::Lite -signatures;

get '/res1' => sub ($c) {
  $c->render(data => 'Hello World!');
};

get '/res2' => sub ($c) {
  $c->write('Hello ');
  $c->write('World!');
  $c->write('');
};

get '/res3' => sub ($c) {
  $c->write_chunk('Hello ');
  $c->write_chunk('World!');
  $c->write_chunk('');
};

get '/res4' => sub ($c) {
  $c->render(data => '', status => 204);
};

app->start;
