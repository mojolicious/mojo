use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop;
use Mojolicious::Lite;
use Test::Mojo;

package MyTestApp::Controller;
use Mojo::Base 'Mojolicious::Controller';

sub DESTROY { shift->stash->{destroyed} = 1 }

package main;

app->controller_class('MyTestApp::Controller');

get '/write' => sub {
  my $c = shift;
  $c->res->headers->connection('close');
  $c->on(finish => sub { shift->stash->{finished}++ });
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->finish('this was short.');
};

get '/write/length' => sub {
  my $c = shift;
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->res->headers->content_length(25);
  $c->write('this was short and plain.');
};

get '/write/nolength' => sub {
  my $c = shift;
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->write('this was short and had no length.');
  $c->write('');
};

get '/longpoll/chunked' => sub {
  my $c = shift;
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->write_chunk('hi ');
  my $id = Mojo::IOLoop->timer(
    0.25 => sub {
      $c->write_chunk(
        'there,' => sub {
          shift->write_chunk(' whats up?' => sub { shift->finish });
        }
      );
    }
  );
  $c->on(
    finish => sub {
      shift->stash->{finished}++;
      Mojo::IOLoop->remove($id);
    }
  );
};

get '/longpoll/length' => sub {
  my $c = shift;
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->res->headers->content_length(25);
  $c->write('hi ');
  Mojo::IOLoop->timer(
    0.25 => sub {
      $c->on(finish => sub { shift->stash->{finished}++ });
      $c->write(
        'there plain,' => sub {
          shift->write(' whats up?' => sub { shift->stash->{drain}++ });
        }
      );
    }
  );
};

get '/longpoll/nolength' => sub {
  my $c = shift;
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->write('hi ');
  Mojo::IOLoop->timer(
    0.25 => sub {
      $c->write(
        'there,' => sub {
          shift->write(' what length?' => sub { $c->finish });
        }
      );
    }
  );
};

get '/longpoll/order' => sub {
  my $c = shift;
  $c->write_chunk(
    'First, ' => sub {
      my $c = shift;
      $c->stash->{order} -= 1;
      $c->write_chunk('second, ' => sub { shift->finish('third!') });
    }
  );
  $c->stash->{order} = 2;
};

get '/longpoll/static' => sub {
  my $c = shift;
  $c->cookie(bar => 'baz');
  $c->session(foo => 'bar');
  Mojo::IOLoop->timer(0.25 => sub { $c->reply->static('hello.txt') });
};

get '/longpoll/dynamic' => sub {
  my $c = shift;
  Mojo::IOLoop->timer(
    0.25 => sub {
      $c->res->code(201);
      $c->cookie(baz => 'yada');
      $c->res->body('Dynamic!');
      $c->rendered;
    }
  );
};

get '/stream' => sub {
  my $c = shift;
  my $i = 0;
  my $drain;
  $drain = sub {
    my $c = shift;
    return $c->finish if $i >= 10;
    $c->write_chunk($i++, $drain);
    $c->stash->{subscribers}
      += @{Mojo::IOLoop->stream($c->tx->connection)->subscribers('drain')};
  };
  $c->$drain;
};

get '/render' => sub {
  my $c      = shift;
  my $stream = Mojo::IOLoop->stream($c->tx->connection);
  $c->on(finish => sub { shift->stash->{writing} = $stream->is_writing });
  $c->render_later;
  Mojo::IOLoop->next_tick(sub { $c->render(msg => 'Finish!') });
};

get '/too_long' => sub {
  my $c = shift;
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->res->headers->content_length(17);
  $c->write('Waiting forever!');
};

my $steps;
helper steps => sub {
  my $c = shift;
  $c->delay(
    sub { Mojo::IOLoop->next_tick(shift->begin) },
    sub {
      Mojo::IOLoop->next_tick(shift->begin);
      $c->param('die') ? die 'intentional' : $c->render(text => 'second');
      $c->res->headers->header('X-Next' => 'third');
    },
    sub { $steps = $c->res->headers->header('X-Next') }
  );
};

get '/steps' => sub { shift->steps };

my $t = Test::Mojo->new;

# Stream without delay and finish
my $log = '';
my $cb = $t->app->log->on(message => sub { $log .= pop });
my $stash;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/write')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_type_is('text/plain')->content_is('this was short.');
Mojo::IOLoop->one_tick until $stash->{finished};
ok !$t->tx->kept_alive, 'connection was not kept alive';
ok !$t->tx->keep_alive, 'connection will not be kept alive';
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';
unlike $log, qr/Nothing has been rendered, expecting delayed response/,
  'right message';
$t->app->log->unsubscribe(message => $cb);

# Stream without delay and content length
$t->get_ok('/write/length')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('this was short and plain.');
ok !$t->tx->kept_alive, 'connection was not kept alive';
ok $t->tx->keep_alive, 'connection will be kept alive';

# Stream without delay and empty write
$t->get_ok('/write/nolength')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => undef)->content_type_is('text/plain')
  ->content_is('this was short and had no length.');
ok $t->tx->kept_alive, 'connection was kept alive';
ok !$t->tx->keep_alive, 'connection will not be kept alive';

# Chunked response with delay
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/longpoll/chunked')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('hi there, whats up?');
Mojo::IOLoop->one_tick until $stash->{finished};
ok !$t->tx->kept_alive, 'connection was not kept alive';
ok $t->tx->keep_alive, 'connection will be kept alive';
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';

# Interrupted by closing the connection
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
my $port = $t->ua->server->url->port;
Mojo::IOLoop->client(
  {port => $port} => sub {
    my ($loop, $err, $stream) = @_;
    $stream->on(read => sub { shift->close });
    $stream->write("GET /longpoll/chunked HTTP/1.1\x0d\x0a\x0d\x0a");
  }
);
Mojo::IOLoop->one_tick until $stash->{finished};
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';

# Interrupted by raising an error
my $tx = $t->ua->build_tx(GET => '/longpoll/chunked');
my $buffer = '';
$tx->res->content->unsubscribe('read')->on(
  read => sub {
    my ($content, $chunk) = @_;
    $buffer .= $chunk;
    $tx->res->error({message => 'Interrupted'}) if length $buffer == 3;
  }
);
$t->ua->start($tx);
is $tx->res->code, 200, 'right status';
is $tx->res->error->{message}, 'Interrupted', 'right error';
is $buffer, 'hi ', 'right content';

# Stream with delay and content length
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/longpoll/length')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('hi there plain, whats up?');
is $stash->{drain}, 1, 'drain event has been emitted once';

# Stream with delay and finish
$t->get_ok('/longpoll/nolength')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => undef)->content_type_is('text/plain')
  ->content_is('hi there, what length?');
ok !$t->tx->keep_alive, 'connection will not be kept alive';

# The drain event should be emitted on the next reactor tick
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/longpoll/order')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('First, second, third!');
is $stash->{order}, 1, 'the drain event was emitted on the next reactor tick';

# Static file with cookies and session
$log = '';
$cb = $t->app->log->on(message => sub { $log .= pop });
$t->get_ok('/longpoll/static')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_like('Set-Cookie' => qr/bar=baz/)
  ->header_like('Set-Cookie' => qr/mojolicious=/)
  ->content_type_is('text/plain;charset=UTF-8')
  ->content_is("Hello Mojo from a static file!\n");
like $log, qr/Nothing has been rendered, expecting delayed response/,
  'right message';
$t->app->log->unsubscribe(message => $cb);

# Custom response
$t->get_ok('/longpoll/dynamic')->status_is(201)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_like('Set-Cookie' => qr/baz=yada/)->content_is('Dynamic!');

# Chunked response streaming with drain event
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/stream')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('0123456789');
is $stash->{subscribers}, 0, 'no leaking subscribers';
ok $stash->{destroyed}, 'controller has been destroyed';

# Rendering of template
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/render')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Finish!');
Mojo::IOLoop->one_tick until $stash->{destroyed};
ok !$stash->{writing}, 'finish event timing is right';
ok $stash->{destroyed}, 'controller has been destroyed';

# Request timeout
$tx = $t->ua->request_timeout(0.5)->get('/too_long');
is $tx->error->{message}, 'Request timeout', 'right error';
$t->ua->request_timeout(0);

# Inactivity timeout
$tx = $t->ua->inactivity_timeout(0.5)->get('/too_long');
is $tx->error->{message}, 'Inactivity timeout', 'right error';
$t->ua->inactivity_timeout(20);

# Transaction is available after rendering early in steps
$t->get_ok('/steps')->status_is(200)->content_is('second');
Mojo::IOLoop->one_tick until $steps;
is $steps, 'third', 'right result';

# Event loop is automatically started for steps
my $c = app->build_controller;
$c->steps;
is $c->res->body, 'second', 'right content';

# Exception in step
$t->get_ok('/steps?die=1')->status_is(500)->content_like(qr/intentional/);

done_testing();

__DATA__
@@ render.html.ep
<%= $msg %>\
