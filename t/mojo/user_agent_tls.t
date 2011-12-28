use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More;
use Mojo::IOLoop::Server;
plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.37 required for this test!'
  unless Mojo::IOLoop::Server::TLS;
plan tests => 14;

# "That does not compute.
#  Really?
#  Well, it computes a little."
use Mojo::IOLoop;
use Mojo::UserAgent;

# Server
my $ua   = Mojo::UserAgent->new;
my $port = $ua->ioloop->generate_port;
my $err;
my $id = $ua->ioloop->server(
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/server.crt',
  tls_key  => 't/mojo/certs/server.key',
  tls_ca   => 't/mojo/certs/ca.crt',
  sub {
    my ($loop, $stream, $id) = @_;
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;
        $stream->write("HTTP/1.1 200 OK\x0d\x0a"
            . "Connection: keep-alive\x0d\x0a"
            . "Content-Length: 6\x0d\x0a\x0d\x0aworks!");
        $loop->drop($id);
      }
    );
    $stream->on(
      error => sub {
        $loop->drop($id);
        $err = pop;
      }
    );
  }
);

# No certificate
my $tx = $ua->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';
ok !$err, 'no error';
$err = '';
$tx  = $ua->cert('')->key('')->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';
ok !$err, 'no error';

# Valid certificate
$tx =
  $ua->cert('t/mojo/certs/client.crt')->key('t/mojo/certs/client.key')
  ->get("https://localhost:$port");
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Fresh user agent
$ua = Mojo::UserAgent->new(ioloop => $ua->ioloop);

# Valid certificate (env)
{
  local $ENV{MOJO_CERT_FILE} = 't/mojo/certs/client.crt';
  local $ENV{MOJO_KEY_FILE}  = 't/mojo/certs/client.key';
  $tx = $ua->get("https://localhost:$port");
  ok $tx->success, 'successful';
  is $tx->res->code, 200,      'right status';
  is $tx->res->body, 'works!', 'right content';
}

# Invalid certificate
$tx =
  $ua->cert('t/mojo/certs/badclient.crt')->key('t/mojo/certs/badclient.key')
  ->get("https://localhost:$port");
ok !$err, 'no error';

# Empty certificate
$tx = $ua->cert('no file')->key('no file')->get("https://localhost:$port");
ok !$err, 'no error';
