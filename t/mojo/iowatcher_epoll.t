#!/usr/bin/env perl

use strict;
use warnings;

# Disable Bonjour and IPv6
BEGIN { $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More;

# "Have you ever seen that Blue Man Group? Total ripoff of the Smurfs.
#  And the Smurfs, well, they SUCK."
plan skip_all => 'set TEST_EPOLL to enable this test (developer only!)'
  unless $ENV{TEST_EPOLL};
plan skip_all => 'IO::Epoll 0.02 required for this test!'
  unless eval 'use IO::Epoll 0.02; 1';
plan tests => 25;

use_ok 'Mojo::IOWatcher::Epoll';

use IO::Socket::INET;
use Mojo::IOLoop;

# Listen
my $port    = Mojo::IOLoop->generate_port;
my $listen  = IO::Socket::INET->new(Listen => 1, LocalPort => $port);
my $watcher = Mojo::IOWatcher::Epoll->new;
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
$watcher->one_tick(0);
is $readable, 1,     'handle is readable';
is $writable, undef, 'handle is not writable';

# Accept
my $server = $listen->accept;
$watcher = Mojo::IOWatcher::Epoll->new;
$readable = $writable = undef;
$watcher->add(
  $client,
  on_readable => sub { $readable++ },
  on_writable => sub { $writable++ }
);
$watcher->one_tick(0);
is $readable, undef, 'handle is not readable';
is $writable, 1,     'handle is writable';
print $client 'hello!';
$watcher = Mojo::IOWatcher::Epoll->new;
$readable = $writable = undef;
$watcher->add(
  $server,
  on_readable => sub { $readable++ },
  on_writable => sub { $writable++ }
);
$watcher->watch(0);
is $readable, 1, 'handle is readable';
is $writable, 1, 'handle is writable';

# Timers
my ($timer, $recurring);
$watcher->timer(0 => sub { $timer++ });
$watcher->recurring(0 => sub { $recurring++ });
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
$watcher->watch(0);
is $readable,  4, 'handle is readable again';
is $writable,  4, 'handle is writable again';
is $timer,     1, 'timer was not triggered';
is $recurring, 2, 'recurring was not triggered';
$watcher->one_tick(0);
is $readable,  5, 'handle is readable again';
is $writable,  5, 'handle is writable again';
is $timer,     1, 'timer was not triggered';
is $recurring, 3, 'recurring was triggered again';
