use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::TLS 'HAS_TLS';

plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.94+ required for this test!' unless HAS_TLS;

use Mojo::IOLoop;
use Socket;

# Built-in certificate
my $loop = Mojo::IOLoop->new;
socketpair(my $client_sock, my $server_sock, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
  or die "Couldn't create socket pair: $!";
$client_sock->blocking(0);
$server_sock->blocking(0);
my $delay  = $loop->delay;
my $server = Mojo::IOLoop::TLS->new($server_sock)->reactor($loop->reactor);
$server->once(upgrade => $delay->begin);
$server->once(error => sub { warn pop });
$server->negotiate(server => 1);
my $client = Mojo::IOLoop::TLS->new($client_sock)->reactor($loop->reactor);
$client->once(upgrade => $delay->begin);
$client->once(error => sub { warn pop });
$client->negotiate;
my ($client_result, $server_result);
$delay->on(finish => sub { (undef, $server_result, $client_result) = @_ });
$delay->wait;
is ref $client_result, 'IO::Socket::SSL', 'right class';
is ref $server_result, 'IO::Socket::SSL', 'right class';

done_testing;
