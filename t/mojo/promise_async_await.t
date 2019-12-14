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

use Mojo::Promise;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

helper defer_resolve_p => sub {
  my ($c, $msg) = @_;
  my $promise = Mojo::Promise->new;
  Mojo::IOLoop->next_tick(sub { $promise->resolve($msg) });
  return $promise;
};

helper defer_reject_p => sub {
  my ($c, $msg) = @_;
  my $promise = Mojo::Promise->new;
  Mojo::IOLoop->next_tick(sub { $promise->reject($msg) });
  return $promise;
};

get '/one' => {text => 'works!'};

get '/two' => {text => 'also'};

get '/three' => async sub {
  my $c      = shift;
  my $first  = await $c->defer_resolve_p('this ');
  my $second = await $c->defer_resolve_p('works');
  my $third  = await $c->defer_resolve_p(' too!');
  $c->render(text => "$first$second$third");
};

get '/four' => async sub {
  my $c = shift;

  my $text = await Mojo::Promise->resolve('fail');
  eval { await $c->defer_reject_p('this went perfectly') };
  if   (my $err = $@) { $c->render(text => $err, status => 500) }
  else                { $c->render(text => $text) }
};

get '/five' => async sub {
  my $c       = shift;
  my $runaway = $c->defer_reject_p('runaway too');
  await $c->defer_resolve_p('fail');
  await $runaway;
};

my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);

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
is $tx->res->code,   500,                     'right code';
like $tx->res->body, qr/this went perfectly/, 'right content';

# Runaway exception
$tx = $ua->get('/five');
is $tx->res->code,   500,             'right code';
like $tx->res->body, qr/runaway too/, 'right content';

done_testing();
