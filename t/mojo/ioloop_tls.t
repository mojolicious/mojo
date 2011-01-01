#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll and kqueue
BEGIN { $ENV{MOJO_POLL} = 1 }

use Test::More;
use Mojo::IOLoop;
plan skip_all => 'IO::Socket::SSL 1.34 required for this test!'
  unless Mojo::IOLoop::TLS;
plan tests => 14;

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

# Good client cert
$loop   = Mojo::IOLoop->new;
$port   = Mojo::IOLoop->generate_port;
$server = '';
$client = '';
my $error = '';
$loop->listen(
    port      => $port,
    tls       => 1,
    tls_cert  => 't/certs/server/server.crt',
    tls_key   => 't/certs/server/server.key',
    tls_ca    => 't/certs/ca/ca.crt',
    on_accept => sub {
        shift->write(shift, 'test', sub { shift->write(shift, '321') });
    },
    on_read => sub { $server .= pop },
    on_hup  => sub { $server .= 'hup' },
    on_error => sub { $error = pop },
);
$c = $loop->connect(
    address    => 'localhost',
    port       => $port,
    tls        => 1,
    tls_cert   => 't/certs/client/client.crt',
    tls_key    => 't/certs/client/client.key',
    on_connect => sub {
        shift->write(shift, 'tset', sub { shift->write(shift, '123') });
    },
    on_read => sub { $client .= pop },
    on_hup => sub { shift->stop },
);
$loop->connection_timeout($c => '0.5');
$loop->timer(1 => sub { shift->stop });
$loop->start;
is $server, 'tset123hup', 'right content';
is $client, 'test321',    'right content';
ok !$error, 'no error';

# Fails with bad client cert
$error = '';

$c = $loop->connect(
    address  => 'localhost',
    port     => $port,
    tls      => 1,
    tls_cert => 't/certs/badcert/badcert.key',
    tls_key  => 't/certs/badcert/badcert.crt',
    on_error => sub { $error = pop },
);
$loop->connection_timeout($c => '0.5');
$loop->timer(1 => sub { shift->stop });
$loop->start;
is $error,
  "SSL connect accept failed because of handshake problemserror:00000000:lib(0):func(0):reason(0)\n",
  'handshake error';

# Fails with good client cert and callback refusal
$loop  = Mojo::IOLoop->new;
$port  = Mojo::IOLoop->generate_port;
$error = '';
my $client_error = '';

$loop->listen(
    port       => $port,
    tls        => 1,
    tls_cert   => 't/certs/server/server.crt',
    tls_key    => 't/certs/server/server.key',
    tls_ca     => 't/certs/ca/ca.crt',
    tls_verify => sub { return 0 },
    on_error   => sub { $error = pop },
);
$c = $loop->connect(
    address  => 'localhost',
    port     => $port,
    tls      => 1,
    tls_cert => 't/certs/client/client.crt',
    tls_key  => 't/certs/client/client.key',
    on_error => sub { $client_error = pop }
);
$loop->connection_timeout($c => '0.5');
$loop->timer(1 => sub { shift->stop });
$loop->start;
ok $error,        'server manual handshake error';
ok $client_error, 'client manual handshake error';

# Good client cert with callback acceptance
$loop   = Mojo::IOLoop->new;
$port   = Mojo::IOLoop->generate_port;
$server = '';
$client = '';
$loop->listen(
    port       => $port,
    tls        => 1,
    tls_cert   => 't/certs/server/server.crt',
    tls_key    => 't/certs/server/server.key',
    tls_ca     => 't/certs/ca/ca.crt',
    tls_verify => sub { return 1 },
    on_accept  => sub {
        shift->write(shift, 'test', sub { shift->write(shift, '321') });
    },
    on_read => sub { $server .= pop },
    on_hup  => sub { $server .= 'hup' },
    on_error => sub { $error = pop }
);
$c = $loop->connect(
    address    => 'localhost',
    port       => $port,
    tls        => 1,
    tls_cert   => 't/certs/client/client.crt',
    tls_key    => 't/certs/client/client.key',
    on_connect => sub {
        shift->write(shift, 'tset', sub { shift->write(shift, '123') });
    },
    on_read => sub { $client .= pop },
    on_hup => sub { shift->stop },
);
$loop->connection_timeout($c => '0.5');
$loop->timer(1 => sub { shift->stop });
$loop->start;
is $server, 'tset123hup', 'right content';
is $client, 'test321',    'right content';

# Fails with no client cert
$client_error = '';
$error        = '';

$c = $loop->connect(
    address  => 'localhost',
    port     => $port,
    tls      => 1,
    on_error => sub { $client_error = pop }
);
$loop->start;
like $error, qr/^SSL accept attempt failed with unknown error/,
  'server fails w/o client cert';
like $client_error,
  qr/^SSL connect attempt failed because of handshake problems/,
  'client fails w/o client cert';

# Fails with bad CA
$loop         = Mojo::IOLoop->new;
$port         = Mojo::IOLoop->generate_port;
$error        = '';
$client_error = '';
$loop->listen(
    port      => $port,
    tls       => 1,
    tls_cert  => 't/certs/server/server.crt',
    tls_key   => 't/certs/server/server.key',
    tls_ca    => 'no certs',
    on_accept => sub {
        shift->write(shift, 'test', sub { shift->write(shift, '321') });
    },
    on_error => sub { $error = pop }
);
$c = $loop->connect(
    address  => 'localhost',
    port     => $port,
    tls      => 1,
    tls_cert => 't/certs/client/client.crt',
    tls_key  => 't/certs/client/client.key',
    on_error => sub { $client_error = pop }
);
$loop->connection_timeout($c => '0.5');
$loop->timer(1 => sub { shift->stop });
$loop->start;
ok $error,        'server fails missing ca';
ok $client_error, 'client fails missing ca';
