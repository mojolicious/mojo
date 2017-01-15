use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::TLS;

plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.94+ required for this test!'
  unless Mojo::IOLoop::TLS->can_tls;

use Mojo::IOLoop;
use Socket;

# Built-in certificate
socketpair(my $client_sock, my $server_sock, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
  or die "Couldn't create socket pair: $!";
$client_sock->blocking(0);
$server_sock->blocking(0);
my $delay  = Mojo::IOLoop->delay;
my $server = Mojo::IOLoop::TLS->new($server_sock);
$server->once(upgrade => $delay->begin);
$server->once(error => sub { warn pop });
$server->negotiate({server => 1});
my $client = Mojo::IOLoop::TLS->new($client_sock);
$client->once(upgrade => $delay->begin);
$client->once(error => sub { warn pop });
$client->negotiate;
my ($client_result, $server_result);
$delay->on(finish => sub { (undef, $server_result, $client_result) = @_ });
$delay->wait;
is ref $client_result, 'IO::Socket::SSL', 'right class';
is ref $server_result, 'IO::Socket::SSL', 'right class';

# Built-in certificate (custom event loop and cipher)
my $loop = Mojo::IOLoop->new;
socketpair($client_sock, $server_sock, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
  or die "Couldn't create socket pair: $!";
$client_sock->blocking(0);
$server_sock->blocking(0);
$delay  = $loop->delay;
$server = Mojo::IOLoop::TLS->new($server_sock)->reactor($loop->reactor);
$server->once(upgrade => $delay->begin);
$server->once(error => sub { warn pop });
$server->negotiate(server => 1, tls_ciphers => 'AES256-SHA:ALL');
$client = Mojo::IOLoop::TLS->new($client_sock)->reactor($loop->reactor);
$client->once(upgrade => $delay->begin);
$client->once(error => sub { warn pop });
$client->negotiate;
$client_result = $server_result = undef;
$delay->on(finish => sub { (undef, $server_result, $client_result) = @_ });
$delay->wait;
is ref $client_result, 'IO::Socket::SSL', 'right class';
is $client_result->get_cipher, 'AES256-SHA', 'AES256-SHA has been negotiatied';
is ref $server_result, 'IO::Socket::SSL', 'right class';
is $server_result->get_cipher, 'AES256-SHA', 'AES256-SHA has been negotiatied';

done_testing;
