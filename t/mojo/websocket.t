use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 48;

use IO::Socket::INET;
use Mojo::IOLoop;
use Mojo::Transaction::WebSocket;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Max WebSocket size
{
  local $ENV{MOJO_MAX_WEBSOCKET_SIZE} = 1024;
  is(Mojo::Transaction::WebSocket->new->max_websocket_size,
    1024, 'right value');
}

# Silence
app->log->level('fatal');

# Avoid exception template
app->renderer->paths->[0] = app->home->rel_dir('public');

# GET /link
get '/link' => sub {
  my $self = shift;
  $self->render(text => $self->url_for('index')->to_abs);
};

# WebSocket /
my $server;
websocket '/' => sub {
  my $self = shift;
  $self->on(finish => sub { $server += 2 });
  $self->on(
    message => sub {
      my ($self, $message) = @_;
      my $url = $self->url_for->to_abs;
      $self->send("${message}test2$url");
      $server = 1;
    }
  );
} => 'index';

# GET /something/else
get '/something/else' => sub {
  my $self = shift;
  my $timeout
    = Mojo::IOLoop->singleton->stream($self->tx->connection)->timeout;
  $self->render(text => "${timeout}failed!");
};

# WebSocket /socket
websocket '/socket' => sub {
  my $self = shift;
  $self->send(
    $self->req->headers->host => sub {
      my $self = shift;
      $self->send(Mojo::IOLoop->stream($self->tx->connection)->timeout);
      $self->finish;
    }
  );
};

# WebSocket /early_start
websocket '/early_start' => sub {
  my $self = shift;
  $self->send('test1');
  $self->on(
    message => sub {
      my ($self, $message) = @_;
      $self->send("${message}test2")->finish;
    }
  );
};

# WebSocket /denied
my ($handshake, $denied);
websocket '/denied' => sub {
  my $self = shift;
  $self->tx->handshake->on(finish => sub { $handshake += 1 });
  $self->on(finish => sub { $denied += 1 });
  $self->render(text => 'denied', status => 403);
};

# WebSocket /subreq
my $subreq;
websocket '/subreq' => sub {
  my $self = shift;
  $self->ua->websocket(
    '/echo' => sub {
      my $tx = pop;
      $tx->on(
        message => sub {
          my ($tx, $message) = @_;
          $self->send($message);
          $tx->finish;
          $self->finish;
        }
      );
      $tx->send('test1');
    }
  );
  $self->send('test0');
  $self->on(finish => sub { $subreq += 1 });
};

# WebSocket /echo
websocket '/echo' => sub {
  my $self = shift;
  $self->on(
    message => sub {
      my ($self, $message) = @_;
      $self->send($message);
    }
  );
};

# WebSocket /double_echo
my $buffer = '';
websocket '/double_echo' => sub {
  shift->on(
    message => sub {
      my ($self, $message) = @_;
      $self->send($message => sub { shift->send($message) });
    }
  );
};

# WebSocket /dead
websocket '/dead' => sub { die 'i see dead processes' };

# WebSocket /foo
websocket '/foo' =>
  sub { shift->rendered->res->code('403')->message("i'm a teapot") };

# WebSocket /deadcallback
websocket '/deadcallback' => sub {
  my $self = shift;
  $self->on(message => sub { die 'i see dead callbacks' });
};

# WebSocket /timeout
my $timeout;
websocket '/timeout' => sub {
  my $self = shift;
  Mojo::IOLoop->stream($self->tx->connection)->timeout(0.25);
  $self->on(finish => sub { $timeout = 'works!' });
};

# GET /link
my $ua  = app->ua;
my $res = $ua->get('/link')->success;
is $res->code, 200, 'right status';
like $res->body, qr!ws\://localhost\:\d+/!, 'right content';

# GET /socket (plain HTTP request)
$res = $ua->get('/socket')->res;
is $res->code, 404, 'right status';
like $res->body, qr/Page not found/, 'right content';

# WebSocket /
my $loop = Mojo::IOLoop->singleton;
my $result;
$ua->websocket(
  '/' => sub {
    my $tx = pop;
    $tx->on(finish => sub { $loop->stop });
    $tx->on(
      message => sub {
        my ($tx, $message) = @_;
        $result = $message;
        $tx->finish;
      }
    );
    $tx->send('test1');
  }
);
$loop->start;
like $result, qr!test1test2ws\://localhost\:\d+/!, 'right result';

# WebSocket /something/else (failed websocket connection)
my ($code, $body, $ws);
$ua->websocket(
  '/something/else' => sub {
    my $tx = pop;
    $ws   = $tx->is_websocket;
    $code = $tx->res->code;
    $body = $tx->res->body;
    $loop->stop;
  }
);
$loop->start;
ok !$ws, 'not a websocket';
is $code, 426, 'right code';
ok $body =~ /^(\d+)failed!$/, 'right content';
is $1, 15, 'right timeout';

# WebSocket /socket (using an already prepared socket)
my $port = $ua->app_url->port;
my $tx   = $ua->build_websocket_tx('ws://lalala/socket');
my $finished;
$tx->on(finish => sub { $finished++ });
my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port);
$sock->blocking(0);
$tx->connection($sock);
$result = '';
my ($local, $early);
$ua->start(
  $tx => sub {
    my $tx = pop;
    $early = $finished;
    $tx->on(finish => sub { $loop->stop });
    $tx->on(
      message => sub {
        my ($tx, $message) = @_;
        $tx->finish if length $result;
        $result .= $message;
      }
    );
    $local = $loop->stream($tx->connection)->handle->sockport;
  }
);
$loop->start;
is $finished, 1, 'finish event has been emitted';
is $early,    1, 'finish event has been emitted at the right time';
ok $result =~ /^lalala(\d+)$/, 'right result';
is $1, 15, 'right timeout';
ok $local, 'local port';
is $loop->stream($tx->connection)->handle, $sock, 'right connection id';

# WebSocket /early_start (server directly sends a message)
$result = undef;
my $client;
$ua->websocket(
  '/early_start' => sub {
    my $tx = pop;
    $tx->on(
      finish => sub {
        $client += 2;
        $loop->stop;
      }
    );
    $tx->on(
      message => sub {
        my ($tx, $message) = @_;
        $result = $message;
        $tx->send('test3');
        $client = 1;
      }
    );
  }
);
$loop->start;
is $result, 'test3test2', 'right result';
is $client, 3,            'finish event has been emitted';

# WebSocket /denied (connection denied)
$code = undef;
$ua->websocket(
  '/denied' => sub {
    $code = pop->res->code;
    $loop->stop;
  }
);
$loop->start;
is $code,      403, 'right status';
is $handshake, 1,   'finished handshake';
is $denied,    1,   'finished websocket';

# WebSocket /subreq
$finished = 0;
($code, $result) = undef;
$ua->websocket(
  '/subreq' => sub {
    my $tx = pop;
    $code   = $tx->res->code;
    $result = '';
    $tx->on(
      message => sub {
        my ($tx, $message) = @_;
        $result .= $message;
        $tx->finish if $message eq 'test1';
      }
    );
    $tx->on(
      finish => sub {
        $finished += 4;
        $loop->stop;
      }
    );
  }
);
$loop->start;
is $code,     101,          'right status';
is $result,   'test0test1', 'right result';
is $finished, 4,            'finished client websocket';
is $subreq,   1,            'finished server websocket';

# WebSocket /subreq (parallel)
my $delay = Mojo::IOLoop->delay;
$finished = 0;
($code, $result) = undef;
my ($code2, $result2);
$delay->begin;
$ua->websocket(
  '/subreq' => sub {
    my $tx = pop;
    $code   = $tx->res->code;
    $result = '';
    $tx->on(
      message => sub {
        my ($tx, $message) = @_;
        $result .= $message;
        $tx->finish if $message eq 'test1';
      }
    );
    $tx->on(
      finish => sub {
        $finished += 1;
        $delay->end;
      }
    );
  }
);
$delay->begin;
$ua->websocket(
  '/subreq' => sub {
    my $tx = pop;
    $code2   = $tx->res->code;
    $result2 = '';
    $tx->on(
      message => sub {
        my ($tx, $message) = @_;
        $result2 .= $message;
        $tx->finish if $message eq 'test1';
      }
    );
    $tx->on(
      finish => sub {
        $finished += 2;
        $delay->end;
      }
    );
  }
);
$delay->wait;
is $code,     101,          'right status';
is $result,   'test0test1', 'right result';
is $code2,    101,          'right status';
is $result2,  'test0test1', 'right result';
is $finished, 3,            'finished client websocket';
is $subreq,   3,            'finished server websocket';

# WebSocket /echo (client-side drain callback)
$result = '';
$client = 0;
my ($drain, $counter);
$ua->websocket(
  '/echo' => sub {
    my $tx = pop;
    $tx->on(
      finish => sub {
        $client += 2;
        $loop->stop;
      }
    );
    $tx->on(
      message => sub {
        my ($tx, $message) = @_;
        $result .= $message;
        $tx->finish if ++$counter == 2;
      }
    );
    $client = 1;
    $tx->send(
      'hi!' => sub {
        shift->send('there!');
        $drain
          += @{Mojo::IOLoop->stream($tx->connection)->subscribers('drain')};
      }
    );
  }
);
$loop->start;
is $result, 'hi!there!', 'right result';
is $client, 3,           'finish event has been emitted';
is $drain,  1,           'no leaking subscribers';

# WebSocket /double_echo (server-side drain callback)
$result = '';
$counter = $client = 0;
$ua->websocket(
  '/double_echo' => sub {
    my $tx = pop;
    $tx->on(
      finish => sub {
        $client += 2;
        $loop->stop;
      }
    );
    $tx->on(
      message => sub {
        my ($tx, $message) = @_;
        $result .= $message;
        $tx->finish if ++$counter == 2;
      }
    );
    $client = 1;
    $tx->send('hi!');
  }
);
$loop->start;
is $result, 'hi!hi!', 'right result';
is $client, 3,        'finish event has been emitted';

# WebSocket /dead (dies)
$finished = $code = undef;
my ($websocket, $message);
$ua->websocket(
  '/dead' => sub {
    my $tx = pop;
    $finished  = $tx->is_finished;
    $websocket = $tx->is_websocket;
    $code      = $tx->res->code;
    $message   = $tx->res->message;
    $loop->stop;
  }
);
$loop->start;
ok $finished, 'transaction is finished';
ok !$websocket, 'no websocket';
is $code, 500, 'right status';
is $message, 'Internal Server Error', 'right message';

# WebSocket /foo (forbidden)
($websocket, $code, $message) = undef;
$ua->websocket(
  '/foo' => sub {
    my $tx = pop;
    $websocket = $tx->is_websocket;
    $code      = $tx->res->code;
    $message   = $tx->res->message;
    $loop->stop;
  }
);
$loop->start;
ok !$websocket, 'no websocket';
is $code,    403,            'right status';
is $message, "i'm a teapot", 'right message';

# WebSocket /deadcallback (dies in callback)
$ua->websocket(
  '/deadcallback' => sub {
    pop->send('test1');
    $loop->stop;
  }
);
$loop->start;

# WebSocket /echo (16bit length)
$result = undef;
$ua->websocket(
  '/echo' => sub {
    my $tx = pop;
    $tx->on(finish => sub { $loop->stop });
    $tx->on(
      message => sub {
        my ($tx, $message) = @_;
        $result = $message;
        $tx->finish;
      }
    );
    $tx->send('hi!' x 100);
  }
);
$loop->start;
is $result, 'hi!' x 100, 'right result';

# WebSocket /timeout
my $log = '';
$message = app->log->on(message => sub { $log .= pop });
$ua->websocket(
  '/timeout' => sub {
    pop->on(finish => sub { Mojo::IOLoop->stop });
  }
);
Mojo::IOLoop->start;
app->log->unsubscribe(message => $message);
is $timeout, 'works!', 'finish event has been emitted';
like $log, qr/Inactivity timeout\./, 'right log message';

# WebSocket /echo (ping/pong)
my $pong;
$ua->websocket(
  '/echo' => sub {
    my $tx = pop;
    $tx->on(
      frame => sub {
        my ($tx, $frame) = @_;
        $pong = $frame->[5] if $frame->[4] == 10;
        Mojo::IOLoop->stop;
      }
    );
    $tx->send([1, 0, 0, 0, 9, 'test']);
  }
);
Mojo::IOLoop->start;
is $pong, 'test', 'received pong with payload';

# The "finish" event has been emitted on the server side too
is $server, 3, 'finish event has been emitted';
