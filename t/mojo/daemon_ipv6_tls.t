use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::TLS;

use Mojo::File 'curfile';
use lib curfile->sibling('lib')->to_string;

plan skip_all => 'set TEST_IPV6 to enable this test (developer only!)'
  unless $ENV{TEST_IPV6} || $ENV{TEST_ALL};
plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS} || $ENV{TEST_ALL};
plan skip_all => 'IO::Socket::SSL 2.009+ required for this test!'
  unless Mojo::IOLoop::TLS->can_tls;

# To regenerate all required certificates run these commands (07.01.2016)
# openssl genrsa -out domain.key 1024
# openssl req -new -key domain.key -out domain.csr -subj "/C=US/CN=example.com"
# openssl x509 -req -days 7300 -in domain.csr -out domain.crt -CA ca.crt \
#   -CAkey ca.key -CAcreateserial
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::TestConnectProxy;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/' => {text => 'works!'};

# IPv6 and TLS
my $daemon = Mojo::Server::Daemon->new(
  app    => app,
  listen => ['https://[::1]'],
  silent => 1
);
my $port = $daemon->start->ports->[0];
my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton, insecure => 1);
my $tx = $ua->get("https://[::1]:$port/");
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# IPv6, TLS, SNI and a proxy
SKIP: {
  skip 'SNI support required!', 1
    unless IO::Socket::SSL->can_client_sni && IO::Socket::SSL->can_server_sni;
  $daemon = Mojo::Server::Daemon->new(app => app, silent => 1);
  my $listen
    = 'https://[::1]'
    . '?127.0.0.1_cert=t/mojo/certs/server.crt'
    . '&127.0.0.1_key=t/mojo/certs/server.key'
    . '&example.com_cert=t/mojo/certs/domain.crt'
    . '&example.com_key=t/mojo/certs/domain.key';
  my $forward = $daemon->listen([$listen])->start->ports->[0];
  my $id      = Mojo::TestConnectProxy::proxy({address => '[::1]'},
    {address => '[::1]', port => $forward});
  my $proxy = Mojo::IOLoop->acceptor($id)->port;
  $ua = Mojo::UserAgent->new(
    ioloop => Mojo::IOLoop->singleton,
    ca     => 't/mojo/certs/ca.crt'
  );
  $ua->proxy->https("http://[::1]:$proxy");
  $tx = $ua->get("https://example.com/");
  is $tx->res->code, 200,      'right status';
  is $tx->res->body, 'works!', 'right content';
  ok !$tx->error, 'no error';
  $tx = $ua->get("https://127.0.0.1/");
  is $tx->res->code, 200,      'right status';
  is $tx->res->body, 'works!', 'right content';
  ok !$tx->error, 'no error';
  $tx = $ua->get("https://has.no.cert/");
  like $tx->error->{message}, qr/hostname verification failed/, 'right error';
}

done_testing();
