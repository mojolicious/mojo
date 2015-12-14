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

use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/' => {text => 'works!'};

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

done_testing();
