use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::IOLoop::Client;
use Mojo::UserAgent;

plan skip_all => 'set TEST_SOCKS to enable this test (developer only!)'
  unless $ENV{TEST_SOCKS};
plan skip_all => 'IO::Socket::SOCKS 0.63 required for this test!'
  unless Mojo::IOLoop::Client::SOCKS;

use Mojo::IOLoop;
use Mojo::IOLoop::Server;
use Mojo::IOLoop::Stream;

my $port   = Mojo::IOLoop::Server->generate_port;
my $server = IO::Socket::Socks->new(
  Blocking    => 0,
  Listen      => 10,
  ProxyAddr   => '127.0.0.1',
  ProxyPort   => $port,
  RequireAuth => 1,
  UserAuth    => sub { $_[0] eq 'foo' && $_[1] eq 'bar' }
);

Mojo::IOLoop->singleton->reactor->io(
  $server => sub {
    my $reactor = shift;
    my $client  = $server->accept;
    $client->blocking(0);
    my $done;
    $reactor->io(
      $client => sub {
        my $reactor = shift;
        my $err     = $IO::Socket::Socks::SOCKS_ERROR;
        if ($client->ready) {
          if ($done) {
            $reactor->remove($client);
            my $stream = Mojo::IOLoop::Stream->new($client);
            my $buffer = '';
            Mojo::IOLoop->stream($stream);
            $stream->on(
              read => sub {
                my ($stream, $chunk) = @_;
                $buffer .= $chunk;
                my $response = "HTTP/1.1 200 OK\x0d\x0a"
                  . "Content-Length: 3\x0d\x0a\x0d\x0aHi!";
                $stream->write($response => sub { shift->close })
                  if $buffer =~ /\x0d\x0a\x0d\x0a/;
              }
            );
          }
          else {
            my $command = $client->command;
            $client->command_reply(IO::Socket::Socks::REPLY_SUCCESS,
              $command->[1], $command->[2]);
            $done = 1;
          }
        }
        elsif ($err == IO::Socket::Socks::SOCKS_WANT_WRITE) {
          $reactor->watch($client, 1, 1);
        }
        elsif ($err == IO::Socket::Socks::SOCKS_WANT_READ) {
          $reactor->watch($client, 1, 0);
        }
      }
    );
  }
);

my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
$ua->proxy->http("socks://foo:bar\@127.0.0.1:$port");
my $tx = $ua->get('http://127.0.0.1:3000/');
is $tx->res->code, 200,   'right status';
is $tx->res->body, 'Hi!', 'right content';

done_testing();
