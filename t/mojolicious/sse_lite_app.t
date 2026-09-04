use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

get '/events' => sub {
  my $c = shift;
  $c->write_sse({text => 'One', id => 24});
  $c->write_sse({text => 'Two'});
  $c->finish;
};

post '/delayed' => sub {
  my $c = shift;
  $c->write_sse({type => 'test', text => 'One'});
  Mojo::IOLoop->timer(
    1 => sub {
      $c->write_sse(
        {type => 'test', text => 'Two'} => sub {
          my $c = shift;
          $c->finish;
        }
      );
    }
  );
};

get '/infinite' => sub {
  my $c = shift;
  $c->write_sse;
  my $id = Mojo::IOLoop->recurring(
    0.1 => sub {
      $c->write_sse({type => 'time', text => time});
    }
  );
  $c->tx->on(finish => sub { Mojo::IOLoop->remove($id) });
};

get '/redirect' => sub {
  my $c = shift;
  $c->redirect_to('/infinite');
};

my $t = Test::Mojo->new;
$t->ua->max_redirects(10);

subtest 'Basic SSE connection' => sub {
  $t->get_sse_ok('/events')->status_is(200)->content_type_is('text/event-stream')->sse_ok->sse_type_is('message')
    ->sse_text_is('One')
    ->sse_text_isnt('Two')
    ->sse_id_is(24)
    ->sse_id_isnt(25)
    ->sse_ok->sse_type_is('message')
    ->sse_type_isnt('foo')
    ->sse_text_is('Two')
    ->sse_finished_ok;
  $t->get_sse_ok('/events')->status_is(200)->sse_ok->sse_type_is('message')
    ->sse_text_is('One')
    ->sse_ok->sse_type_is('message')->sse_text_is('Two')->sse_finished_ok;
};

subtest 'Delayed events' => sub {
  $t->post_sse_ok('/delayed')->status_is(200)->sse_ok->sse_type_is('test')
    ->sse_text_is('One')
    ->sse_ok->sse_type_is('test')->sse_text_is('Two')->sse_finished_ok;
};

subtest 'Infinite stream of events' => sub {
  $t->get_sse_ok('/infinite')->status_is(200)->sse_ok->sse_type_is('time')
    ->sse_text_like(qr/\d+/)
    ->sse_text_unlike(qr/test/)
    ->sse_ok->sse_type_is('time')->sse_text_like(qr/\d+/)->sse_ok->sse_type_is('time')
    ->sse_text_like(qr/\d+/)
    ->sse_finish_ok;
};

subtest 'Early finish' => sub {
  $t->get_sse_ok('/events')->status_is(200)->sse_ok->sse_type_is('message')->sse_text_is('One')->sse_finish_ok;
};

subtest 'Follow redirect' => sub {
  $t->get_sse_ok('/redirect')->status_is(200)->sse_ok->sse_type_is('time')
    ->sse_text_like(qr/\d+/)
    ->sse_ok->sse_type_is('time')->sse_text_like(qr/\d+/)->sse_finish_ok;
};

done_testing();
