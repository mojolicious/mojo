use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::Server;

plan skip_all => 'set TEST_IPV6 to enable this test (developer only!)'
  unless $ENV{TEST_IPV6};
plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.94+ required for this test!'
  unless Mojo::IOLoop::Server::TLS;

# To regenerate all required certificates run these commands (07.01.2016)
# openssl genrsa -out domain.key 1024
# openssl req -new -key domain.key -out domain.csr -subj "/C=US/CN=example.com"
# openssl x509 -req -days 7300 -in domain.csr -out domain.crt -CA ca.crt \
#   -CAkey ca.key -CAcreateserial
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/' => {text => 'works!'};

# CONNECT proxy server for testing
my (%buffer, $forward);
my $id = Mojo::IOLoop->server(
  {address => '[::1]'} => sub {
    my ($loop, $stream, $id) = @_;

    # Connection to client
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;

        # Write chunk from client to server
        my $server = $buffer{$id}{connection};
        return Mojo::IOLoop->stream($server)->write($chunk) if length $server;

        # Read connect request from client
        my $buffer = $buffer{$id}{client} .= $chunk;
        if ($buffer =~ /\x0d?\x0a\x0d?\x0a$/) {
          $buffer{$id}{client} = '';
          if ($buffer =~ /CONNECT \S+:\d+/) {

            # Connection to server
            $buffer{$id}{connection} = Mojo::IOLoop->client(
              {address => '[::1]', port => $forward} => sub {
                my ($loop, $err, $stream) = @_;

                # Connection to server failed
                if ($err) {
                  Mojo::IOLoop->remove($id);
                  return delete $buffer{$id};
                }

                # Start forwarding data in both directions
                Mojo::IOLoop->stream($id)
                  ->write("HTTP/1.1 200 OK\x0d\x0a"
                    . "Connection: keep-alive\x0d\x0a\x0d\x0a");
                $stream->on(
                  read => sub {
                    my ($stream, $chunk) = @_;
                    Mojo::IOLoop->stream($id)->write($chunk);
                  }
                );

                # Server closed connection
                $stream->on(
                  close => sub {
                    Mojo::IOLoop->remove($id);
                    delete $buffer{$id};
                  }
                );
              }
            );
          }

          # Invalid request from client
          else { Mojo::IOLoop->remove($id) }
        }
      }
    );

    # Client closed connection
    $stream->on(
      close => sub {
        my $buffer = delete $buffer{$id};
        Mojo::IOLoop->remove($buffer->{connection}) if $buffer->{connection};
      }
    );
  }
);
my $proxy = Mojo::IOLoop->acceptor($id)->port;

# IPv6 and TLS
my $daemon = Mojo::Server::Daemon->new(
  app    => app,
  listen => ['https://[::1]'],
  silent => 1
);
$daemon->start;
my $port = Mojo::IOLoop->acceptor($daemon->acceptors->[0])->port;
my $ua   = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
my $tx   = $ua->get("https://[::1]:$port/");
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
  $daemon->listen([$listen])->start;
  $forward = Mojo::IOLoop->acceptor($daemon->acceptors->[0])->port;
  $ua      = Mojo::UserAgent->new(
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
