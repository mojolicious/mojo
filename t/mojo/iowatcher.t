use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 55;

# "I don't mind being called a liar when I'm lying, or about to lie,
#  or just finished lying, but NOT WHEN I'M TELLING THE TRUTH."
use IO::Socket::INET;
use Mojo::IOLoop;

use_ok 'Mojo::IOWatcher';

# Listen
my $port   = Mojo::IOLoop->generate_port;
my $listen = IO::Socket::INET->new(
  Listen    => 5,
  LocalAddr => '127.0.0.1',
  LocalPort => $port,
  Proto     => 'tcp'
);
my $watcher = Mojo::IOWatcher->new;
isa_ok $watcher, 'Mojo::IOWatcher', 'right object';
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
$watcher = undef;
$watcher = Mojo::IOWatcher->new;
isa_ok $watcher, 'Mojo::IOWatcher', 'right object';
($readable, $writable) = undef;
$watcher->io($client => sub { pop() ? $writable++ : $readable++ });
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, undef, 'handle is not readable';
is $writable, 1,     'handle is writable';
print $client "hello!\n";
sleep 1;
$watcher = undef;
$watcher = Mojo::IOWatcher->new;
isa_ok $watcher, 'Mojo::IOWatcher', 'right object';
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
$watcher = undef;
$watcher = Mojo::IOWatcher->new;
isa_ok $watcher, 'Mojo::IOWatcher', 'right object';
$watcher->timer(0 => sub { shift->stop });
$watcher->start;
is $readable, 6, 'io event was not triggered again';
is $writable, 6, 'io event was not triggered again';
my $watcher2 = Mojo::IOWatcher->new;
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
$watcher = Mojo::IOWatcher->new;
my $err;
$watcher->on(
  error => sub {
    shift->stop;
    $err = pop;
  }
);
$watcher->timer(0 => sub { die "works!\n" });
$watcher->start;
like $err, qr/works!/, 'right error';
