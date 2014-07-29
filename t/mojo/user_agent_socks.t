use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::IOLoop::Client;

plan skip_all => 'set TEST_SOCKS to enable this test (developer only!)'
  unless $ENV{TEST_SOCKS};
plan skip_all => 'IO::Socket::SOCKS 0.63 required for this test!'
  unless Mojo::IOLoop::Client::SOCKS;
plan skip_all => 'IO::Socket::SSL 1.84 required for this test!'
  unless Mojo::IOLoop::Server::TLS;

use Mojo::IOLoop;
use Mojo::IOLoop::Server;
use Mojo::IOLoop::Stream;
use Mojo::UserAgent;
use Mojolicious::Lite;
use Scalar::Util 'weaken';

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
  $c->render(
    text => $c->req->url->to_abs->protocol . ':' . $c->tx->remote_port);
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
                $client->on(close => sub { $server->close });
                $server->on(read  => sub { $client->write(pop) });
                $server->on(close => sub { $client->close });
              }
            );
          }

          else {
            ($address, $port) = @{$client->command}[1, 2];
            $client->command_reply(IO::Socket::Socks::REPLY_SUCCESS(),
              $address, $port);
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

# Simple request with SOCKS proxy
my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
$ua->proxy->http("socks://foo:bar\@127.0.0.1:$port");
my $tx = $ua->get('/');
ok $tx->success, 'successful';
ok !$tx->kept_alive, 'kept connection not alive';
ok $tx->keep_alive, 'keep connection alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, $last, 'right content';
isnt $last, $port, 'different port';

# Keep alive request with SOCKS proxy
$tx = $ua->get('/');
ok $tx->success,    'successful';
ok $tx->kept_alive, 'kept connection alive';
ok $tx->keep_alive, 'keep connection alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, $last, 'right content';
isnt $last, $port, 'different port';

# WebSocket with SOCKS proxy
my $result;
$ua->websocket(
  '/echo' => sub {
    my ($ua, $tx) = @_;
    $tx->on(
      message => sub {
        $result = pop;
        Mojo::IOLoop->stop;
      }
    );
    $tx->send('test');
  }
);
Mojo::IOLoop->start;
is $result, $last, 'right result';
isnt $last, $port, 'different port';

# HTTPS request with SOCKS proxy
$ua->proxy->https("socks://foo:bar\@127.0.0.1:$port");
$ua->server->url('https');
$tx = $ua->get('/secure');
ok $tx->success, 'successful';
ok !$tx->kept_alive, 'kept connection not alive';
ok $tx->keep_alive, 'keep connection alive';
is $tx->res->code, 200,           'right status';
is $tx->res->body, "https:$last", 'right content';
isnt $last, $port, 'different port';

done_testing();
