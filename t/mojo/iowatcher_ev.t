#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour and IPv6
BEGIN { $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More;

# "Oh well. At least we'll die doing what we love: inhaling molten rock."
plan skip_all => 'set TEST_EV to enable this test (developer only!)'
  unless $ENV{TEST_EV};
plan skip_all => 'EV required for this test!' unless eval 'use EV; 1';
plan tests => 50;

use_ok 'Mojo::IOWatcher::EV';

use IO::Socket::INET;
use Mojo::IOLoop;

# Listen
my $port   = Mojo::IOLoop->generate_port;
my $listen = IO::Socket::INET->new(
  Listen    => 5,
  LocalAddr => '127.0.0.1',
  LocalPort => $port,
  Proto     => 'tcp'
);
my $watcher = Mojo::IOWatcher::EV->new;
isa_ok $watcher, 'Mojo::IOWatcher::EV', 'right object';
my ($readable, $writable);
$watcher->add(
  $listen,
  on_readable => sub { $readable++ },
  on_writable => sub { $writable++ }
);
$watcher->one_tick(0);
is $readable, undef, 'handle is not readable';
is $writable, undef, 'handle is not writable';

# Connect
my $client =
  IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port);
$watcher->one_tick(1);
ok $readable, 'handle is readable';
ok !$writable, 'handle is not writable';

# Accept
my $server = $listen->accept;
$watcher = undef;
$watcher = Mojo::IOWatcher::EV->new;
isa_ok $watcher, 'Mojo::IOWatcher::EV', 'right object';
$readable = $writable = undef;
$watcher->add(
  $client,
  on_readable => sub { $readable++ },
  on_writable => sub { $writable++ }
);
$watcher->one_tick(0);
is $readable, undef, 'handle is not readable';
is $writable, 1,     'handle is writable';
print $client "hello!\n";
sleep 1;
$watcher = undef;
$watcher = Mojo::IOWatcher::EV->new;
isa_ok $watcher, 'Mojo::IOWatcher::EV', 'right object';
$readable = $writable = undef;
$watcher->add(
  $server,
  on_readable => sub { $readable++ },
  on_writable => sub { $writable++ }
);
$watcher->not_writing($server);
$watcher->one_tick(0);
is $readable, 1,     'handle is readable';
is $writable, undef, 'handle is not writable';
$watcher->writing($server);
$watcher->one_tick(0);
is $readable, 2, 'handle is readable';
is $writable, 1, 'handle is writable';
$watcher->not_writing($server);
$watcher->one_tick(0);
is $readable, 3, 'handle is readable';
is $writable, 1, 'handle is not writable';
$readable = $writable = undef;
$watcher->add(
  $server,
  on_readable => sub { $readable++ },
  on_writable => sub { $writable++ }
);
$watcher->one_tick(0);
is $readable, 1, 'handle is readable';
is $writable, 1, 'handle is writable';

# Timers
my ($timer, $recurring);
$watcher->timer(0 => sub { $timer++ });
$watcher->cancel($watcher->timer(0 => sub { $timer++ }));
my $id = $watcher->recurring(0 => sub { $recurring++ });
$watcher->one_tick(0);
is $readable,  2, 'handle is readable again';
is $writable,  2, 'handle is writable again';
is $timer,     1, 'timer was triggered';
is $recurring, 1, 'recurring was triggered';
$watcher->one_tick(0);
is $readable,  3, 'handle is readable again';
is $writable,  3, 'handle is writable again';
is $timer,     1, 'timer was not triggered';
is $recurring, 2, 'recurring was triggered again';
$watcher->one_tick(0);
is $readable,  4, 'handle is readable again';
is $writable,  4, 'handle is writable again';
is $timer,     1, 'timer was not triggered';
is $recurring, 3, 'recurring was not triggered';
$watcher->one_tick(0);
is $readable,  5, 'handle is readable again';
is $writable,  5, 'handle is writable again';
is $timer,     1, 'timer was not triggered';
is $recurring, 4, 'recurring was triggered again';
$watcher->cancel($id);
$watcher->one_tick(0);
is $readable,  6, 'handle is readable again';
is $writable,  6, 'handle is writable again';
is $timer,     1, 'timer was not triggered';
is $recurring, 4, 'recurring was not triggered again';

# Reset
$watcher = undef;
$watcher = Mojo::IOWatcher::EV->new;
isa_ok $watcher, 'Mojo::IOWatcher::EV', 'right object';
$watcher->one_tick(0);
is $readable, 6, 'io event was not triggered again';
is $writable, 6, 'io event was not triggered again';
my $watcher2 = Mojo::IOWatcher::EV->new;
isa_ok $watcher2, 'Mojo::IOWatcher', 'right object';

# Parallel loops
$timer = 0;
$watcher->recurring(0 => sub { $timer++ });
my $timer2 = 0;
$watcher2->recurring(0 => sub { $timer2++ });
$watcher->one_tick(0);
is $timer,  1, 'timer was triggered';
is $timer2, 0, 'timer was not triggered';
$watcher2->one_tick(0);
is $timer,  1, 'timer was not triggered';
is $timer2, 1, 'timer was triggered';
$watcher->one_tick(0);
is $timer,  2, 'timer was triggered';
is $timer2, 1, 'timer was not triggered';
$watcher2->one_tick(0);
is $timer,  2, 'timer was not triggered';
is $timer2, 2, 'timer was triggered';
