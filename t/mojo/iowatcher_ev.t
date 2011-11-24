#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour and IPv6
BEGIN { $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More;

plan skip_all => 'set TEST_EV to enable this test (developer only!)'
  unless $ENV{TEST_EV};
plan skip_all => 'EV 4.0 required for this test!' unless eval 'use EV 4.0; 1';
plan tests => 53;

use IO::Socket::INET;
use Mojo::IOLoop;

# "Oh well. At least we'll die doing what we love: inhaling molten rock."
use_ok 'Mojo::IOWatcher::EV';

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
$watcher->watch($listen, sub { $readable++ }, sub { $writable++ });
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, undef, 'handle is not readable';
is $writable, undef, 'handle is not writable';

# Connect
my $client =
  IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port);
$watcher->timer(1 => sub { shift->stop });
$watcher->start;
ok $readable, 'handle is readable';
ok !$writable, 'handle is not writable';

# Accept
my $server = $listen->accept;
$watcher = undef;
$watcher = Mojo::IOWatcher::EV->new;
isa_ok $watcher, 'Mojo::IOWatcher::EV', 'right object';
($readable, $writable) = undef;
$watcher->watch($client, sub { $readable++ }, sub { $writable++ });
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, undef, 'handle is not readable';
is $writable, 1,     'handle is writable';
print $client "hello!\n";
sleep 1;
$watcher = undef;
$watcher = Mojo::IOWatcher::EV->new;
isa_ok $watcher, 'Mojo::IOWatcher::EV', 'right object';
($readable, $writable) = undef;
$watcher->watch($server, sub { $readable++ }, sub { $writable++ });
$watcher->change($server, 1, 0);
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, 1,     'handle is readable';
is $writable, undef, 'handle is not writable';
$watcher->change($server, 1, 1);
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, 2, 'handle is readable';
is $writable, 1, 'handle is writable';
$watcher->change($server, 0, 0);
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, 2, 'handle is not readable';
is $writable, 1, 'handle is not writable';
$watcher->change($server, 1, 0);
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, 3, 'handle is readable';
is $writable, 1, 'handle is not writable';
($readable, $writable) = undef;
$watcher->watch($server, sub { $readable++ }, sub { $writable++ });
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, 1, 'handle is readable';
is $writable, 1, 'handle is writable';

# Timers
my ($timer, $recurring);
$watcher->timer(0 => sub { $timer++ });
$watcher->drop_timer($watcher->timer(0 => sub { $timer++ }));
my $id = $watcher->recurring(0 => sub { $recurring++ });
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable,  2, 'handle is readable again';
is $writable,  2, 'handle is writable again';
is $timer,     1, 'timer was triggered';
is $recurring, 1, 'recurring was triggered';
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable,  3, 'handle is readable again';
is $writable,  3, 'handle is writable again';
is $timer,     1, 'timer was not triggered';
is $recurring, 2, 'recurring was triggered again';
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable,  4, 'handle is readable again';
is $writable,  4, 'handle is writable again';
is $timer,     1, 'timer was not triggered';
is $recurring, 3, 'recurring was not triggered';
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable,  5, 'handle is readable again';
is $writable,  5, 'handle is writable again';
is $timer,     1, 'timer was not triggered';
is $recurring, 4, 'recurring was triggered again';
$watcher->drop_timer($id);
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable,  6, 'handle is readable again';
is $writable,  6, 'handle is writable again';
is $timer,     1, 'timer was not triggered';
is $recurring, 4, 'recurring was not triggered again';

# Reset
$watcher = undef;
$watcher = Mojo::IOWatcher::EV->new;
isa_ok $watcher, 'Mojo::IOWatcher::EV', 'right object';
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, 6, 'io event was not triggered again';
is $writable, 6, 'io event was not triggered again';
my $watcher2 = Mojo::IOWatcher::EV->new;
isa_ok $watcher2, 'Mojo::IOWatcher', 'right object';

# Parallel loops
$timer = 0;
$watcher->recurring(0 => sub { $timer++ });
my $timer2 = 0;
$watcher2->recurring(0 => sub { $timer2++ });
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $timer,  1, 'timer was triggered';
is $timer2, 0, 'timer was not triggered';
$watcher2->timer(0 => sub { shift->stop });
$watcher2->start;
is $timer,  1, 'timer was not triggered';
is $timer2, 1, 'timer was triggered';
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $timer,  2, 'timer was triggered';
is $timer2, 1, 'timer was not triggered';
$watcher2->timer(0 => sub { shift->stop });
$watcher2->start;
is $timer,  2, 'timer was not triggered';
is $timer2, 2, 'timer was triggered';

# Error
$watcher = Mojo::IOWatcher::EV->new;
my $error;
$watcher->on(
  error => sub {
    shift->stop;
    $error = pop;
  }
);
$watcher->timer(0 => sub { die "works!\n" });
$watcher->start;
like $error, qr/works!/, 'right error';
