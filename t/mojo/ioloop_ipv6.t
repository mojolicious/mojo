use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::Server;
use Mojo::Promise;

plan skip_all => 'set TEST_IPV6 to enable this test (developer only!)' unless $ENV{TEST_IPV6} || $ENV{TEST_ALL};

use Mojo::IOLoop;

subtest 'IPv6 roundtrip' => sub {
  my ($server, $client);
  my $promise = Mojo::Promise->new;
  my $id      = Mojo::IOLoop->server(
    {address => '[::1]'} => sub {
      my ($loop, $stream) = @_;
      $stream->write('test' => sub { shift->write('321') });
      $stream->on(close => sub { $promise->resolve });
      $stream->on(read  => sub { $server .= pop });
    }
  );
  my $port     = Mojo::IOLoop->acceptor($id)->port;
  my $promise2 = Mojo::Promise->new;
  Mojo::IOLoop->client(
    {address => '[::1]', port => $port} => sub {
      my ($loop, $err, $stream) = @_;
      $stream->write('tset' => sub { shift->write('123') });
      $stream->on(close => sub { $promise2->resolve });
      $stream->on(read  => sub { $client .= pop });
      $stream->timeout(0.5);
    }
  );
  Mojo::Promise->all($promise, $promise2)->wait;
  is $server, 'tset123', 'right content';
  is $client, 'test321', 'right content';
};

done_testing();
