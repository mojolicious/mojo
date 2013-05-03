use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::IOLoop;
use Mojo::IOLoop::Client;
use Mojo::IOLoop::Delay;
use Mojo::IOLoop::Server;
use Mojo::IOLoop::Stream;

# Custom reactor
package MyReactor;
use Mojo::Base 'Mojo::Reactor::Poll';

package main;

# Reactor detection
$ENV{MOJO_REACTOR} = 'MyReactorDoesNotExist';
my $loop = Mojo::IOLoop->new;
is ref $loop->reactor, 'Mojo::Reactor::Poll', 'right class';
$ENV{MOJO_REACTOR} = 'MyReactor';
$loop = Mojo::IOLoop->new;
is ref $loop->reactor, 'MyReactor', 'right class';

# Double start
my $err;
Mojo::IOLoop->timer(
  0 => sub {
    eval { Mojo::IOLoop->start };
    $err = $@;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
like $err, qr/^Mojo::IOLoop already running/, 'right error';

# Basic functionality
my ($ticks, $timer, $hirestimer);
my $id = $loop->recurring(0 => sub { $ticks++ });
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

# Recurring timer
my $count;
$id = $loop->recurring(0.1 => sub { $count++ });
$loop->timer(0.5 => sub { shift->stop });
$loop->start;
$loop->one_tick;
$loop->remove($id);
ok $count > 1, 'more than one recurring event';
ok $count < 10, 'less than ten recurring events';

# Handle
my $port = Mojo::IOLoop->generate_port;
my ($handle, $handle2);
$id = Mojo::IOLoop->server(
  (address => '127.0.0.1', port => $port) => sub {
    my ($loop, $stream) = @_;
    $handle = $stream->handle;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->acceptor($id)->on(accept => sub { $handle2 = pop });
$id2
  = Mojo::IOLoop->client((address => 'localhost', port => $port) => sub { });
Mojo::IOLoop->start;
Mojo::IOLoop->remove($id);
Mojo::IOLoop->remove($id2);
is $handle, $handle2, 'handles are equal';
isa_ok $handle, 'IO::Socket', 'right reference';

# The poll reactor stops when there are no events being watched anymore
my $time = time;
Mojo::IOLoop->start;
Mojo::IOLoop->one_tick;
ok time < ($time + 10), 'stopped automatically';

# Stream
$port = Mojo::IOLoop->generate_port;
my $buffer = '';
Mojo::IOLoop->server(
  (address => '127.0.0.1', port => $port) => sub {
    my ($loop, $stream, $id) = @_;
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
my $delay = Mojo::IOLoop->delay;
my $end   = $delay->begin(0);
Mojo::IOLoop->client(
  {port => $port} => sub {
    my ($loop, $err, $stream) = @_;
    $end->($stream);
    $stream->on(close => sub { $buffer .= 'should not happen' });
    $stream->on(error => sub { $buffer .= 'should not happen either' });
  }
);
$handle = $delay->wait->steal_handle;
my $stream = Mojo::IOLoop::Stream->new($handle);
$id = Mojo::IOLoop->stream($stream);
$stream->on(close => sub { Mojo::IOLoop->stop });
$stream->on(read => sub { $buffer .= pop });
$stream->write('hello');
ok(Mojo::IOLoop->stream($id), 'stream exists');
Mojo::IOLoop->start;
Mojo::IOLoop->timer(0.25 => sub { Mojo::IOLoop->stop });
Mojo::IOLoop->start;
ok !Mojo::IOLoop->stream($id), 'stream does not exist anymore';
is $buffer, 'acceptedhelloworld', 'right result';

# Removed listen socket
$port = Mojo::IOLoop->generate_port;
$id = $loop->server({address => '127.0.0.1', port => $port} => sub { });
my $connected;
$loop->client(
  {port => $port} => sub {
    my ($loop, $err, $stream) = @_;
    $loop->remove($id);
    $loop->stop;
    $connected = 1;
  }
);
like $ENV{MOJO_REUSE}, qr/(?:^|\,)${port}:/, 'file descriptor can be reused';
$loop->start;
unlike $ENV{MOJO_REUSE}, qr/(?:^|\,)${port}:/, 'environment is clean';
ok $connected, 'connected';
$err = undef;
$loop->client(
  (port => $port) => sub {
    shift->stop;
    $err = shift;
  }
);
$loop->start;
ok $err, 'has error';

# Removed connection (with delay)
my $removed;
$delay = Mojo::IOLoop->delay(sub { $removed++ });
$port  = Mojo::IOLoop->generate_port;
$end   = $delay->begin;
Mojo::IOLoop->server(
  (address => '127.0.0.1', port => $port) => sub {
    my ($loop, $stream) = @_;
    $stream->on(close => $end);
  }
);
my $end2 = $delay->begin;
$id = Mojo::IOLoop->client(
  (port => $port) => sub {
    my ($loop, $err, $stream) = @_;
    $stream->on(close => $end2);
    $loop->remove($id);
  }
);
$delay->wait;
is $removed, 1, 'connection has been removed';

# Stream throttling
$port = Mojo::IOLoop->generate_port;
my ($client, $server, $client_after, $server_before, $server_after);
Mojo::IOLoop->server(
  {address => '127.0.0.1', port => $port} => sub {
    my ($loop, $stream) = @_;
    $stream->timeout(0)->on(
      read => sub {
        my ($stream, $chunk) = @_;
        Mojo::IOLoop->timer(
          0.5 => sub {
            $server_before = $server;
            $stream->stop;
            $stream->write('works!');
            Mojo::IOLoop->timer(
              0.5 => sub {
                $server_after = $server;
                $client_after = $client;
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
is $client, 'works!', 'full message has been written';

# Graceful shutdown (max_connections)
$err = '';
$loop = Mojo::IOLoop->new(max_connections => 0);
$loop->remove($loop->client({port => $loop->generate_port} => sub { }));
$loop->timer(3 => sub { shift->stop; $err = 'failed' });
$loop->start;
ok !$err, 'no error';
is $loop->max_connections, 0, 'right value';

# Graceful shutdown (max_accepts)
$err  = '';
$loop = Mojo::IOLoop->new(max_accepts => 1);
$port = $loop->generate_port;
$loop->server(
  {address => '127.0.0.1', port => $port} => sub { shift; shift->close });
$loop->client({port => $port} => sub { });
$loop->timer(3 => sub { shift->stop; $err = 'failed' });
$loop->start;
ok !$err, 'no error';
is $loop->max_accepts, 1, 'right value';

# Defaults
is(
  Mojo::IOLoop::Client->new->reactor,
  Mojo::IOLoop->singleton->reactor,
  'right default'
);
is(Mojo::IOLoop::Delay->new->ioloop, Mojo::IOLoop->singleton, 'right default');
is(
  Mojo::IOLoop::Server->new->reactor,
  Mojo::IOLoop->singleton->reactor,
  'right default'
);
is(
  Mojo::IOLoop::Stream->new->reactor,
  Mojo::IOLoop->singleton->reactor,
  'right default'
);

done_testing();
