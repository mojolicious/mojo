use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

BEGIN {
  plan skip_all => 'set TEST_ASYNC_AWAIT to enable this test (developer only!)'
    unless $ENV{TEST_ASYNC_AWAIT} || $ENV{TEST_ALL};
  plan skip_all => 'Future::AsyncAwait X.XX+ required for this test!'
    unless Mojo::Base->ASYNC;
}
use Mojo::Base -async;

use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/one' => {text => 'works!'};

get '/two' => {text => 'also'};

get '/three' => async sub {
  my $c      = shift;
  my $first  = await Mojo::Promise->resolve('this ');
  my $second = await Mojo::Promise->resolve('works');
  my $third  = await Mojo::Promise->resolve(' too!');
  $c->render(text => "$first$second$third");
};

get '/four' => async sub {
  my $c = shift;

  my $text     = await Mojo::Promise->resolve('fail');
  my $rejected = Mojo::Promise->reject('this went perfectly');
  eval { await $rejected };
  if ($@) { $c->render(text => $@, status => 500) }
  else    { $c->render(text => $text) }
};

my $ua = Mojo::UserAgent->new;

async sub test_one {
  await $ua->get_p('/one');
}

async sub test_two {
  my $separator = shift;

  my $text = '';
  my $two  = await $ua->get_p('/two');
  $text .= $two->res->body;
  my $one = await $ua->get_p('/one');
  $text .= $separator . $one->res->body;

  return $text;
}

# Basic async/await
my $promise = test_one();
isa_ok $promise, 'Mojo::Promise', 'right class';
my $tx;
$promise->then(sub { $tx = shift })->catch(sub { warn @_ });
$promise->wait;
is $tx->res->body, 'works!', 'right content';

# Multiple awaits
my $text;
test_two(' ')->then(sub { $text = shift })->catch(sub { warn @_ })->wait;
is $text, 'also works!', 'right content';

# Application with async/await action
$tx = $ua->get('/three');
is $tx->res->body, 'this works too!', 'right content';

# Exception handling and async/await
$tx = $ua->get('/four');
is $tx->res->code, 500, 'right code';
like $tx->res->body, qr/this went perfectly/, 'right content';

done_testing();
