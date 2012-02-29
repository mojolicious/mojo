use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 66;

# "I don't mind being called a liar when I'm lying, or about to lie,
#  or just finished lying, but NOT WHEN I'M TELLING THE TRUTH."
use IO::Socket::INET;

use_ok 'Mojo::IOWatcher';

# Instantiation
my $watcher = Mojo::IOWatcher->new;
is ref $watcher, 'Mojo::IOWatcher', 'right object';
is ref Mojo::IOWatcher->new, 'Mojo::IOWatcher', 'right object';
undef $watcher;
is ref Mojo::IOWatcher->new, 'Mojo::IOWatcher', 'right object';
require Mojo::IOLoop;
$watcher = Mojo::IOLoop->singleton->iowatcher;
is ref $watcher, 'Mojo::IOWatcher', 'right object';

# Make sure it stops automatically without watchers
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
$watcher->io($listen => sub { pop() ? $writable++ : $readable++ })
  ->watch($listen, 0, 0)->watch($listen, 1, 1);
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, undef, 'handle is not readable';
is $writable, undef, 'handle is not writable';
ok !$watcher->is_readable($listen), 'handle is not readable';

# Connect
my $client =
  IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port);
$watcher->timer(1 => sub { shift->stop });
$watcher->start;
ok $readable, 'handle is readable';
ok !$writable, 'handle is not writable';
ok $watcher->is_readable($listen), 'handle is readable';

# Accept
my $server = $listen->accept;
$watcher->drop($listen);
($readable, $writable) = undef;
$watcher->io($client => sub { pop() ? $writable++ : $readable++ });
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, undef, 'handle is not readable';
is $writable, 1,     'handle is writable';
print $client "hello!\n";
sleep 1;
$watcher->drop($client);
($readable, $writable) = undef;
$watcher->io($server => sub { pop() ? $writable++ : $readable++ });
$watcher->watch($server, 1, 0);
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, 1,     'handle is readable';
is $writable, undef, 'handle is not writable';
$watcher->watch($server, 1, 1);
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, 2, 'handle is readable';
is $writable, 1, 'handle is writable';
$watcher->watch($server, 0, 0);
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, 2, 'handle is not readable';
is $writable, 1, 'handle is not writable';
$watcher->watch($server, 1, 0);
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, 3, 'handle is readable';
is $writable, 1, 'handle is not writable';
($readable, $writable) = undef;
$watcher->io($server => sub { pop() ? $writable++ : $readable++ });
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, 1, 'handle is readable';
is $writable, 1, 'handle is writable';

# Timers
my ($timer, $recurring);
$watcher->timer(0 => sub { $timer++ });
$watcher->drop($watcher->timer(0 => sub { $timer++ }));
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
$watcher->drop($id);
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable,  6, 'handle is readable again';
is $writable,  6, 'handle is writable again';
is $timer,     1, 'timer was not triggered';
is $recurring, 4, 'recurring was not triggered again';

# Reset
$watcher->drop($id);
$watcher->drop($server);
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, 6, 'io event was not triggered again';
is $writable, 6, 'io event was not triggered again';
my $watcher2 = Mojo::IOWatcher->new;
is ref $watcher2, 'Mojo::IOWatcher', 'right object';

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
my $err;
$watcher->unsubscribe('error')->on(
  error => sub {
    shift->stop;
    $err = pop;
  }
);
$watcher->timer(0 => sub { die "works!\n" });
$watcher->start;
like $err, qr/works!/, 'right error';

# Detection
is(Mojo::IOWatcher->detect, 'Mojo::IOWatcher', 'right class');

# Dummy watcher
package Mojo::IOWatcher::Test;
use Mojo::Base 'Mojo::IOWatcher';
$ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher::Test';

package main;

# Detection (env)
is(Mojo::IOWatcher->detect, 'Mojo::IOWatcher::Test', 'right class');

# Watcher in control
$ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
is ref Mojo::IOLoop->singleton->iowatcher, 'Mojo::IOWatcher', 'right object';
ok !Mojo::IOLoop->is_running, 'loop is not running';
$port = Mojo::IOLoop->generate_port;
my ($server_err, $server_running, $client_err, $client_running);
($server, $client) = '';
Mojo::IOLoop->server(
  {port => $port} => sub {
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
Mojo::IOLoop->timer(1 => sub { Mojo::IOLoop->singleton->iowatcher->stop });
Mojo::IOLoop->singleton->iowatcher->start;
ok !Mojo::IOLoop->is_running, 'loop is not running';
like $server_err, qr/^Mojo::IOLoop already running/, 'right error';
like $client_err, qr/^Mojo::IOLoop already running/, 'right error';
ok $server_running, 'loop is running';
ok $client_running, 'loop is running';
is $server,         'tset123', 'right content';
is $client,         'test321', 'right content';
