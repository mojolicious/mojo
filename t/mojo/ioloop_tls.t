use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::TLS;

plan skip_all => 'set TEST_TLS to enable this test (developer only!)' unless $ENV{TEST_TLS} || $ENV{TEST_ALL};
plan skip_all => 'IO::Socket::SSL 2.009+ required for this test!'     unless Mojo::IOLoop::TLS->can_tls;

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
use Mojo::Promise;

# Built-in certificate (and upgraded string)
my $loop     = Mojo::IOLoop->new;
my $upgraded = "\x01\x00\x00\x00\x00\x00\xD0\x00\x0A\x00\x0B\x00\x00\x00\x84\x0B";
utf8::upgrade $upgraded;
my ($server, $client);
my $promise = Mojo::Promise->new->ioloop($loop);
my $id      = $loop->server(
  {address => '127.0.0.1', tls => 1} => sub {
    my ($loop, $stream) = @_;
    $stream->write($upgraded => sub { shift->write('321') });
    $stream->on(close => sub { $promise->resolve });
    $stream->on(read  => sub { $server .= pop });
  }
);
my $port     = $loop->acceptor($id)->port;
my $promise2 = Mojo::Promise->new->ioloop($loop);
$loop->client(
  {port => $port, tls => 1, tls_options => {SSL_verify_mode => 0x00}} => sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset' => sub { shift->write('123') });
    $stream->on(close => sub { $promise2->resolve });
    $stream->on(read  => sub { $client .= pop });
    $stream->timeout(0.5);
  }
);
Mojo::Promise->all($promise, $promise2)->wait;
is $server, 'tset123',        'right content';
is $client, "${upgraded}321", 'right content';

# Shutdown
$loop = Mojo::IOLoop->new;
$promise = Mojo::Promise->new->ioloop($loop);
$id = $loop->server(
  {address => '127.0.0.1', tls => 1} => sub {
    my ($loop, $stream) = @_;
    $stream->on(
      read  => sub {
        $stream->write("close");
        shift->close_gracefully();
        $promise->resolve;
      }
    );
  }
);
$promise2 = Mojo::Promise->new->ioloop($loop);
$port = $loop->acceptor($id)->port;
my ($shutdown, $handle);
$loop->client(
  {port => $port, tls => 1, tls_options => {SSL_verify_mode => 0x00}} => sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('quit');
    $stream->on(
      close => sub {
        my $ssl = ${*$handle}{_SSL_object};
        $shutdown = Net::SSLeay::get_shutdown($ssl);
        $promise2->resolve;
      }
    );
    # keep a reference the IO::Socket::SSL
    $handle = $stream->{handle};
    $shutdown = 0;
  }
);
Mojo::Promise->all($promise, $promise2)->wait;
is $shutdown, 2, 'SSL received shutdown';

# Valid client certificate
($server, $client) = ();
my ($remove, $running, $timeout, $server_err, $server_close, $client_close);
Mojo::IOLoop->remove(Mojo::IOLoop->recurring(0 => sub { $remove++ }));
$promise = Mojo::Promise->new;
$id      = Mojo::IOLoop->server(
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
        $promise->resolve;
      }
    );
    $stream->on(error => sub { $server_err = pop });
    $stream->on(read  => sub { $server .= pop });
    $stream->timeout(0.5);
  }
);
$port     = Mojo::IOLoop->acceptor($id)->port;
$promise2 = Mojo::Promise->new;
Mojo::IOLoop->client(
  port        => $port,
  tls         => 1,
  tls_cert    => 't/mojo/certs/client.crt',
  tls_key     => 't/mojo/certs/client.key',
  tls_options => {SSL_verify_mode => 0x00},
  sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset' => sub { shift->write('123') });
    $stream->on(
      close => sub {
        $client_close++;
        $promise2->resolve;
      }
    );
    $stream->on(read => sub { $client .= pop });
  }
);
Mojo::Promise->all($promise, $promise2)->wait;
is $server,       'tset123', 'right content';
is $client,       'test321', 'right content';
is $timeout,      1,         'server emitted timeout event once';
is $server_close, 1,         'server emitted close event once';
is $client_close, 1,         'client emitted close event once';
ok $running,     'loop was running';
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
ok $client_err,  'has error';

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
ok $client_err,  'has error';

# Valid client and server certificates
($running, $timeout, $server, $server_err, $server_close) = ();
($client, $client_close) = ();
$promise = Mojo::Promise->new;
$id      = Mojo::IOLoop->server(
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
        $promise->resolve;
      }
    );
    $stream->on(error => sub { $server_err = pop });
    $stream->on(read  => sub { $server .= pop });
  }
);
$port     = Mojo::IOLoop->acceptor($id)->port;
$promise2 = Mojo::Promise->new;
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
        $promise2->resolve;
      }
    );
    $stream->on(read => sub { $client .= pop });
    $stream->timeout(0.5);
  }
);
Mojo::Promise->all($promise, $promise2)->wait;
is $server,       'tset123', 'right content';
is $client,       'test321', 'right content';
is $timeout,      1,         'server emitted timeout event once';
is $server_close, 1,         'server emitted close event once';
is $client_close, 1,         'client emitted close event once';
ok $running,     'loop was running';
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
ok $client_err,  'has error';

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
ok $client_err,  'has error';

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
ok $client_err,  'has error';

# Ignore invalid client certificate
$loop = Mojo::IOLoop->new;
my ($cipher, $version);
($server, $client, $client_err) = ();
$id = $loop->server(
  address     => '127.0.0.1',
  tls         => 1,
  tls_ca      => 't/mojo/certs/ca.crt',
  tls_cert    => 't/mojo/certs/server.crt',
  tls_key     => 't/mojo/certs/server.key',
  tls_options => {SSL_verify_mode => 0x00, SSL_cipher_list => 'AES256-SHA:ALL'},
  sub {
    my ($loop, $stream) = @_;
    $stream->on(close => sub { $loop->stop });
    $server = 'accepted';
  }
);
$port = $loop->acceptor($id)->port;
$loop->client(
  port        => $port,
  tls         => 1,
  tls_cert    => 't/mojo/certs/bad.crt',
  tls_key     => 't/mojo/certs/bad.key',
  tls_options => {SSL_verify_mode => 0x00},
  sub {
    my ($loop, $err, $stream) = @_;
    $stream->timeout(0.5);
    $client_err = $err;
    $client     = 'connected';
    my $handle = $stream->handle;
    $cipher  = $handle->get_cipher;
    $version = $handle->get_sslversion;
  }
);
$loop->start;
is $server, 'accepted',  'right result';
is $client, 'connected', 'right result';
ok !$client_err, 'no error';
my $expect = $version eq 'TLSv1_3' ? 'TLS_AES_256_GCM_SHA384' : 'AES256-SHA';
is $cipher, $expect, "$expect has been negotiatied";

# Ignore missing client certificate
($server, $client, $client_err) = ();
$id = Mojo::IOLoop->server(
  address     => '127.0.0.1',
  tls         => 1,
  tls_ca      => 't/mojo/certs/ca.crt',
  tls_cert    => 't/mojo/certs/server.crt',
  tls_key     => 't/mojo/certs/server.key',
  tls_options => {SSL_verify_mode => 0x01, SSL_version => 'TLSv1_2'},
  sub { $server = 'accepted' }
);
$port = Mojo::IOLoop->acceptor($id)->port;
Mojo::IOLoop->client(
  {port => $port, tls => 1, tls_options => {SSL_verify_mode => 0x00}} => sub {
    shift->stop;
    $client     = 'connected';
    $client_err = shift;
  }
);
Mojo::IOLoop->start;
is $server, 'accepted',  'right result';
is $client, 'connected', 'right result';
ok !$client_err, 'no error';

subtest 'ALPN' => sub {
  plan skip_all => 'ALPN support required!' unless IO::Socket::SSL->can_alpn;
  my ($server_proto, $client_proto);
  $id = Mojo::IOLoop->server(
    address     => '127.0.0.1',
    tls         => 1,
    tls_options => {SSL_alpn_protocols => ['foo', 'bar', 'baz']},
    sub {
      my ($loop, $stream) = @_;
      $server_proto = $stream->handle->alpn_selected;
      $stream->close;
    }
  );
  $port = Mojo::IOLoop->acceptor($id)->port;
  Mojo::IOLoop->client(
    port        => $port,
    tls         => 1,
    tls_options => {SSL_alpn_protocols => ['baz', 'bar'], SSL_verify_mode => 0x00},
    sub {
      my ($loop, $err, $stream) = @_;
      $client_proto = $stream->handle->alpn_selected;
      $stream->on(close => sub { Mojo::IOLoop->stop });
    }
  );
  Mojo::IOLoop->start;
  is $server_proto, 'baz', 'right protocol';
  is $client_proto, 'baz', 'right protocol';
};

done_testing();
