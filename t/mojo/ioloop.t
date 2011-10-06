#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 15;

# "Marge, you being a cop makes you the man!
#  Which makes me the woman, and I have no interest in that,
#  besides occasionally wearing the underwear,
#  which as we discussed, is strictly a comfort thing."
use_ok 'Mojo::IOLoop';

# Custom watcher
package MyWatcher;
use Mojo::Base 'Mojo::IOWatcher';

package main;

# Watcher detection
$ENV{MOJO_IOWATCHER} = 'MyWatcherDoesNotExist';
my $loop = Mojo::IOLoop->new;
is ref $loop->iowatcher, 'Mojo::IOWatcher', 'right class';
$ENV{MOJO_IOWATCHER} = 'MyWatcher';
$loop = Mojo::IOLoop->new;
is ref $loop->iowatcher, 'MyWatcher', 'right class';

# Double start
my $error;
Mojo::IOLoop->defer(
  sub {
    eval { Mojo::IOLoop->start };
    $error = $@;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
like $error, qr/^Mojo::IOLoop already running/, 'right error';

# Ticks
my $ticks = 0;
my $id = $loop->recurring(0 => sub { $ticks++ });

# Timer
my $flag = 0;
my $flag2;
$loop->timer(
  1 => sub {
    my $self = shift;
    $self->timer(
      1 => sub {
        shift->stop;
        $flag2 = $flag;
      }
    );
    $flag = 23;
  }
);

# HiRes timer
my $hiresflag = 0;
$loop->timer(0.25 => sub { $hiresflag = 42 });

# Start
$loop->start;

# Timer
is $flag, 23, 'recursive timer works';

# HiRes timer
is $hiresflag, 42, 'hires timer';

# Another tick
$loop->one_tick;

# Ticks
ok $ticks > 2, 'more than two ticks';

# Run again without first tick event handler
my $before = $ticks;
my $after  = 0;
$loop->recurring(0 => sub { $after++ });
$loop->drop($id);
$loop->timer(1 => sub { shift->stop });
$loop->start;
$loop->one_tick;
ok $after > 1, 'more than one tick';
is $ticks, $before, 'no additional ticks';

# Recurring timer
my $count = 0;
$loop->recurring(0.5 => sub { $count++ });
$loop->timer(3 => sub { shift->stop });
$loop->start;
$loop->one_tick;
ok $count > 3, 'more than three recurring events';

# Handle
my $port = Mojo::IOLoop->generate_port;
my $handle;
$loop->listen(
  port      => $port,
  on_accept => sub {
    my $self = shift;
    $handle = $self->handle(pop);
    $self->stop;
  },
  on_read  => sub { },
  on_error => sub { }
);
$loop->connect(
  address  => 'localhost',
  port     => $port,
  on_read  => sub { },
  on_error => sub { }
);
$loop->start;
isa_ok $handle, 'IO::Socket', 'right reference';

# Dropped listen socket
$port  = Mojo::IOLoop->generate_port;
$id    = $loop->listen(port => $port);
$error = undef;
my $connected;
$loop->connect(
  address    => 'localhost',
  port       => $port,
  on_connect => sub {
    my $loop = shift;
    $loop->drop($id);
    $loop->stop;
    $connected = 1;
  },
  on_error => sub {
    shift->stop;
    $error = pop;
  }
);
$loop->start;
ok $connected, 'connected';
ok !$error, 'no error';
$connected = $error = undef;
$loop->connect(
  address    => 'localhost',
  port       => $port,
  on_connect => sub {
    shift->stop;
    $connected = 1;
  },
  on_error => sub {
    shift->stop;
    $error = pop;
  }
);
$loop->start;
ok !$connected, 'not connected';
ok $error, 'has error';
