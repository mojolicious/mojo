use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::Stream;
use Mojo::IOLoop::Client;

use Mojo::IOLoop;
use IO::Socket::IP;

my $delay = Mojo::IOLoop->delay;
my ($server, $client);
my $end = $delay->begin;

my $port = 54321;
my $sock = IO::Socket::IP->new(
    LocalPort => $port,
    Proto => 'udp',
    Blocking => 0,
) or die "socket: $@";

my $id;
$id = Mojo::IOLoop->recurring(0 => sub {
    my $chunk;
    $sock->recv($chunk, 1024);
    if ($chunk) {
        $server .= $chunk;
        $sock->send('PONG');
        Mojo::IOLoop->remove($id);
    };
});
Mojo::IOLoop->timer(0.5 => sub { Mojo::IOLoop->remove($id) if $id });

my $end2 = $delay->begin;
Mojo::IOLoop->client(
  {address => '127.0.0.1', port => $port, proto => 'udp'} => sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('PING');
    $stream->on(close => $end2);
    $stream->on(read => sub {
      $client .= pop;
      $stream->close;
    });
    $stream->timeout(0.5);
  }
);
$delay->wait;
is $server, 'PING', 'right content';
is $client, 'PONG', 'right content';

done_testing();
