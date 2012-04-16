use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 67;

# "I don't mind being called a liar when I'm lying, or about to lie,
#  or just finished lying, but NOT WHEN I'M TELLING THE TRUTH."
use IO::Socket::INET;
use Mojo::Reactor::Poll;

# Instantiation
my $reactor = Mojo::Reactor::Poll->new;
is ref $reactor, 'Mojo::Reactor::Poll', 'right object';
is ref Mojo::Reactor::Poll->new, 'Mojo::Reactor::Poll', 'right object';
undef $reactor;
is ref Mojo::Reactor::Poll->new, 'Mojo::Reactor::Poll', 'right object';
use_ok 'Mojo::IOLoop';
$reactor = Mojo::IOLoop->singleton->reactor;
is ref $reactor, 'Mojo::Reactor::Poll', 'right object';

# Make sure it stops automatically when not watching for events
Mojo::IOLoop->one_tick;
my $triggered;
Mojo::IOLoop->timer(0.25 => sub { $triggered++ });
Mojo::IOLoop->start;
ok $triggered, 'reactor waited for one event';
Mojo::IOLoop->start;

# Listen
my $port   = Mojo::IOLoop->generate_port;
my $listen = IO::Socket::INET->new(
  Listen    => 5,
  LocalAddr => '127.0.0.1',
  LocalPort => $port,
  Proto     => 'tcp'
);
my ($readable, $writable);
$reactor->io($listen => sub { pop() ? $writable++ : $readable++ })
  ->watch($listen, 0, 0)->watch($listen, 1, 1);
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok !$readable, 'handle is not readable';
ok !$writable, 'handle is not writable';
ok !$reactor->is_readable($listen), 'handle is not readable';

# Connect
my $client =
  IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port);
$reactor->timer(1 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable';
ok !$writable, 'handle is not writable';
ok $reactor->is_readable($listen), 'handle is readable';

# Accept
my $server = $listen->accept;
$reactor->remove($listen);
($readable, $writable) = undef;
$reactor->io($client => sub { pop() ? $writable++ : $readable++ });
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok !$readable, 'handle is not readable';
ok $writable, 'handle is writable';
print $client "hello!\n";
sleep 1;
$reactor->remove($client);
($readable, $writable) = undef;
$reactor->io($server => sub { pop() ? $writable++ : $readable++ });
$reactor->watch($server, 1, 0);
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable';
ok !$writable, 'handle is not writable';
($readable, $writable) = undef;
$reactor->watch($server, 1, 1);
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable';
ok $writable, 'handle is writable';
($readable, $writable) = undef;
$reactor->watch($server, 0, 0);
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok !$readable, 'handle is not readable';
ok !$writable, 'handle is not writable';
($readable, $writable) = undef;
$reactor->watch($server, 1, 0);
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable';
ok !$writable, 'handle is not writable';
($readable, $writable) = undef;
$reactor->io($server => sub { pop() ? $writable++ : $readable++ });
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable';
ok $writable, 'handle is writable';

# Timers
my ($timer, $recurring);
$reactor->timer(0 => sub { $timer++ });
$reactor->remove($reactor->timer(0 => sub { $timer++ }));
my $id = $reactor->recurring(0 => sub { $recurring++ });
($readable, $writable) = undef;
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable,  'handle is readable again';
ok $writable,  'handle is writable again';
ok $timer,     'timer was triggered';
ok $recurring, 'recurring was triggered';
my $done = 0;
($readable, $writable, $timer, $recurring) = undef;
$reactor->timer(0.025 => sub { $done = shift->is_running });
$reactor->one_tick while !$done;
ok $readable, 'handle is readable again';
ok $writable, 'handle is writable again';
ok !$timer, 'timer was not triggered';
ok $recurring, 'recurring was triggered again';
($readable, $writable, $timer, $recurring) = undef;
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable again';
ok $writable, 'handle is writable again';
ok !$timer, 'timer was not triggered';
ok $recurring, 'recurring was triggered again';
($readable, $writable, $timer, $recurring) = undef;
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable again';
ok $writable, 'handle is writable again';
ok !$timer, 'timer was not triggered';
ok $recurring, 'recurring was triggered again';
$reactor->remove($id);
($readable, $writable, $timer, $recurring) = undef;
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable again';
ok $writable, 'handle is writable again';
ok !$timer,     'timer was not triggered';
ok !$recurring, 'recurring was not triggered again';

# Reset
$reactor->remove($id);
$reactor->remove($server);
($readable, $writable) = undef;
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok !$readable, 'io event was not triggered again';
ok !$writable, 'io event was not triggered again';
my $reactor2 = Mojo::Reactor::Poll->new;
is ref $reactor2, 'Mojo::Reactor::Poll', 'right object';

# Parallel loops
$timer = 0;
$reactor->recurring(0 => sub { $timer++ });
my $timer2 = 0;
$reactor2->recurring(0 => sub { $timer2++ });
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $timer, 'timer was triggered';
ok !$timer2, 'timer was not triggered';
($timer, $timer2) = 0;
$reactor2->timer(0.025 => sub { shift->stop });
$reactor2->start;
ok !$timer, 'timer was not triggered';
ok $timer2, 'timer was triggered';
($timer, $timer2) = 0;
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $timer, 'timer was triggered';
ok !$timer2, 'timer was not triggered';
($timer, $timer2) = 0;
$reactor2->timer(0.025 => sub { shift->stop });
$reactor2->start;
ok !$timer, 'timer was not triggered';
ok $timer2, 'timer was triggered';

# Error
my $err;
$reactor->on(
  error => sub {
    shift->stop;
    $err = pop;
  }
);
$reactor->timer(0 => sub { die "works!\n" });
$reactor->start;
like $err, qr/works!/, 'right error';

# Detection
is(Mojo::Reactor::Poll->detect, 'Mojo::Reactor::Poll', 'right class');

# Dummy reactor
package Mojo::Reactor::Test;
use Mojo::Base 'Mojo::Reactor::Poll';
$ENV{MOJO_REACTOR} = 'Mojo::Reactor::Test';

package main;

# Detection (env)
is(Mojo::Reactor->detect, 'Mojo::Reactor::Test', 'right class');

# Reactor in control
$ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
is ref Mojo::IOLoop->singleton->reactor, 'Mojo::Reactor::Poll',
  'right object';
ok !Mojo::IOLoop->is_running, 'loop is not running';
$port = Mojo::IOLoop->generate_port;
my ($server_err, $server_running, $client_err, $client_running);
$server = $client = '';
Mojo::IOLoop->server(
  {address => '127.0.0.1', port => $port} => sub {
    my ($loop, $stream) = @_;
    $stream->write('test', sub { shift->write('321') });
    $stream->on(read => sub { $server .= pop });
    $server_running = Mojo::IOLoop->is_running;
    eval { Mojo::IOLoop->start };
    $server_err = $@;
  }
);
Mojo::IOLoop->client(
  {port => $port} => sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset', sub { shift->write('123') });
    $stream->on(read => sub { $client .= pop });
    $client_running = Mojo::IOLoop->is_running;
    eval { Mojo::IOLoop->start };
    $client_err = $@;
  }
);
Mojo::IOLoop->timer(1 => sub { Mojo::IOLoop->singleton->reactor->stop });
Mojo::IOLoop->singleton->reactor->start;
ok !Mojo::IOLoop->is_running, 'loop is not running';
like $server_err, qr/^Mojo::IOLoop already running/, 'right error';
like $client_err, qr/^Mojo::IOLoop already running/, 'right error';
ok $server_running, 'loop is running';
ok $client_running, 'loop is running';
is $server,         'tset123', 'right content';
is $client,         'test321', 'right content';
