use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::Server;

plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.84 required for this test!'
  unless Mojo::IOLoop::Server::TLS;

# To regenerate all required certificates run these commands (12.12.2014)
# openssl genrsa -out ca.key 1024
# openssl req -new -key ca.key -out ca.csr -subj "/C=US/CN=ca"
# openssl req -x509 -days 7300 -key ca.key -in ca.csr -out ca.crt
#
# openssl genrsa -out server.key 1024
# openssl req -new -key server.key -out server.csr -subj "/C=US/CN=127.0.0.1"
# openssl x509 -req -days 7300 -in server.csr -out server.crt -CA ca.crt \
#   -CAkey ca.key -CAcreateserial
#
# openssl genrsa -out client.key 1024
# openssl req -new -key client.key -out client.csr -subj "/C=US/CN=127.0.0.1"
# openssl x509 -req -days 7300 -in client.csr -out client.crt -CA ca.crt \
#   -CAkey ca.key -CAcreateserial
#
# openssl genrsa -out bad.key 1024
# openssl req -new -key bad.key -out bad.csr -subj "/C=US/CN=bad"
# openssl req -x509 -days 7300 -key bad.key -in bad.csr -out bad.crt
use Mojo::IOLoop;

# Built-in certificate
my $loop  = Mojo::IOLoop->new;
my $delay = $loop->delay;
my ($server, $client);
my $end = $delay->begin;
my $id  = $loop->server(
  {address => '127.0.0.1', tls => 1} => sub {
    my ($loop, $stream) = @_;
    $stream->write('test' => sub { shift->write('321') });
    $stream->on(close => $end);
    $stream->on(read => sub { $server .= pop });
  }
);
my $port = $loop->acceptor($id)->port;
my $end2 = $delay->begin;
$loop->client(
  {port => $port, tls => 1} => sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset' => sub { shift->write('123') });
    $stream->on(close => $end2);
    $stream->on(read => sub { $client .= pop });
    $stream->timeout(0.5);
  }
);
$delay->wait;
is $server, 'tset123', 'right content';
is $client, 'test321', 'right content';

# Valid client certificate
$delay = Mojo::IOLoop->delay;
($server, $client) = ();
my ($remove, $running, $timeout, $server_err, $server_close, $client_close);
Mojo::IOLoop->remove(Mojo::IOLoop->recurring(0 => sub { $remove++ }));
$end = $delay->begin;
$id  = Mojo::IOLoop->server(
  address  => '127.0.0.1',
  tls      => 1,
  tls_ca   => 't/mojo/certs/ca.crt',
  tls_cert => 't/mojo/certs/server.crt',
  tls_key  => 't/mojo/certs/server.key',
  sub {
    my ($loop, $stream) = @_;
    $stream->write('test' => sub { shift->write('321') });
    $running = Mojo::IOLoop->is_running;
    $stream->on(timeout => sub { $timeout++ });
    $stream->on(
      close => sub {
        $server_close++;
        $end->();
      }
    );
    $stream->on(error => sub { $server_err = pop });
    $stream->on(read => sub { $server .= pop });
    $stream->timeout(0.5);
  }
);
$port = Mojo::IOLoop->acceptor($id)->port;
$end2 = $delay->begin;
Mojo::IOLoop->client(
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/client.crt',
  tls_key  => 't/mojo/certs/client.key',
  sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset' => sub { shift->write('123') });
    $stream->on(
      close => sub {
        $client_close++;
        $end2->();
      }
    );
    $stream->on(read => sub { $client .= pop });
  }
);
$delay->wait;
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
Mojo::IOLoop->client(
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/bad.crt',
  tls_key  => 't/mojo/certs/bad.key',
  sub {
    shift->stop;
    $client_err = shift;
  }
);
Mojo::IOLoop->start;
ok $client_err, 'has error';

# Missing client certificate
($server_err, $client_err) = ();
Mojo::IOLoop->client(
  {port => $port, tls => 1} => sub {
    shift->stop;
    $client_err = shift;
  }
);
Mojo::IOLoop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Invalid certificate authority (server)
$loop = Mojo::IOLoop->new;
($server_err, $client_err) = ();
$id = $loop->server(
  address  => '127.0.0.1',
  tls      => 1,
  tls_ca   => 'no cert',
  tls_cert => 't/mojo/certs/server.crt',
  tls_key  => 't/mojo/certs/server.key',
  sub { $server_err = 'accepted' }
);
$port = $loop->acceptor($id)->port;
$loop->client(
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/client.crt',
  tls_key  => 't/mojo/certs/client.key',
  sub {
    shift->stop;
    $client_err = shift;
  }
);
$loop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Valid client and server certificates
$delay = Mojo::IOLoop->delay;
($running, $timeout, $server, $server_err, $server_close) = ();
($client, $client_close) = ();
$end = $delay->begin;
$id  = Mojo::IOLoop->server(
  address  => '127.0.0.1',
  tls      => 1,
  tls_ca   => 't/mojo/certs/ca.crt',
  tls_cert => 't/mojo/certs/server.crt',
  tls_key  => 't/mojo/certs/server.key',
  sub {
    my ($loop, $stream) = @_;
    $stream->write('test' => sub { shift->write('321') });
    $running = Mojo::IOLoop->is_running;
    $stream->on(
      close => sub {
        $server_close++;
        $end->();
      }
    );
    $stream->on(error => sub { $server_err = pop });
    $stream->on(read => sub { $server .= pop });
  }
);
$port = Mojo::IOLoop->acceptor($id)->port;
$end2 = $delay->begin;
Mojo::IOLoop->client(
  port     => $port,
  tls      => 1,
  tls_ca   => 't/mojo/certs/ca.crt',
  tls_cert => 't/mojo/certs/client.crt',
  tls_key  => 't/mojo/certs/client.key',
  sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset' => sub { shift->write('123') });
    $stream->on(timeout => sub { $timeout++ });
    $stream->on(
      close => sub {
        $client_close++;
        $end2->();
      }
    );
    $stream->on(read => sub { $client .= pop });
    $stream->timeout(0.5);
  }
);
$delay->wait;
is $server,       'tset123', 'right content';
is $client,       'test321', 'right content';
is $timeout,      1,         'server emitted timeout event once';
is $server_close, 1,         'server emitted close event once';
is $client_close, 1,         'client emitted close event once';
ok $running,      'loop was running';
ok !$server_err, 'no error';

# Invalid server certificate (unsigned)
$loop = Mojo::IOLoop->new;
($server_err, $client_err) = ();
$id = $loop->server(
  address  => '127.0.0.1',
  tls      => 1,
  tls_cert => 't/mojo/certs/bad.crt',
  tls_key  => 't/mojo/certs/bad.key',
  sub { $server_err = 'accepted' }
);
$port = $loop->acceptor($id)->port;
$loop->client(
  port   => $port,
  tls    => 1,
  tls_ca => 't/mojo/certs/ca.crt',
  sub {
    shift->stop;
    $client_err = shift;
  }
);
$loop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Invalid server certificate (hostname)
$loop = Mojo::IOLoop->new;
($server_err, $client_err) = ();
$id = $loop->server(
  address  => '127.0.0.1',
  tls      => 1,
  tls_cert => 't/mojo/certs/bad.crt',
  tls_key  => 't/mojo/certs/bad.key',
  sub { $server_err = 'accepted' }
);
$port = $loop->acceptor($id)->port;
$loop->client(
  address => '127.0.0.1',
  port    => $port,
  tls     => 1,
  tls_ca  => 't/mojo/certs/ca.crt',
  sub {
    shift->stop;
    $client_err = shift;
  }
);
$loop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Invalid certificate authority (client)
$loop = Mojo::IOLoop->new;
($server_err, $client_err) = ();
$id = $loop->server(
  address  => '127.0.0.1',
  tls      => 1,
  tls_cert => 't/mojo/certs/bad.crt',
  tls_key  => 't/mojo/certs/bad.key',
  sub { $server_err = 'accepted' }
);
$port = $loop->acceptor($id)->port;
$loop->client(
  port   => $port,
  tls    => 1,
  tls_ca => 'no cert',
  sub {
    shift->stop;
    $client_err = shift;
  }
);
$loop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Ignore invalid client certificate
$loop = Mojo::IOLoop->new;
my $cipher;
($server, $client, $client_err) = ();
$id = $loop->server(
  address     => '127.0.0.1',
  tls         => 1,
  tls_ca      => 't/mojo/certs/ca.crt',
  tls_cert    => 't/mojo/certs/server.crt',
  tls_ciphers => 'RC4-SHA:ALL',
  tls_key     => 't/mojo/certs/server.key',
  tls_verify  => 0x00,
  sub {
    my ($loop, $stream) = @_;
    $stream->on(close => sub { $loop->stop });
    $server = 'accepted';
  }
);
$port = $loop->acceptor($id)->port;
$loop->client(
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/bad.crt',
  tls_key  => 't/mojo/certs/bad.key',
  sub {
    my ($loop, $err, $stream) = @_;
    $stream->timeout(0.5);
    $client_err = $err;
    $client     = 'connected';
    $cipher     = $stream->handle->get_cipher;
  }
);
$loop->start;
is $server, 'accepted',  'right result';
is $client, 'connected', 'right result';
ok !$client_err, 'no error';
is $cipher, 'RC4-SHA', 'RC4-SHA has been negotiatied';

# Ignore missing client certificate
($server, $client, $client_err) = ();
$id = Mojo::IOLoop->server(
  address    => '127.0.0.1',
  tls        => 1,
  tls_ca     => 't/mojo/certs/ca.crt',
  tls_cert   => 't/mojo/certs/server.crt',
  tls_key    => 't/mojo/certs/server.key',
  tls_verify => 0x01,
  sub { $server = 'accepted' }
);
$port = Mojo::IOLoop->acceptor($id)->port;
Mojo::IOLoop->client(
  {port => $port, tls => 1} => sub {
    shift->stop;
    $client     = 'connected';
    $client_err = shift;
  }
);
Mojo::IOLoop->start;
is $server, 'accepted',  'right result';
is $client, 'connected', 'right result';
ok !$client_err, 'no error';

done_testing();
