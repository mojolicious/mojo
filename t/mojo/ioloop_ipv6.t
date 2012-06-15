use Mojo::Base -strict;

# Disable libev
BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::Server;
plan skip_all => 'set TEST_IPV6 to enable this test (developer only!)'
  unless $ENV{TEST_IPV6};
plan skip_all => 'IO::Socket::IP 0.12 required for this test!'
  unless Mojo::IOLoop::Server::IPV6;
plan tests => 2;

# "Remember, you can always find East by staring directly at the sun."
use Mojo::IOLoop;

# IPv6 roundtrip
my $loop = Mojo::IOLoop->new;
my $port = Mojo::IOLoop->generate_port;
my ($server, $client);
$loop->server(
  {address => '[::1]', port => $port} => sub {
    my ($loop, $stream) = @_;
    $stream->write('test', sub { shift->write('321') });
    $stream->on(read => sub { $server .= pop });
  }
);
$loop->client(
  {address => '[::1]', port => $port} => sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset', sub { shift->write('123') });
    $stream->on(read => sub { $client .= pop });
  }
);
$loop->timer(1 => sub { shift->stop });
$loop->start;
is $server, 'tset123', 'right content';
is $client, 'test321', 'right content';
