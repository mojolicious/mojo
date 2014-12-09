use Mojo::Base -strict;

use Test::More;

plan skip_all => 'set TEST_EV to enable this test (developer only!)'
  unless $ENV{TEST_EV};
plan skip_all => 'EV 4.0 required for this test!' unless eval 'use EV 4.0; 1';

use IO::Socket::INET;

# Instantiation
use_ok 'Mojo::Reactor::EV';
my $reactor = Mojo::Reactor::EV->new;
is ref $reactor, 'Mojo::Reactor::EV', 'right object';
is ref Mojo::Reactor::EV->new, 'Mojo::Reactor::Poll', 'right object';
undef $reactor;
is ref Mojo::Reactor::EV->new, 'Mojo::Reactor::EV', 'right object';
use_ok 'Mojo::IOLoop';
$reactor = Mojo::IOLoop->singleton->reactor;
is ref $reactor, 'Mojo::Reactor::EV', 'right object';

# Make sure it stops automatically when not watching for events
my $triggered;
Mojo::IOLoop->next_tick(sub { $triggered++ });
Mojo::IOLoop->start;
ok $triggered, 'reactor waited for one event';
my $time = time;
Mojo::IOLoop->start;
Mojo::IOLoop->one_tick;
ok time < ($time + 10), 'stopped automatically';

# Listen
my $listen = IO::Socket::INET->new(Listen => 5, LocalAddr => '127.0.0.1');
my $port = $listen->sockport;
my ($readable, $writable);
$reactor->io($listen => sub { pop() ? $writable++ : $readable++ })
  ->watch($listen, 0, 0)->watch($listen, 1, 1);
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok !$readable, 'handle is not readable';
ok !$writable, 'handle is not writable';
ok !$reactor->is_readable($listen), 'handle is not readable';

# Connect
my $client = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port);
$reactor->timer(1 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable';
ok !$writable, 'handle is not writable';
ok $reactor->is_readable($listen), 'handle is readable';

# Accept
my $server = $listen->accept;
$reactor->remove($listen);
($readable, $writable) = ();
$reactor->io($client => sub { pop() ? $writable++ : $readable++ });
$reactor->again($reactor->timer(0.025 => sub { shift->stop }));
$reactor->start;
ok !$readable, 'handle is not readable';
ok $writable, 'handle is writable';
print $client "hello!\n";
sleep 1;
$reactor->remove($client);
($readable, $writable) = ();
$reactor->io($server => sub { pop() ? $writable++ : $readable++ });
$reactor->watch($server, 1, 0);
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable';
ok !$writable, 'handle is not writable';
($readable, $writable) = ();
$reactor->watch($server, 1, 1);
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable';
ok $writable, 'handle is writable';
($readable, $writable) = ();
$reactor->watch($server, 0, 0);
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok !$readable, 'handle is not readable';
ok !$writable, 'handle is not writable';
($readable, $writable) = ();
$reactor->watch($server, 1, 0);
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable';
ok !$writable, 'handle is not writable';
($readable, $writable) = ();
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
($readable, $writable) = ();
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable,  'handle is readable again';
ok $writable,  'handle is writable again';
ok $timer,     'timer was triggered';
ok $recurring, 'recurring was triggered';
my $done;
($readable, $writable, $timer, $recurring) = ();
$reactor->timer(0.025 => sub { $done = shift->is_running });
$reactor->one_tick while !$done;
ok $readable, 'handle is readable again';
ok $writable, 'handle is writable again';
ok !$timer, 'timer was not triggered';
ok $recurring, 'recurring was triggered again';
($readable, $writable, $timer, $recurring) = ();
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable again';
ok $writable, 'handle is writable again';
ok !$timer, 'timer was not triggered';
ok $recurring, 'recurring was triggered again';
$reactor->remove($id);
($readable, $writable, $timer, $recurring) = ();
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $readable, 'handle is readable again';
ok $writable, 'handle is writable again';
ok !$timer,     'timer was not triggered';
ok !$recurring, 'recurring was not triggered again';
($readable, $writable, $timer, $recurring) = ();
$id = $reactor->recurring(0 => sub { $recurring++ });
is $reactor->next_tick(sub { shift->stop }), undef, 'returned undef';
$reactor->start;
ok $readable, 'handle is readable again';
ok $writable, 'handle is writable again';
ok !$timer, 'timer was not triggered';
ok $recurring, 'recurring was triggered again';

# Reset
$reactor->reset;
($readable, $writable, $recurring) = ();
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok !$readable,  'io event was not triggered again';
ok !$writable,  'io event was not triggered again';
ok !$recurring, 'recurring was not triggered again';
my $reactor2 = Mojo::Reactor::EV->new;
is ref $reactor2, 'Mojo::Reactor::Poll', 'right object';

# Reset while watchers are active
$writable = undef;
$reactor->io($_ => sub { ++$writable and shift->reset })->watch($_, 0, 1)
  for $client, $server;
$reactor->start;
is $writable, 1, 'only one handle was writable';

# Concurrent reactors
$timer = 0;
$reactor->recurring(0 => sub { $timer++ });
my $timer2;
$reactor2->recurring(0 => sub { $timer2++ });
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $timer, 'timer was triggered';
ok !$timer2, 'timer was not triggered';
$timer = $timer2 = 0;
$reactor2->timer(0.025 => sub { shift->stop });
$reactor2->start;
ok !$timer, 'timer was not triggered';
ok $timer2, 'timer was triggered';
$timer = $timer2 = 0;
$reactor->timer(0.025 => sub { shift->stop });
$reactor->start;
ok $timer, 'timer was triggered';
ok !$timer2, 'timer was not triggered';
$timer = $timer2 = 0;
$reactor2->timer(0.025 => sub { shift->stop });
$reactor2->start;
ok !$timer, 'timer was not triggered';
ok $timer2, 'timer was triggered';

# Restart timer
my ($single, $pair, $one, $two, $last);
$reactor->timer(0.025 => sub { $single++ });
$one = $reactor->timer(
  0.025 => sub {
    my $reactor = shift;
    $last++ if $single && $pair;
    $pair++ ? $reactor->stop : $reactor->again($two);
  }
);
$two = $reactor->timer(
  0.025 => sub {
    my $reactor = shift;
    $last++ if $single && $pair;
    $pair++ ? $reactor->stop : $reactor->again($one);
  }
);
$reactor->start;
is $pair, 2, 'timer pair was triggered';
ok $single, 'single timer was triggered';
ok $last,   'timers were triggered in the right order';

# Error
my $err;
$reactor->unsubscribe('error')->on(
  error => sub {
    shift->stop;
    $err = pop;
  }
);
$reactor->timer(0 => sub { die "works!\n" });
$reactor->start;
like $err, qr/works!/, 'right error';

# Recursion
$timer   = undef;
$reactor = $reactor->new;
$reactor->timer(0 => sub { ++$timer and shift->one_tick });
$reactor->one_tick;
is $timer, 1, 'timer was triggered once';

# Detection
is(Mojo::Reactor->detect, 'Mojo::Reactor::EV', 'right class');

# Dummy reactor
package Mojo::Reactor::Test;
use Mojo::Base 'Mojo::Reactor::Poll';
$ENV{MOJO_REACTOR} = 'Mojo::Reactor::Test';

package main;

# Detection (env)
is(Mojo::Reactor->detect, 'Mojo::Reactor::Test', 'right class');

# EV in control
$ENV{MOJO_REACTOR} = 'Mojo::Reactor::EV';
is ref Mojo::IOLoop->singleton->reactor, 'Mojo::Reactor::EV', 'right object';
ok !Mojo::IOLoop->is_running, 'loop is not running';
my ($buffer, $server_err, $server_running, $client_err, $client_running);
$id = Mojo::IOLoop->server(
  {address => '127.0.0.1'} => sub {
    my ($loop, $stream) = @_;
    $stream->write('test' => sub { shift->write('321') });
    $server_running = Mojo::IOLoop->is_running;
    eval { Mojo::IOLoop->start };
    $server_err = $@;
  }
);
$port = Mojo::IOLoop->acceptor($id)->port;
Mojo::IOLoop->client(
  {port => $port} => sub {
    my ($loop, $err, $stream) = @_;
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;
        $buffer .= $chunk;
        return unless $buffer eq 'test321';
        EV::break(EV::BREAK_ALL());
      }
    );
    $client_running = Mojo::IOLoop->is_running;
    eval { Mojo::IOLoop->start };
    $client_err = $@;
  }
);
EV::run();
ok !Mojo::IOLoop->is_running, 'loop is not running';
like $server_err, qr/^Mojo::IOLoop already running/, 'right error';
like $client_err, qr/^Mojo::IOLoop already running/, 'right error';
ok $server_running, 'loop is running';
ok $client_running, 'loop is running';

done_testing();
