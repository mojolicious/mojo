#
# Application demonstrating the various HTTP response variants for debugging
#
use Mojolicious::Lite;

get '/res1' => sub {
  my $c = shift;
  $c->render(data => 'Hello World!');
};

get '/res2' => sub {
  my $c = shift;
  $c->write('Hello ');
  $c->write('World!');
  $c->write('');
};

get '/res3' => sub {
  my $c = shift;
  $c->write_chunk('Hello ');
  $c->write_chunk('World!');
  $c->write_chunk('');
};

get '/res4' => sub {
  my $c = shift;
  $c->render(data => '', status => 204);
};

app->start;
