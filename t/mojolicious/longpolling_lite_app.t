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

get '/shortpoll' => sub {
  my $c = shift;
  $c->res->headers->connection('close');
  $c->on(finish => sub { shift->stash->{finished}++ });
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->finish('this was short.');
} => 'shortpoll';

get '/shortpoll/plain' => sub {
  my $c = shift;
  $c->on(finish => sub { shift->stash->{finished}++ });
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->res->headers->content_length(25);
  $c->write('this was short and plain.');
};

get '/shortpoll/nolength' => sub {
  my $c = shift;
  $c->on(finish => sub { shift->stash->{finished}++ });
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->write('this was short and had no length.');
  $c->write('');
};

get '/longpoll' => sub {
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

get '/longpoll/nolength' => sub {
  my $c = shift;
  $c->on(finish => sub { shift->stash->{finished}++ });
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

get '/longpoll/nested' => sub {
  my $c = shift;
  $c->on(finish => sub { shift->stash->{finished}++ });
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->cookie(foo => 'bar');
  $c->write_chunk(
    sub {
      shift->write_chunk('nested!' => sub { shift->write_chunk('') });
    }
  );
};

get '/longpoll/plain' => sub {
  my $c = shift;
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->res->headers->content_length(25);
  $c->write('hi ');
  Mojo::IOLoop->timer(
    0.25 => sub {
      $c->on(finish => sub { shift->stash->{finished}++ });
      $c->write('there plain,' => sub { shift->write(' whats up?') });
    }
  );
};

get '/longpoll/delayed' => sub {
  my $c = shift;
  $c->on(finish => sub { shift->stash->{finished}++ });
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->write_chunk;
  Mojo::IOLoop->timer(
    0.25 => sub {
      $c->write_chunk(
        sub {
          my $c = shift;
          $c->write_chunk('how');
          $c->finish('dy!');
        }
      );
    }
  );
};

get '/longpoll/plain/delayed' => sub {
  my $c = shift;
  $c->on(finish => sub { shift->stash->{finished}++ });
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->res->headers->content_length(12);
  $c->write;
  Mojo::IOLoop->timer(
    0.25 => sub {
      $c->write(
        sub {
          my $c = shift;
          $c->write('how');
          $c->write('dy plain!');
        }
      );
    }
  );
} => 'delayed';

get '/longpoll/nolength/delayed' => sub {
  my $c = shift;
  $c->on(finish => sub { shift->stash->{finished}++ });
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  $c->write;
  Mojo::IOLoop->timer(
    0.25 => sub {
      $c->write(
        sub {
          my $c = shift;
          $c->write('how');
          $c->finish('dy nolength!');
        }
      );
    }
  );
};

get '/longpoll/static/delayed' => sub {
  my $c = shift;
  $c->on(finish => sub { shift->stash->{finished}++ });
  $c->cookie(bar => 'baz');
  $c->session(foo => 'bar');
  Mojo::IOLoop->timer(0.25 => sub { $c->reply->static('hello.txt') });
};

get '/longpoll/dynamic/delayed' => sub {
  my $c = shift;
  $c->on(finish => sub { shift->stash->{finished}++ });
  Mojo::IOLoop->timer(
    0.25 => sub {
      $c->res->code(201);
      $c->cookie(baz => 'yada');
      $c->res->body('Dynamic!');
      $c->rendered;
    }
  );
} => 'dynamic';

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

get '/finish' => sub {
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
$t->get_ok('/shortpoll')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('this was short.');
ok !$t->tx->kept_alive, 'connection was not kept alive';
ok !$t->tx->keep_alive, 'connection will not be kept alive';
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';
unlike $log, qr/Nothing has been rendered, expecting delayed response/,
  'right message';
$t->app->log->unsubscribe(message => $cb);

# Stream without delay and content length
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/shortpoll/plain')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('this was short and plain.');
ok !$t->tx->kept_alive, 'connection was not kept alive';
ok $t->tx->keep_alive, 'connection will be kept alive';
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';

# Stream without delay and empty write
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/shortpoll/nolength')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => undef)->content_type_is('text/plain')
  ->content_is('this was short and had no length.');
ok $t->tx->kept_alive, 'connection was kept alive';
ok !$t->tx->keep_alive, 'connection will not be kept alive';
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';

# Chunked response with delay
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/longpoll')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('hi there, whats up?');
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
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;
        $stream->close;
        Mojo::IOLoop->timer(0.25 => sub { Mojo::IOLoop->stop });
      }
    );
    $stream->write("GET /longpoll HTTP/1.1\x0d\x0a\x0d\x0a");
  }
);
Mojo::IOLoop->start;
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';

# Interrupted by raising an error
my $tx = $t->ua->build_tx(GET => '/longpoll');
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

# Stream with delay and finish
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/longpoll/nolength')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => undef)->content_type_is('text/plain')
  ->content_is('hi there, what length?');
ok !$t->tx->keep_alive, 'connection will not be kept alive';
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';

# Stream with delay and empty write
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/longpoll/nested')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_like('Set-Cookie' => qr/foo=bar/)->content_type_is('text/plain')
  ->content_is('nested!');
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';

# Stream with delay and content length
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/longpoll/plain')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('hi there plain, whats up?');
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';

# Chunked response delayed multiple times with finish
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/longpoll/delayed')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('howdy!');
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';

# Stream delayed multiple times with content length
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/longpoll/plain/delayed')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('howdy plain!');
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';

# Stream delayed multiple times with finish
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/longpoll/nolength/delayed')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => undef)->content_type_is('text/plain')
  ->content_is('howdy nolength!');
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';

# Delayed static file with cookies and session
$log   = '';
$cb    = $t->app->log->on(message => sub { $log .= pop });
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/longpoll/static/delayed')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_like('Set-Cookie' => qr/bar=baz/)
  ->header_like('Set-Cookie' => qr/mojolicious=/)
  ->content_type_is('text/plain;charset=UTF-8')
  ->content_is("Hello Mojo from a static file!\n");
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';
like $log, qr/Nothing has been rendered, expecting delayed response/,
  'right message';
$t->app->log->unsubscribe(message => $cb);

# Delayed custom response
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/longpoll/dynamic/delayed')->status_is(201)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_like('Set-Cookie' => qr/baz=yada/)->content_is('Dynamic!');
is $stash->{finished}, 1, 'finish event has been emitted once';
ok $stash->{destroyed}, 'controller has been destroyed';

# Chunked response streaming with drain event
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/stream')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('0123456789');
is $stash->{subscribers}, 0, 'no leaking subscribers';
ok $stash->{destroyed}, 'controller has been destroyed';

# Finish event timing and delayed rendering of template
$stash = undef;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/finish')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Finish!');
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
@@ finish.html.ep
<%= $msg %>\
