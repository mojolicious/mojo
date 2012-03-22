use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::IOLoop::Server;
plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.37 required for this test!'
  unless Mojo::IOLoop::Server::TLS;
plan tests => 19;

# "That does not compute.
#  Really?
#  Well, it computes a little."
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => {text => 'works!'};

# Web server with valid certificates
my $daemon =
  Mojo::Server::Daemon->new(app => app, ioloop => Mojo::IOLoop->singleton);
my $port = Mojo::IOLoop->new->generate_port;
my $listen =
    "https://127.0.0.1:$port"
  . '?cert=t/mojo/certs/server.crt'
  . '&key=t/mojo/certs/server.key'
  . '&ca=t/mojo/certs/ca.crt';
$daemon->listen([$listen])->start;

# No certificate
my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
my $tx = $ua->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';
$tx = $ua->cert('')->key('')->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';

# Valid certificates
$ua->ca('t/mojo/certs/ca.crt')->cert('t/mojo/certs/client.crt')
  ->key('t/mojo/certs/client.key');
$tx = $ua->get("https://localhost:$port");
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Valid certificates (env)
$ua = Mojo::UserAgent->new(ioloop => $ua->ioloop);
{
  local $ENV{MOJO_CA_FILE}   = 't/mojo/certs/ca.crt';
  local $ENV{MOJO_CERT_FILE} = 't/mojo/certs/client.crt';
  local $ENV{MOJO_KEY_FILE}  = 't/mojo/certs/client.key';
  $tx = $ua->get("https://localhost:$port");
  is $ua->ca,   't/mojo/certs/ca.crt',     'right path';
  is $ua->cert, 't/mojo/certs/client.crt', 'right path';
  is $ua->key,  't/mojo/certs/client.key', 'right path';
  ok $tx->success, 'successful';
  is $tx->res->code, 200,      'right status';
  is $tx->res->body, 'works!', 'right content';
}

# Invalid certificate authority
$ua = Mojo::UserAgent->new(ioloop => $ua->ioloop);
$ua->ca('no file')->cert('t/mojo/certs/client.crt')
  ->key('t/mojo/certs/client.key');
$tx = $ua->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';

# Invalid certificate
$ua = Mojo::UserAgent->new(ioloop => $ua->ioloop);
$ua->cert('t/mojo/certs/badclient.crt')->key('t/mojo/certs/badclient.key');
$tx = $ua->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';

# Empty certificate
$ua = Mojo::UserAgent->new(ioloop => $ua->ioloop);
$tx = $ua->cert('no file')->key('no file')->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';
