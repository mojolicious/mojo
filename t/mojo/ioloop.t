#!/usr/bin/env perl

use strict;
use warnings;

# Disable IPv6, epoll and kqueue
BEGIN { $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1 }

use Test::More tests => 11;

use_ok 'Mojo::IOLoop';

use IO::Handle;

# "Marge, you being a cop makes you the man!
#  Which makes me the woman, and I have no interest in that,
#  besides occasionally wearing the underwear,
#  which as we discussed, is strictly a comfort thing."
my $loop = Mojo::IOLoop->new;

# Readonly handle
my $ro = IO::Handle->new;
$ro->fdopen(fileno(DATA), 'r');
my $error;
$loop->connect(
  handle   => $ro,
  on_read  => sub { },
  on_error => sub { $error = pop }
);

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

# Idle callback
my $idle = 0;
$loop->idle(sub { $idle++ });

# Another tick
$loop->one_tick;

# Ticks
ok $ticks > 2, 'more than two ticks';

# Idle callback
is $idle, 1, 'one idle event';

# Run again without first tick event handler
my $before = $ticks;
my $after  = 0;
$loop->recurring(0 => sub { $after++ });
$loop->drop($id);
$loop->timer(1 => sub { shift->stop });
$loop->start;
ok $after > 2, 'more than two ticks';
is $ticks, $before, 'no additional ticks';


# Recurring timer
my $count = 0;
$loop->recurring(0.5 => sub { $count++ });
$loop->timer(3 => sub { shift->stop });
$loop->start;
ok $count > 4, 'more than four recurring events';

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

# Readonly handle
is $error, undef, 'no error';

# Idle
$idle = 0;
Mojo::IOLoop->idle(sub { Mojo::IOLoop->stop if $idle++ });
Mojo::IOLoop->start;
is $idle, 2, 'two idle ticks';

__DATA__
