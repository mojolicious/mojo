use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::Server;

use Mojo::IOLoop;

my $delay = Mojo::IOLoop->delay;
my ($server, $client);
my $end = $delay->begin;
my $id  = Mojo::IOLoop->server(
  {address => '127.0.0.1'} => sub {
    my ($loop, $stream) = @_;
    $stream->write('test');
    $stream->on(eof => sub { shift->handle->write('321') });
    $stream->on(close => $end);
    $stream->on(read => sub { $server .= pop });
  }
);
my $port = Mojo::IOLoop->acceptor($id)->handle->sockport;
my $end2 = $delay->begin;
Mojo::IOLoop->client(
  {address => '127.0.0.1', port => $port} => sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset', sub { shift->handle->shutdown(1) });
    $stream->on(eof => sub { shift->handle->write('123') });
    $stream->on(close => $end2);
    $stream->on(read => sub { $client .= pop });
    $stream->timeout(0.5);
  }
);
$delay->wait;
is $server, 'tset', 'right content';
is $client, 'test321', 'right content';

done_testing();
