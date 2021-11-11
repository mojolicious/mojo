use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use IO::Socket::IP;
use Mojo::IOLoop;
use Mojo::IOLoop::Client;
use Mojo::IOLoop::Server;
use Mojo::IOLoop::Stream;
use Mojo::Promise;

subtest 'Defaults' => sub {
  my $loop = Mojo::IOLoop->new;
  is $loop->max_connections, 1000, 'right default';
  $loop = Mojo::IOLoop->new(max_connections => 10);
  is $loop->max_connections, 10, 'right value';
};

subtest 'Double start' => sub {
  my $err;
  Mojo::IOLoop->next_tick(sub {
    my $loop = shift;
    eval { $loop->start };
    $err = $@;
    $loop->stop;
  });
  Mojo::IOLoop->start;
  like $err, qr/^Mojo::IOLoop already running/, 'right error';
};

subtest 'Double one_tick' => sub {
  my $err;
  Mojo::IOLoop->next_tick(sub {
    my $loop = shift;
    eval { $loop->one_tick };
    $err = $@;
  });
  Mojo::IOLoop->one_tick;
  like $err, qr/^Mojo::IOLoop already running/, 'right error';
};

subtest 'Basic functionality' => sub {
  my ($ticks, $timer, $hirestimer);
  my $loop = Mojo::IOLoop->new;
  my $id   = $loop->recurring(0 => sub { $ticks++ });
  $loop->timer(
    1 => sub {
      shift->timer(0 => sub { shift->stop });
      $timer++;
    }
  );
  $loop->timer(0.25 => sub { $hirestimer++ });
  $loop->start;
  ok $timer,      'recursive timer works';
  ok $hirestimer, 'hires timer works';
  $loop->one_tick;
  ok $ticks > 2, 'more than two ticks';

  # Run again without first tick event handler
  my $before = $ticks;
  my $after;
  my $id2 = $loop->recurring(0 => sub { $after++ });
  $loop->remove($id);
  $loop->timer(0.5 => sub { shift->stop });
  $loop->start;
  $loop->one_tick;
  $loop->remove($id2);
  ok $after > 1, 'more than one tick';
  is $ticks, $before, 'no additional ticks';
};

subtest 'Recurring timer' => sub {
  my $count;
  my $loop = Mojo::IOLoop->new;
  my $id   = $loop->recurring(0.1 => sub { $count++ });
  $loop->timer(0.5 => sub { shift->stop });
  $loop->start;
  $loop->one_tick;
  $loop->remove($id);
  ok($count > 1,  'more than one recurring event');
  ok($count < 10, 'less than ten recurring events');
};

subtest 'Handle and reset' => sub {
  my ($handle, $handle2, $reset, $close);
  Mojo::IOLoop->singleton->on(reset => sub { $reset++ });
  my $id = Mojo::IOLoop->server(
    (address => '127.0.0.1') => sub {
      my ($loop, $stream) = @_;
      $stream->on(close => sub { $close++ });
      $handle = $stream->handle;
      Mojo::IOLoop->stop;
    }
  );
  my $port = Mojo::IOLoop->acceptor($id)->port;
  Mojo::IOLoop->acceptor($id)->on(accept => sub { $handle2 = pop });
  my $id2 = Mojo::IOLoop->client((address => '127.0.0.1', port => $port) => sub { });
  Mojo::IOLoop->start;
  my ($count, $running, $timer) = (0) x 3;
  Mojo::IOLoop->recurring(10 => sub { $timer++ });
  Mojo::IOLoop->next_tick(sub {
    Mojo::IOLoop->reset;
    $running = Mojo::IOLoop->is_running;
  });
  Mojo::IOLoop->start;
  ok !$running, 'not running';
  is $count, 0, 'no recurring events';
  ok !Mojo::IOLoop->acceptor($id), 'acceptor has been removed';
  ok !Mojo::IOLoop->stream($id2),  'stream has been removed';
  is $handle, $handle2, 'handles are equal';
  isa_ok $handle, 'IO::Socket', 'right reference';
  is $reset, 1, 'reset event has been emitted once';
  is $close, 1, 'close event has been emitted once';
};

subtest 'Handle and reset with freeze' => sub {
  my ($handle, $handle2, $reset, $close);
  Mojo::IOLoop->singleton->on(reset => sub { $reset++ });
  my $id = Mojo::IOLoop->server(
    (address => '127.0.0.1') => sub {
      my ($loop, $stream) = @_;
      $stream->on(close => sub { $close++ });
      $handle = $stream->handle;
      Mojo::IOLoop->stop;
    }
  );
  my $port = Mojo::IOLoop->acceptor($id)->port;
  Mojo::IOLoop->acceptor($id)->on(accept => sub { $handle2 = pop });
  my $id2 = Mojo::IOLoop->client((address => '127.0.0.1', port => $port) => sub { });
  Mojo::IOLoop->start;
  my ($count, $running, $timer) = (0) x 3;
  Mojo::IOLoop->recurring(10 => sub { $timer++ });
  Mojo::IOLoop->next_tick(sub {
    Mojo::IOLoop->reset({freeze => 1});
    $running = Mojo::IOLoop->is_running;
  });
  Mojo::IOLoop->start;
  ok !$running, 'not running';
  is $count, 0, 'no recurring events';
  ok !Mojo::IOLoop->acceptor($id), 'acceptor has been removed';
  ok !Mojo::IOLoop->stream($id2),  'stream has been removed';
  is $handle, $handle2, 'handles are equal';
  isa_ok $handle, 'IO::Socket', 'right reference';
  is $reset, 1, 'reset event has been emitted once';
  ok !$close, 'close event has not been emitted';
};

subtest 'The poll reactor stops when there are no events being watched anymore' => sub {
  my $time = time;
  Mojo::IOLoop->start;
  Mojo::IOLoop->one_tick;
  Mojo::IOLoop->reset;
  ok time < ($time + 10), 'stopped automatically';
};

subtest 'Reset events' => sub {
  Mojo::IOLoop->singleton->on(finish => sub { });
  ok !!Mojo::IOLoop->singleton->has_subscribers('finish'), 'has subscribers';
  Mojo::IOLoop->reset;
  ok !Mojo::IOLoop->singleton->has_subscribers('finish'), 'no subscribers';
};

subtest 'Stream' => sub {
  my $buffer = '';
  my $id     = Mojo::IOLoop->server(
    (address => '127.0.0.1') => sub {
      my ($loop, $stream) = @_;
      $buffer .= 'accepted';
      $stream->on(
        read => sub {
          my ($stream, $chunk) = @_;
          $buffer .= $chunk;
          return unless $buffer eq 'acceptedhello';
          $stream->write('wo')->write('')->write('rld' => sub { shift->close });
        }
      );
    }
  );
  my $port    = Mojo::IOLoop->acceptor($id)->port;
  my $promise = Mojo::Promise->new;
  my $handle;
  Mojo::IOLoop->client(
    {port => $port} => sub {
      my ($loop, $err, $stream) = @_;
      $handle = $stream->steal_handle;
      $promise->resolve;
      $stream->on(close => sub { $buffer .= 'should not happen' });
      $stream->on(error => sub { $buffer .= 'should not happen either' });
    }
  );
  $promise->wait;
  my $stream = Mojo::IOLoop::Stream->new($handle);
  is $stream->timeout,              15, 'right default';
  is $stream->timeout(16)->timeout, 16, 'right timeout';
  $id = Mojo::IOLoop->stream($stream);
  $stream->on(close => sub { Mojo::IOLoop->stop });
  $stream->on(read  => sub { $buffer .= pop });
  $stream->write('hello');
  ok !!Mojo::IOLoop->stream($id), 'stream exists';
  is $stream->timeout, 16, 'right timeout';
  Mojo::IOLoop->start;
  Mojo::IOLoop->timer(0.25 => sub { Mojo::IOLoop->stop });
  Mojo::IOLoop->start;
  ok !Mojo::IOLoop->stream($id), 'stream does not exist anymore';
  is $buffer, 'acceptedhelloworld', 'right result';
};

subtest 'Removed listen socket' => sub {
  my $loop = Mojo::IOLoop->new;
  my $id   = $loop->server({address => '127.0.0.1'} => sub { });
  my $port = $loop->acceptor($id)->port;
  my $connected;
  $loop->client(
    {port => $port} => sub {
      my ($loop, $err, $stream) = @_;
      $loop->remove($id);
      $loop->stop;
      $connected = 1;
    }
  );
  my $fd = fileno $loop->acceptor($id)->handle;
  like $ENV{MOJO_REUSE}, qr/(?:^|\,)127\.0\.0\.1:\Q$port\E:\Q$fd\E/, 'file descriptor can be reused';
  $loop->start;
  unlike $ENV{MOJO_REUSE}, qr/(?:^|\,)127\.0\.0\.1:\Q$port\E:\Q$fd\E/, 'environment is clean';
  ok $connected,            'connected';
  ok !$loop->acceptor($id), 'acceptor has been removed';
};

subtest 'Removed connection (with promise)' => sub {
  my $removed;
  my $promise = Mojo::Promise->new;
  $promise->then(sub { $removed++ });
  my $id = Mojo::IOLoop->server(
    (address => '127.0.0.1') => sub {
      my ($loop, $stream) = @_;
      $stream->on(close => sub { $promise->resolve });
    }
  );
  my $port     = Mojo::IOLoop->acceptor($id)->port;
  my $promise2 = Mojo::Promise->new;
  $id = Mojo::IOLoop->client(
    (port => $port) => sub {
      my ($loop, $err, $stream) = @_;
      $stream->on(close => sub { $promise2->resolve });
      $loop->remove($id);
    }
  );
  Mojo::Promise->all($promise, $promise2)->wait;
  is $removed, 1, 'connection has been removed';
};

subtest 'Stream throttling' => sub {
  my ($client, $server, $client_after, $server_before, $server_after, @waiting);
  my $id = Mojo::IOLoop->server(
    {address => '127.0.0.1'} => sub {
      my ($loop, $stream) = @_;
      $stream->timeout(0)->on(
        read => sub {
          my ($stream, $chunk) = @_;
          Mojo::IOLoop->timer(
            0.5 => sub {
              $server_before = $server;
              $stream->stop;
              $stream->write('works!');
              push @waiting, $stream->bytes_waiting;
              Mojo::IOLoop->timer(
                0.5 => sub {
                  $server_after = $server;
                  $client_after = $client;
                  push @waiting, $stream->bytes_waiting;
                  $stream->start;
                  Mojo::IOLoop->timer(0.5 => sub { Mojo::IOLoop->stop });
                }
              );
            }
          ) unless $server;
          $server .= $chunk;
        }
      );
    }
  );
  my $port = Mojo::IOLoop->acceptor($id)->port;
  Mojo::IOLoop->client(
    {port => $port} => sub {
      my ($loop, $err, $stream) = @_;
      my $drain;
      $drain = sub { shift->write('1', $drain) };
      $stream->$drain();
      $stream->on(read => sub { $client .= pop });
    }
  );
  Mojo::IOLoop->start;
  is $server_before, $server_after, 'stream has been paused';
  ok length($server) > length($server_after), 'stream has been resumed';
  is $client, $client_after, 'stream was writable while paused';
  is $client, 'works!',      'full message has been written';
  is_deeply \@waiting, [6, 0], 'right buffer sizes';
};

subtest 'Watermarks' => sub {
  my $fake   = IO::Socket::IP->new(Listen => 5, LocalAddr => '127.0.0.1');
  my $stream = Mojo::IOLoop::Stream->new($fake);
  $stream->start;
  $stream->high_water_mark(10);
  $stream->write('abcd');
  is $stream->bytes_waiting, 4, 'four bytes waiting';
  ok $stream->can_write, 'stream is still writable';
  $stream->write('efghijk');
  is $stream->bytes_waiting, 11, 'eleven bytes waiting';
  ok !$stream->can_write, 'stream is not writable anymore';
  $stream->high_water_mark(12);
  ok $stream->can_write, 'stream is writable again';
  $stream->close;
  ok !$stream->can_write, 'closed stream is not writable anymore';
  undef $stream;
};

subtest 'Graceful shutdown' => sub {
  my $err;
  my $loop = Mojo::IOLoop->new;
  my $port = $loop->acceptor($loop->server({address => '127.0.0.1'} => sub { }))->port;
  my $id   = $loop->client({port => $port} => sub { shift->stop_gracefully });
  my $finish;
  $loop->on(finish => sub { ++$finish and shift->stream($id)->close });
  $loop->timer(30 => sub { shift->stop; $err = 'failed' });
  $loop->start;
  ok !$loop->stream($id), 'stopped gracefully';
  ok !$err,               'no error';
  is $finish, 1, 'finish event has been emitted once';
};

subtest 'Graceful shutdown (without connection)' => sub {
  my ($err, $finish);
  my $loop = Mojo::IOLoop->new;
  $loop->on(finish => sub { $finish++ });
  $loop->next_tick(sub { shift->stop_gracefully });
  $loop->timer(30 => sub { shift->stop; $err = 'failed' });
  $loop->start;
  ok !$err, 'no error';
  is $finish, 1, 'finish event has been emitted once';
};

subtest 'Graceful shutdown (max_accepts)' => sub {
  my $err;
  my $loop = Mojo::IOLoop->new->max_accepts(1);
  my $id   = $loop->server({address => '127.0.0.1'} => sub { });
  my $port = $loop->acceptor($id)->port;
  $loop->client({port => $port} => sub { pop->close });
  $loop->timer(30 => sub { shift->stop; $err = 'failed' });
  $loop->start;
  ok !$err, 'no error';
  is $loop->max_accepts, 1, 'right value';
};

subtest 'Connection limit' => sub {
  my ($err, $id);
  my $loop = Mojo::IOLoop->new->max_connections(2);
  my @accepting;
  $id = $loop->server(
    {address => '127.0.0.1', single_accept => 1} => sub {
      shift->next_tick(sub {
        my $loop = shift;
        push @accepting, $loop->acceptor($id)->is_accepting;
        $loop->stop if @accepting == 2;
      });
    }
  );
  my $port = $loop->acceptor($id)->port;
  $loop->client({port => $port} => sub { }) for 1 .. 2;
  $loop->timer(30 => sub { shift->stop; $err = 'failed' });
  $loop->start;
  ok !$err,          'no error';
  ok $accepting[0],  'accepting connections';
  ok !$accepting[1], 'connection limit reached';
};

subtest 'Exception in timer' => sub {
  local *STDERR;
  open STDERR, '>', \my $err;
  my $loop = Mojo::IOLoop->new;
  $loop->timer(0 => sub { die 'Bye!' });
  $loop->start;
  like $err, qr/^Mojo::Reactor::Poll:.*Bye!/, 'right error';
};

subtest 'Defaults' => sub {
  is(Mojo::IOLoop::Client->new->reactor, Mojo::IOLoop->singleton->reactor, 'right default');
  is(Mojo::IOLoop::Server->new->reactor, Mojo::IOLoop->singleton->reactor, 'right default');
  is(Mojo::IOLoop::Stream->new->reactor, Mojo::IOLoop->singleton->reactor, 'right default');
};

done_testing();
