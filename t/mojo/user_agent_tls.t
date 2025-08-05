use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::TLS;

plan skip_all => 'set TEST_TLS to enable this test (developer only!)' unless $ENV{TEST_TLS} || $ENV{TEST_ALL};
plan skip_all => 'IO::Socket::SSL 2.009+ required for this test!'     unless Mojo::IOLoop::TLS->can_tls;

use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/' => {text => 'works!'};

subtest 'Web server with valid certificates' => sub {
  my $daemon = Mojo::Server::Daemon->new(app => app, ioloop => Mojo::IOLoop->singleton, silent => 1);
  my $listen
    = 'https://127.0.0.1'
    . '?cert=t/mojo/certs/server.crt'
    . '&key=t/mojo/certs/server.key'
    . '&ca=t/mojo/certs/ca.crt&verify=0x03';
  my $port = $daemon->listen([$listen])->start->ports->[0];

  subtest 'No certificate' => sub {
    my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
    my $tx = $ua->get("https://localhost:$port");
    ok $tx->error, 'has error';
    $tx = $ua->get("https://localhost:$port");
    ok $tx->error, 'has error';
    $tx = $ua->ca('t/mojo/certs/ca.crt')->get("https://localhost:$port");
    ok $tx->error, 'has error';
    $tx = $ua->get("https://localhost:$port");
    ok $tx->error, 'has error';
  };

  subtest 'Valid certificates' => sub {
    my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
    $ua->ca('t/mojo/certs/ca.crt')->cert('t/mojo/certs/client.crt')->key('t/mojo/certs/client.key');
    my $tx = $ua->get("https://localhost:$port");
    ok !$tx->error, 'no error';
    is $tx->res->code, 200,      'right status';
    is $tx->res->body, 'works!', 'right content';
  };

  subtest 'Valid certificates (env)' => sub {
    my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
    local $ENV{MOJO_CA_FILE}   = 't/mojo/certs/ca.crt';
    local $ENV{MOJO_CERT_FILE} = 't/mojo/certs/client.crt';
    local $ENV{MOJO_KEY_FILE}  = 't/mojo/certs/client.key';
    local $ENV{MOJO_INSECURE}  = 0;
    my $tx = $ua->get("https://localhost:$port");
    is $ua->ca,       't/mojo/certs/ca.crt',     'right path';
    is $ua->cert,     't/mojo/certs/client.crt', 'right path';
    is $ua->key,      't/mojo/certs/client.key', 'right path';
    is $ua->insecure, 0,                         'secure';
    ok !$tx->error, 'no error';
    is $tx->res->code, 200,      'right status';
    is $tx->res->body, 'works!', 'right content';
  };

  subtest 'Invalid certificate' => sub {
    my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
    $ua->cert('t/mojo/certs/bad.crt')->key('t/mojo/certs/bad.key');
    my $tx = $ua->get("https://localhost:$port");
    ok $tx->error, 'has error';
  };
};


subtest 'Web server with valid certificates and no verification' => sub {
  my $daemon = Mojo::Server::Daemon->new(app => app, ioloop => Mojo::IOLoop->singleton, silent => 1);
  my $listen
    = 'https://127.0.0.1'
    . '?cert=t/mojo/certs/server.crt'
    . '&key=t/mojo/certs/server.key'
    . '&ca=t/mojo/certs/ca.crt'
    . '&ciphers=AES256-SHA:ALL'
    . '&verify=0x00'
    . '&version=TLSv1_2';
  my $port = $daemon->listen([$listen])->start->ports->[0];

  # Invalid certificate
  my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
  $ua->cert('t/mojo/certs/bad.crt')->key('t/mojo/certs/bad.key');
  my $tx = $ua->get("https://localhost:$port");
  ok $tx->error, 'has error';
  $ua = Mojo::UserAgent->new(ioloop => $ua->ioloop, insecure => 1);
  $ua->cert('t/mojo/certs/bad.crt')->key('t/mojo/certs/bad.key');
  $tx = $ua->get("https://localhost:$port");
  ok !$tx->error, 'no error';
  is $ua->ioloop->stream($tx->connection)->handle->get_cipher,     'AES256-SHA', 'AES256-SHA has been negotiatied';
  is $ua->ioloop->stream($tx->connection)->handle->get_sslversion, 'TLSv1_2',    'TLSv1.2 has been negotiatied';
};

subtest 'Client side TLS options' => sub {
  my $daemon = Mojo::Server::Daemon->new(app => app, ioloop => Mojo::IOLoop->singleton, silent => 1);
  my $listen
    = 'https://127.0.0.1'
    . '?cert=t/mojo/certs/server.crt'
    . '&key=t/mojo/certs/server.key'
    . '&ca=t/mojo/certs/ca.crt'
    . '&version=TLSv1_2';
  my $port = $daemon->listen([$listen])->start->ports->[0];

  subtest '(Not) setting verification mode' => sub {
    my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
    my $tx = $ua->get("https://localhost:$port");
    like $tx->error->{message}, qr/certificate verify failed/, 'has error';

    $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
    $ua->tls_options({SSL_verify_mode => 0x00});
    $tx = $ua->get("https://localhost:$port");
    ok !$tx->error, 'no error';
  };

  subtest 'Setting acceptable protocol version' => sub {
    my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
    $ua->tls_options({SSL_version => 'TLSv1_3'});
    my $tx = $ua->get("https://localhost:$port");
    like $tx->error->{message}, qr/tlsv1 alert protocol version/, 'has error';
  };
};

done_testing();
