#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll and kqueue
BEGIN { $ENV{MOJO_POLL} = 1 }

use Test::More;
use Mojo::IOLoop;
plan skip_all => 'IO::Socket::SSL 1.33 required for this test!'
  unless Mojo::IOLoop::TLS;
plan skip_all => 'Windows is too fragile for this test!' if $^O eq 'MSWin32';
plan tests => 2;

# To the panic room!
# We don't have a panic room.
# To the panic room store!
my $loop   = Mojo::IOLoop->new;
my $port   = Mojo::IOLoop->generate_port;
my $server = '';
my $client = '';
$loop->listen(
    port      => $port,
    tls       => 1,
    on_accept => sub {
        shift->write(shift, 'test', sub { shift->write(shift, '321') });
    },
    on_read => sub { $server .= pop },
    on_hup  => sub { $server .= 'hup' }
);
my $c = $loop->connect(
    address    => 'localhost',
    port       => $port,
    tls        => 1,
    on_connect => sub {
        shift->write(shift, 'tset', sub { shift->write(shift, '123') });
    },
    on_read => sub { $client .= pop },
    on_hup => sub { shift->stop }
);
$loop->connection_timeout($c => '0.5');
$loop->start;
is $server, 'tset123hup', 'right content';
is $client, 'test321',    'right content';
