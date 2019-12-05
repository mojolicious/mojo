use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ASYNC_AWAIT to enable this test (developer only!)'
  unless $ENV{TEST_ASYNC_AWAIT} || $ENV{TEST_ALL};
plan skip_all => 'Future::AsyncAwait X.XX required for this test!'
  unless eval { require Future::AsyncAwait };

use Future::AsyncAwait future_class => 'Mojo::Promise';
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/one' => {text => 'works!'};

get '/two' => {text => 'also'};

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

done_testing();
