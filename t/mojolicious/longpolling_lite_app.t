use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::IOLoop;
use Mojolicious::Lite;
use Test::Mojo;

my $shortpoll;
get '/shortpoll' => sub {
  my $self = shift;
  $self->res->headers->connection('close');
  $self->on(finish => sub { $shortpoll++ });
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->finish('this was short.');
} => 'shortpoll';

my $shortpoll_plain;
get '/shortpoll/plain' => sub {
  my $self = shift;
  $self->on(finish => sub { $shortpoll_plain = 'finished!' });
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->res->headers->content_length(25);
  $self->write('this was short and plain.');
};

my $shortpoll_nolength;
get '/shortpoll/nolength' => sub {
  my $self = shift;
  $self->on(finish => sub { $shortpoll_nolength = 'finished!' });
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->write('this was short and had no length.');
  $self->write('');
};

my $longpoll;
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
      Mojo::IOLoop->remove($id);
      $longpoll = 'finished!';
    }
  );
};

my $longpoll_nolength;
get '/longpoll/nolength' => sub {
  my $self = shift;
  $self->on(finish => sub { $longpoll_nolength = 'finished!' });
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

my $longpoll_nested;
get '/longpoll/nested' => sub {
  my $self = shift;
  $self->on(finish => sub { $longpoll_nested = 'finished!' });
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->cookie(foo => 'bar');
  $self->write_chunk(
    sub {
      shift->write_chunk('nested!' => sub { shift->write_chunk('') });
    }
  );
};

my $longpoll_plain;
get '/longpoll/plain' => sub {
  my $self = shift;
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->res->headers->content_length(25);
  $self->write('hi ');
  Mojo::IOLoop->timer(
    0.25 => sub {
      $self->on(finish => sub { $longpoll_plain = 'finished!' });
      $self->write('there plain,' => sub { shift->write(' whats up?') });
    }
  );
};

my $longpoll_delayed;
get '/longpoll/delayed' => sub {
  my $self = shift;
  $self->on(finish => sub { $longpoll_delayed = 'finished!' });
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

my $longpoll_plain_delayed;
get '/longpoll/plain/delayed' => sub {
  my $self = shift;
  $self->on(finish => sub { $longpoll_plain_delayed = 'finished!' });
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

my $longpoll_nolength_delayed;
get '/longpoll/nolength/delayed' => sub {
  my $self = shift;
  $self->on(finish => sub { $longpoll_nolength_delayed = 'finished!' });
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

my $longpoll_static_delayed;
get '/longpoll/static/delayed' => sub {
  my $self = shift;
  $self->on(finish => sub { $longpoll_static_delayed = 'finished!' });
  Mojo::IOLoop->timer(0.25 => sub { $self->render_static('hello.txt') });
};

my $longpoll_static_delayed_too;
get '/longpoll/static/delayed_too' => sub {
  my $self = shift;
  $self->on(finish => sub { $longpoll_static_delayed_too = 'finished!' });
  $self->cookie(bar => 'baz');
  $self->session(foo => 'bar');
  $self->render_later;
  Mojo::IOLoop->timer(0.25 => sub { $self->render_static('hello.txt') });
} => 'delayed_too';

my $longpoll_dynamic_delayed;
get '/longpoll/dynamic/delayed' => sub {
  my $self = shift;
  $self->on(finish => sub { $longpoll_dynamic_delayed = 'finished!' });
  Mojo::IOLoop->timer(
    0.25 => sub {
      $self->res->code(201);
      $self->cookie(baz => 'yada');
      $self->res->body('Dynamic!');
      $self->rendered;
    }
  );
} => 'dynamic';

my $stream;
get '/stream' => sub {
  my $self = shift;
  my $i    = 0;
  my $drain;
  $drain = sub {
    my $self = shift;
    return $self->finish if $i >= 10;
    $self->write_chunk($i++, $drain);
    $stream
      += @{Mojo::IOLoop->stream($self->tx->connection)->subscribers('drain')};
  };
  $self->$drain;
};

my $finish;
get '/finish' => sub {
  my $self   = shift;
  my $stream = Mojo::IOLoop->stream($self->tx->connection);
  $self->on(finish => sub { $finish = $stream->is_writing });
  $self->render(text => 'Finish!');
};

my $too_long;
get '/too_long' => sub {
  my $self = shift;
  $self->on(finish => sub { $too_long = 'finished!' });
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  $self->res->headers->content_length(12);
  $self->write('how');
  Mojo::IOLoop->timer(5 => sub { $self->write('dy plain!') });
};

my $t = Test::Mojo->new;

# Stream without delay and finish
$t->get_ok('/shortpoll')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('this was short.');
ok !$t->tx->kept_alive, 'connection was not kept alive';
ok !$t->tx->keep_alive, 'connection will not be kept alive';
is $shortpoll, 1, 'finished';

# Stream without delay and content length
$t->get_ok('/shortpoll/plain')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('this was short and plain.');
ok !$t->tx->kept_alive, 'connection was not kept alive';
ok $t->tx->keep_alive, 'connection will be kept alive';
is $shortpoll_plain, 'finished!', 'finished';

# Stream without delay and empty write
$t->get_ok('/shortpoll/nolength')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => undef)->content_type_is('text/plain')
  ->content_is('this was short and had no length.');
ok $t->tx->kept_alive, 'connection was kept alive';
ok !$t->tx->keep_alive, 'connection will not be kept alive';
is $shortpoll_nolength, 'finished!', 'finished';

# Chunked response with delay
$t->get_ok('/longpoll')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('hi there, whats up?');
ok !$t->tx->kept_alive, 'connection was not kept alive';
ok $t->tx->keep_alive, 'connection will be kept alive';
is $longpoll, 'finished!', 'finished';

# Interrupted by closing the connection
$longpoll = undef;
my $port = $t->ua->app_url->port;
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
is $longpoll, 'finished!', 'finished';

# Interrupted by raising an error
my $tx = $t->ua->build_tx(GET => '/longpoll');
my $buffer = '';
$tx->res->body(
  sub {
    my ($self, $chunk) = @_;
    $buffer .= $chunk;
    $self->error('Interrupted') if length $buffer == 3;
  }
);
$t->ua->start($tx);
is $tx->res->code,  200,           'right status';
is $tx->res->error, 'Interrupted', 'right error';
is $buffer, 'hi ', 'right content';

# Stream with delay and finish
$t->get_ok('/longpoll/nolength')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => undef)->content_type_is('text/plain')
  ->content_is('hi there, what length?');
ok !$t->tx->keep_alive, 'connection will not be kept alive';
is $longpoll_nolength, 'finished!', 'finished';

# Stream with delay and empty write
$t->get_ok('/longpoll/nested')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_like('Set-Cookie' => qr/foo=bar/)->content_type_is('text/plain')
  ->content_is('nested!');
is $longpoll_nested, 'finished!', 'finished';

# Stream with delay and content length
$t->get_ok('/longpoll/plain')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('hi there plain, whats up?');
is $longpoll_plain, 'finished!', 'finished';

# Chunked response delayed multiple times with finish
$t->get_ok('/longpoll/delayed')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('howdy!');
is $longpoll_delayed, 'finished!', 'finished';

# Stream delayed multiple times with content length
$t->get_ok('/longpoll/plain/delayed')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('howdy plain!');
is $longpoll_plain_delayed, 'finished!', 'finished';

# Stream delayed multiple times with finish
$t->get_ok('/longpoll/nolength/delayed')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => undef)->content_type_is('text/plain')
  ->content_is('howdy nolength!');
is $longpoll_nolength_delayed, 'finished!', 'finished';

# Delayed static file
$t->get_ok('/longpoll/static/delayed')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is("Hello Mojo from a static file!\n");
is $longpoll_static_delayed, 'finished!', 'finished';

# Delayed static file with cookies and session
$t->get_ok('/longpoll/static/delayed_too')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_like('Set-Cookie' => qr/bar=baz/)
  ->header_like('Set-Cookie' => qr/mojolicious=/)
  ->content_type_is('text/plain')
  ->content_is("Hello Mojo from a static file!\n");
is $longpoll_static_delayed_too, 'finished!', 'finished';

# Delayed custom response
$t->get_ok('/longpoll/dynamic/delayed')->status_is(201)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_like('Set-Cookie' => qr/baz=yada/)->content_is('Dynamic!');
is $longpoll_dynamic_delayed, 'finished!', 'finished';

# Chunked response streaming with drain event
$t->get_ok('/stream')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('0123456789');
is $stream, 0, 'no leaking subscribers';

# Finish event timing
$t->get_ok('/finish')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Finish!');
ok !$finish, 'finish event timing is right';

# Request timeout
$tx = $t->ua->request_timeout(0.5)->build_tx(GET => '/too_long');
$buffer = '';
$tx->res->body(
  sub {
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
$tx->res->body(
  sub {
    my ($self, $chunk) = @_;
    $buffer .= $chunk;
  }
);
$t->ua->start($tx);
is $tx->res->code, 200, 'right status';
is $tx->error, 'Inactivity timeout', 'right error';
is $buffer, 'how', 'right content';

done_testing();
