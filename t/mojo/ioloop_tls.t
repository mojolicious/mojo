use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

# To regenerate all required certificates run these commands (18.04.2012)
# openssl genrsa -out ca.key 1024
# openssl req -new -key ca.key -out ca.csr -subj "/C=US/CN=ca"
# openssl req -x509 -days 7300 -key ca.key -in ca.csr -out ca.crt
#
# openssl genrsa -out server.key 1024
# openssl req -new -key server.key -out server.csr -subj "/C=US/CN=localhost"
# openssl x509 -req -days 7300 -in server.csr -out server.crt -CA ca.crt \
#   -CAkey ca.key -CAcreateserial
#
# openssl genrsa -out client.key 1024
# openssl req -new -key client.key -out client.csr -subj "/C=US/CN=localhost"
# openssl x509 -req -days 7300 -in client.csr -out client.crt -CA ca.crt \
#   -CAkey ca.key -CAcreateserial
#
# openssl genrsa -out badclient.key 1024
# openssl req -new -key badclient.key -out badclient.csr \
#   -subj "/C=US/CN=badclient"
# openssl req -x509 -days 7300 -key badclient.key -in badclient.csr \
#   -out badclient.crt
use Test::More;
use Mojo::IOLoop::Server;
plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.37 required for this test!'
  unless Mojo::IOLoop::Server::TLS;
plan tests => 28;

# "To the panic room!
#  We don't have a panic room.
#  To the panic room store!"
use Mojo::IOLoop;

# Built-in certificate
my $loop = Mojo::IOLoop->new;
my $port = Mojo::IOLoop->generate_port;
my ($server, $client);
$loop->server(
  {address => '127.0.0.1', port => $port, tls => 1} => sub {
    my ($loop, $stream) = @_;
    $stream->write('test', sub { shift->write('321') });
    $stream->on(read => sub { $server .= pop });
  }
);
$loop->client(
  {port => $port, tls => 1} => sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset', sub { shift->write('123') });
    $stream->on(read => sub { $client .= pop });
  }
);
$loop->timer(1 => sub { shift->stop });
$loop->start;
is $server, 'tset123', 'right content';
is $client, 'test321', 'right content';

# Valid client certificate
$loop   = Mojo::IOLoop->singleton;
$port   = Mojo::IOLoop->generate_port;
$server = $client = '';
my ($remove, $running, $timeout, $server_err, $server_close, $client_close);
Mojo::IOLoop->remove(Mojo::IOLoop->recurring(0 => sub { $remove++ }));
$loop->server(
  address  => '127.0.0.1',
  port     => $port,
  tls      => 1,
  tls_ca   => 't/mojo/certs/ca.crt',
  tls_cert => 't/mojo/certs/server.crt',
  tls_key  => 't/mojo/certs/server.key',
  sub {
    my ($loop, $stream) = @_;
    $stream->write('test', sub { shift->write('321') });
    $running = Mojo::IOLoop->is_running;
    $stream->on(timeout => sub { $timeout++ });
    $stream->on(close   => sub { $server_close++ });
    $stream->on(error   => sub { $server_err = pop });
    $stream->on(read    => sub { $server .= pop });
    $stream->timeout(0.5);
  }
);
$loop->client(
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/client.crt',
  tls_key  => 't/mojo/certs/client.key',
  sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset', sub { shift->write('123') });
    $stream->on(close => sub { $client_close++ });
    $stream->on(read => sub { $client .= pop });
  }
);
$loop->timer(1 => sub { shift->stop });
$loop->start;
is $server,       'tset123', 'right content';
is $client,       'test321', 'right content';
is $timeout,      1,         'server emitted timeout event once';
is $server_close, 1,         'server emitted close event once';
is $client_close, 1,         'client emitted close event once';
ok $running,      'loop was running';
ok !$remove,     'event removed successfully';
ok !$server_err, 'no error';

# Invalid client certificate
my $client_err;
$loop->client(
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/badclient.crt',
  tls_key  => 't/mojo/certs/badclient.key',
  sub { shift; $client_err = shift }
);
$loop->timer(1 => sub { shift->stop });
$loop->start;
ok $client_err, 'has error';

# Missing client certificate
$server_err = $client_err = '';
$loop->client({port => $port, tls => 1} => sub { shift; $client_err = shift }
);
$loop->timer(1 => sub { shift->stop });
$loop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Invalid certificate authority (server)
$loop       = Mojo::IOLoop->new;
$port       = Mojo::IOLoop->generate_port;
$server_err = $client_err = '';
$loop->server(
  address  => '127.0.0.1',
  port     => $port,
  tls      => 1,
  tls_ca   => 'no cert',
  tls_cert => 't/mojo/certs/server.crt',
  tls_key  => 't/mojo/certs/server.key',
  sub { $server_err = 'connected!' }
);
$loop->client(
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/client.crt',
  tls_key  => 't/mojo/certs/client.key',
  sub { shift; $client_err = shift }
);
$loop->timer(1 => sub { shift->stop });
$loop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Valid client and server certificates
$loop   = Mojo::IOLoop->singleton;
$port   = Mojo::IOLoop->generate_port;
$server = $client = '';
($running, $timeout, $server_err, $server_close, $client_close) = undef;
$loop->server(
  address  => '127.0.0.1',
  port     => $port,
  tls      => 1,
  tls_ca   => 't/mojo/certs/ca.crt',
  tls_cert => 't/mojo/certs/server.crt',
  tls_key  => 't/mojo/certs/server.key',
  sub {
    my ($loop, $stream) = @_;
    $stream->write('test', sub { shift->write('321') });
    $running = Mojo::IOLoop->is_running;
    $stream->on(timeout => sub { $timeout++ });
    $stream->on(close   => sub { $server_close++ });
    $stream->on(error   => sub { $server_err = pop });
    $stream->on(read    => sub { $server .= pop });
    $stream->timeout(0.5);
  }
);
$loop->client(
  port     => $port,
  tls      => 1,
  tls_ca   => 't/mojo/certs/ca.crt',
  tls_cert => 't/mojo/certs/client.crt',
  tls_key  => 't/mojo/certs/client.key',
  sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset', sub { shift->write('123') });
    $stream->on(close => sub { $client_close++ });
    $stream->on(read => sub { $client .= pop });
  }
);
$loop->timer(1 => sub { shift->stop });
$loop->start;
is $server,       'tset123', 'right content';
is $client,       'test321', 'right content';
is $timeout,      1,         'server emitted timeout event once';
is $server_close, 1,         'server emitted close event once';
is $client_close, 1,         'client emitted close event once';
ok $running,      'loop was running';
ok !$server_err, 'no error';

# Invalid server certificate (unsigned)
$loop       = Mojo::IOLoop->new;
$port       = Mojo::IOLoop->generate_port;
$server_err = $client_err = '';
$loop->server(
  address  => '127.0.0.1',
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/badclient.crt',
  tls_key  => 't/mojo/certs/badclient.key',
  sub { $server_err = 'connected!' }
);
$loop->client(
  port   => $port,
  tls    => 1,
  tls_ca => 't/mojo/certs/ca.crt',
  sub { shift; $client_err = shift }
);
$loop->timer(1 => sub { shift->stop });
$loop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Invalid server certificate (hostname)
$loop       = Mojo::IOLoop->new;
$port       = Mojo::IOLoop->generate_port;
$server_err = $client_err = '';
$loop->server(
  address  => '127.0.0.1',
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/server.crt',
  tls_key  => 't/mojo/certs/server.key',
  sub { $server_err = 'connected!' }
);
$loop->client(
  address => '127.0.0.1',
  port    => $port,
  tls     => 1,
  tls_ca  => 't/mojo/certs/ca.crt',
  sub { shift; $client_err = shift }
);
$loop->timer(1 => sub { shift->stop });
$loop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Invalid certificate authority (client)
$loop       = Mojo::IOLoop->new;
$port       = Mojo::IOLoop->generate_port;
$server_err = $client_err = '';
$loop->server(
  address  => '127.0.0.1',
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/badclient.crt',
  tls_key  => 't/mojo/certs/badclient.key',
  sub { $server_err = 'connected!' }
);
$loop->client(
  port   => $port,
  tls    => 1,
  tls_ca => 'no cert',
  sub { shift; $client_err = shift }
);
$loop->timer(1 => sub { shift->stop });
$loop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';
