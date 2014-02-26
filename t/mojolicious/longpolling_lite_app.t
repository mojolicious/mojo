use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

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
  my $self = shift;
  $self->res->headers->connection('close');
  $self->on(finish => sub { shift->stash->{finished}++ });
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->finish('this was short.');
} => 'shortpoll';

get '/shortpoll/plain' => sub {
  my $self = shift;
  $self->on(finish => sub { shift->stash->{finished}++ });
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->res->headers->content_length(25);
  $self->write('this was short and plain.');
};

get '/shortpoll/nolength' => sub {
  my $self = shift;
  $self->on(finish => sub { shift->stash->{finished}++ });
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->write('this was short and had no length.');
  $self->write('');
};

get '/longpoll' => sub {
  my $self = shift;
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->write_chunk('hi ');
  my $id = Mojo::IOLoop->timer(
    0.25 => sub {
      $self->write_chunk(
        'there,' => sub {
          shift->write_chunk(' whats up?' => sub { shift->finish });
        }
      );
    }
  );
  $self->on(
    finish => sub {
      shift->stash->{finished}++;
      Mojo::IOLoop->remove($id);
    }
  );
};

get '/longpoll/nolength' => sub {
  my $self = shift;
  $self->on(finish => sub { shift->stash->{finished}++ });
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->write('hi ');
  Mojo::IOLoop->timer(
    0.25 => sub {
      $self->write(
        'there,' => sub {
          shift->write(' what length?' => sub { $self->finish });
        }
      );
    }
  );
};

get '/longpoll/nested' => sub {
  my $self = shift;
  $self->on(finish => sub { shift->stash->{finished}++ });
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->cookie(foo => 'bar');
  $self->write_chunk(
    sub {
      shift->write_chunk('nested!' => sub { shift->write_chunk('') });
    }
  );
};

get '/longpoll/plain' => sub {
  my $self = shift;
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->res->headers->content_length(25);
  $self->write('hi ');
  Mojo::IOLoop->timer(
    0.25 => sub {
      $self->on(finish => sub { shift->stash->{finished}++ });
      $self->write('there plain,' => sub { shift->write(' whats up?') });
    }
  );
};

get '/longpoll/delayed' => sub {
  my $self = shift;
  $self->on(finish => sub { shift->stash->{finished}++ });
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->write_chunk;
  Mojo::IOLoop->timer(
    0.25 => sub {
      $self->write_chunk(
        sub {
          my $self = shift;
          $self->write_chunk('how');
          $self->finish('dy!');
        }
      );
    }
  );
};

get '/longpoll/plain/delayed' => sub {
  my $self = shift;
  $self->on(finish => sub { shift->stash->{finished}++ });
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->res->headers->content_length(12);
  $self->write;
  Mojo::IOLoop->timer(
    0.25 => sub {
      $self->write(
        sub {
          my $self = shift;
          $self->write('how');
          $self->write('dy plain!');
        }
      );
    }
  );
} => 'delayed';

get '/longpoll/nolength/delayed' => sub {
  my $self = shift;
  $self->on(finish => sub { shift->stash->{finished}++ });
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->write;
  Mojo::IOLoop->timer(
    0.25 => sub {
      $self->write(
        sub {
          my $self = shift;
          $self->write('how');
          $self->finish('dy nolength!');
        }
      );
    }
  );
};

get '/longpoll/static/delayed' => sub {
  my $self = shift;
  $self->on(finish => sub { shift->stash->{finished}++ });
  $self->cookie(bar => 'baz');
  $self->session(foo => 'bar');
  Mojo::IOLoop->timer(0.25 => sub { $self->render_static('hello.txt') });
};

get '/longpoll/dynamic/delayed' => sub {
  my $self = shift;
  $self->on(finish => sub { shift->stash->{finished}++ });
  Mojo::IOLoop->timer(
    0.25 => sub {
      $self->res->code(201);
      $self->cookie(baz => 'yada');
      $self->res->body('Dynamic!');
      $self->rendered;
    }
  );
} => 'dynamic';

get '/stream' => sub {
  my $self = shift;
  my $i    = 0;
  my $drain;
  $drain = sub {
    my $self = shift;
    return $self->finish if $i >= 10;
    $self->write_chunk($i++, $drain);
    $self->stash->{subscribers}
      += @{Mojo::IOLoop->stream($self->tx->connection)->subscribers('drain')};
  };
  $self->$drain;
};

get '/finish' => sub {
  my $self   = shift;
  my $stream = Mojo::IOLoop->stream($self->tx->connection);
  $self->on(finish => sub { shift->stash->{writing} = $stream->is_writing });
  $self->render_later;
  Mojo::IOLoop->next_tick(sub { $self->render(msg => 'Finish!') });
};

get '/too_long' => sub {
  my $self = shift;
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->res->headers->content_length(12);
  $self->write('how');
  Mojo::IOLoop->timer(5 => sub { $self->write('dy plain!') });
};

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
unlike $log, qr/Nothing has been rendered, expecting delayed response\./,
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
    my ($self, $chunk) = @_;
    $buffer .= $chunk;
    $tx->res->error('Interrupted') if length $buffer == 3;
  }
);
$t->ua->start($tx);
is $tx->res->code,  200,           'right status';
is $tx->res->error, 'Interrupted', 'right error';
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
like $log, qr/Nothing has been rendered, expecting delayed response\./,
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
$tx = $t->ua->request_timeout(0.5)->build_tx(GET => '/too_long');
$buffer = '';
$tx->res->content->unsubscribe('read')->on(
  read => sub {
    my ($self, $chunk) = @_;
    $buffer .= $chunk;
  }
);
$t->ua->start($tx);
is $tx->res->code, 200, 'right status';
is $tx->error, 'Request timeout', 'right error';
is $buffer, 'how', 'right content';
$t->ua->request_timeout(0);

# Inactivity timeout
$tx = $t->ua->inactivity_timeout(0.5)->build_tx(GET => '/too_long');
$buffer = '';
$tx->res->content->unsubscribe('read')->on(
  read => sub {
    my ($self, $chunk) = @_;
    $buffer .= $chunk;
  }
);
$t->ua->start($tx);
is $tx->res->code, 200, 'right status';
is $tx->error, 'Inactivity timeout', 'right error';
is $buffer, 'how', 'right content';

done_testing();

__DATA__
@@ finish.html.ep
<%= $msg %>\
