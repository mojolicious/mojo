#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More;
use Mojo::IOLoop;
plan skip_all => 'IO::Socket::SSL 1.33 required for this test!'
  unless Mojo::IOLoop::TLS;
plan tests => 2;

# To the panic room!
# We don't have a panic room.
# To the panic room store!
my $loop   = Mojo::IOLoop->new;
my $port   = Mojo::IOLoop->generate_port;
my $server = '';
my $client = '';
my $l      = $loop->listen(
    port      => $port,
    tls       => 1,
    on_accept => sub { shift->write(shift, 'test') },
    on_read   => sub { $server .= pop }
);
my $c = $loop->connect(
    address    => 'localhost',
    port       => $port,
    tls        => 1,
    on_connect => sub { shift->write(shift, 'tset') },
    on_read    => sub { $client .= pop },
    on_hup => sub { shift->stop }
);
$loop->connection_timeout($c => '0.5');
$loop->start;
is $server, 'tset', 'right content';
is $client, 'test', 'right content';
