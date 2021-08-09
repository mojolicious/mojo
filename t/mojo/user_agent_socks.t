use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::Client;
use Mojo::IOLoop::TLS;

plan skip_all => 'set TEST_SOCKS to enable this test (developer only!)' unless $ENV{TEST_SOCKS} || $ENV{TEST_ALL};
plan skip_all => 'IO::Socket::Socks 0.64+ required for this test!'      unless Mojo::IOLoop::Client->can_socks;
plan skip_all => 'IO::Socket::SSL 2.009+ required for this test!'       unless Mojo::IOLoop::TLS->can_tls;

use Mojo::IOLoop;
use Mojo::IOLoop::Server;
use Mojo::IOLoop::Stream;
use Mojo::UserAgent;
use Mojolicious::Lite;
use Scalar::Util qw(weaken);

# Silence
app->log->level('fatal');

get '/' => sub {
  my $c = shift;
  $c->render(text => $c->tx->remote_port);
};

websocket '/echo' => sub {
  my $c = shift;
  $c->on(
    message => sub {
      my $c = shift;
      $c->send($c->tx->remote_port);
    }
  );
};

get '/secure' => sub {
  my $c = shift;
  $c->render(text => $c->req->url->to_abs->protocol . ':' . $c->tx->remote_port);
};

my $port   = Mojo::IOLoop::Server->generate_port;
my $server = IO::Socket::Socks->new(
  Blocking    => 0,
  Listen      => 10,
  ProxyAddr   => '127.0.0.1',
  ProxyPort   => $port,
  RequireAuth => 1,
  UserAuth    => sub { $_[0] eq 'foo' && $_[1] eq 'bar' }
);

# SOCKS proxy server for testing
my $last;
Mojo::IOLoop->singleton->reactor->io(
  $server => sub {
    my $reactor = shift;

    my $client = $server->accept;
    $client->blocking(0);
    my ($address, $port);
    $reactor->io(
      $client => sub {
        my $reactor = shift;

        my $err = $IO::Socket::Socks::SOCKS_ERROR;
        if ($client->ready) {

          if ($address) {
            $reactor->remove($client);
            Mojo::IOLoop->client(
              {address => $address, port => $port} => sub {
                my ($loop, $err, $server) = @_;
                $last = $server->handle->sockport;
                weaken $server;
                $client = Mojo::IOLoop::Stream->new($client);
                Mojo::IOLoop->stream($client);
                $client->on(read  => sub { $server->write(pop) });
                $client->on(close => sub { $server && $server->close });
                $server->on(read  => sub { $client->write(pop) });
                $server->on(close => sub { $client && $client->close });
              }
            );
          }

          else {
            ($address, $port) = @{$client->command}[1, 2];
            $client->command_reply(IO::Socket::Socks::REPLY_SUCCESS(), $address, $port);
          }
        }
        elsif ($err == IO::Socket::Socks::SOCKS_WANT_WRITE()) {
          $reactor->watch($client, 1, 1);
        }
        elsif ($err == IO::Socket::Socks::SOCKS_WANT_READ()) {
          $reactor->watch($client, 1, 0);
        }
      }
    );
  }
);

subtest 'Failed authentication with SOCKS proxy' => sub {
  my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton, insecure => 1);
  $ua->proxy->http("socks://foo:baz\@127.0.0.1:$port");
  my $tx = $ua->get('/');
  ok $tx->error, 'has error';
};

subtest 'Simple request with SOCKS proxy' => sub {
  my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton, insecure => 1);
  $ua->proxy->http("socks://foo:bar\@127.0.0.1:$port");
  my $tx = $ua->get('/');
  ok !$tx->error,      'no error';
  ok !$tx->kept_alive, 'kept connection not alive';
  ok $tx->keep_alive, 'keep connection alive';
  is $tx->res->code, 200, 'right status';
  is $tx->req->headers->proxy_authorization, undef, 'no "Proxy-Authorization" value';
  is $tx->res->body, $last, 'right content';
  isnt(Mojo::IOLoop->stream($tx->connection)->handle->sockport, $last, 'different ports');
};

subtest 'Keep alive request with SOCKS proxy' => sub {
  my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton, insecure => 1);
  $ua->proxy->http("socks://foo:bar\@127.0.0.1:$port");
  my $before = $last;
  my $tx     = $ua->get('/');
  ok !$tx->error, 'no error';
  ok $tx->kept_alive, 'kept connection alive';
  ok $tx->keep_alive, 'keep connection alive';
  is $tx->res->code, 200, 'right status';
  is $tx->res->body, $last, 'right content';
  is $before, $last, 'same port';
  isnt(Mojo::IOLoop->stream($tx->connection)->handle->sockport, $last, 'different ports');
};

subtest 'WebSocket with SOCKS proxy' => sub {
  my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton, insecure => 1);
  $ua->proxy->http("socks://foo:bar\@127.0.0.1:$port");
  my ($result, $id);
  $ua->websocket(
    '/echo' => sub {
      my ($ua, $tx) = @_;
      $id = $tx->connection;
      $tx->on(message => sub { $result = pop; Mojo::IOLoop->stop });
      $tx->send('test');
    }
  );
  Mojo::IOLoop->start;
  is $result, $last, 'right result';
  isnt(Mojo::IOLoop->stream($id)->handle->sockport, $last, 'different ports');
};

subtest 'HTTPS request with SOCKS proxy' => sub {
  my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton, insecure => 1);
  $ua->proxy->https("socks://foo:bar\@127.0.0.1:$port");
  $ua->server->url('https');
  my $tx = $ua->get('/secure');
  ok !$tx->error,      'no error';
  ok !$tx->kept_alive, 'kept connection not alive';
  ok $tx->keep_alive, 'keep connection alive';
  is $tx->res->code, 200,           'right status';
  is $tx->res->body, "https:$last", 'right content';
  isnt(Mojo::IOLoop->stream($tx->connection)->handle->sockport, $last, 'different ports');
};

subtest 'Disabled SOCKS proxy' => sub {
  my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton, insecure => 1);
  $ua->server->url('http');
  $ua->proxy->http("socks://foo:baz\@127.0.0.1:$port");
  my $tx = $ua->build_tx(GET => '/');
  $tx->req->via_proxy(0);
  $tx = $ua->start($tx);
  ok !$tx->error, 'no error';
  is $tx->res->code, 200, 'right status';
  is $tx->res->body, $tx->local_port, 'right content';
};

done_testing();
