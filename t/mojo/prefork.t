use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;

plan skip_all => 'set TEST_PREFORK to enable this test (developer only!)'
  unless $ENV{TEST_PREFORK};

use List::Util 'first';
use Mojo::IOLoop;
use Mojo::Server::Prefork;
use Mojo::UserAgent;

# Basic functionality
my $port = Mojo::IOLoop->generate_port;
my $prefork = Mojo::Server::Prefork->new(listen => ["http://*:$port"]);
$prefork->unsubscribe('request');
$prefork->on(
  request => sub {
    my ($prefork, $tx) = @_;
    $tx->res->code(200);
    $tx->res->body('just works!');
    $tx->resume;
  }
);
is $prefork->workers, 4, 'start with four workers';
my (@spawn, @reap, $worker, $tx, $graceful);
$prefork->on(spawn => sub { push @spawn, pop });
$prefork->once(
  heartbeat => sub {
    my ($prefork, $pid) = @_;
    $worker = $pid;
    $tx     = Mojo::UserAgent->new->get("http://localhost:$port");
    kill 'QUIT', $$;
  }
);
$prefork->on(reap => sub { push @reap, pop });
$prefork->on(finish => sub { $graceful = pop });
$prefork->run;
is scalar @spawn, 4, 'four workers spawned';
is scalar @reap,  4, 'four workers reaped';
ok !!first { $worker eq $_ } @spawn, 'worker has a heartbeat';
ok $graceful, 'server has been stopped gracefully';
is_deeply [sort @spawn], [sort @reap], 'same process ids';
is $tx->res->code, 200,           'right status';
is $tx->res->body, 'just works!', 'right content';

# Process id and lock files
my $pid = $prefork->pid_file;
ok -e $pid, 'process id file has been created';
my $lock = $prefork->lock_file;
ok -e $lock, 'lock file has been created';
undef $prefork;
ok !-e $pid,  'process id file has been removed';
ok !-e $lock, 'lock file has been removed';

done_testing();
