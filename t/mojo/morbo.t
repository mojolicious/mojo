use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_MORBO to enable this test (developer only!)'
  unless $ENV{TEST_MORBO};

use File::Spec::Functions 'catdir';
use File::Temp 'tempdir';
use FindBin;
use IO::Socket::INET;
use Mojo::IOLoop::Server;
use Mojo::Server::Daemon;
use Mojo::Server::Morbo;
use Mojo::UserAgent;
use Mojo::Util 'spurt';
use Socket qw(SO_REUSEPORT SOL_SOCKET);

# Prepare script
my $dir = tempdir CLEANUP => 1;
my $script = catdir $dir, 'myapp.pl';
my $morbo = Mojo::Server::Morbo->new(watch => [$script]);
is $morbo->check, undef, 'file has not changed';
spurt <<EOF, $script;
use Mojolicious::Lite;

app->log->level('fatal');

get '/hello' => {text => 'Hello Morbo!'};

app->start;
EOF

# Start
my $port   = Mojo::IOLoop::Server->generate_port;
my $prefix = "$FindBin::Bin/../../script";
my $pid    = open my $server, '-|', $^X, "$prefix/morbo", '-l',
  "http://127.0.0.1:$port", $script;
sleep 1 while !_port($port);

my $ua = Mojo::UserAgent->new;

# Application is alive
my $tx = $ua->get("http://127.0.0.1:$port/hello");
ok $tx->is_finished, 'transaction is finished';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello Morbo!', 'right content';

# Same result
$tx = $ua->get("http://127.0.0.1:$port/hello");
ok $tx->is_finished, 'transaction is finished';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello Morbo!', 'right content';

# Update script without changing size
my ($size, $mtime) = (stat $script)[7, 9];
spurt <<EOF, $script;
use Mojolicious::Lite;

app->log->level('fatal');

get '/hello' => {text => 'Hello World!'};

app->start;
EOF
is $morbo->check, $script, 'file has changed';
ok((stat $script)[9] > $mtime, 'modify time has changed');
is((stat $script)[7], $size, 'still equal size');
sleep 3;

# Application has been reloaded
$tx = $ua->get("http://127.0.0.1:$port/hello");
ok $tx->is_finished, 'transaction is finished';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello World!', 'right content';

# Same result
$tx = $ua->get("http://127.0.0.1:$port/hello");
ok $tx->is_finished, 'transaction is finished';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello World!', 'right content';

# Update script without changing mtime
($size, $mtime) = (stat $script)[7, 9];
is $morbo->check, undef, 'file has not changed';
spurt <<EOF, $script;
use Mojolicious::Lite;

app->log->level('fatal');

get '/hello' => {text => 'Hello!'};

app->start;
EOF
utime $mtime, $mtime, $script;
is $morbo->check, $script, 'file has changed';
ok((stat $script)[9] == $mtime, 'modify time has not changed');
isnt((stat $script)[7], $size, 'size has changed');
sleep 3;

# Application has been reloaded again
$tx = $ua->get("http://127.0.0.1:$port/hello");
ok $tx->is_finished, 'transaction is finished';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'Hello!', 'right content';

# Same result
$tx = $ua->get("http://127.0.0.1:$port/hello");
ok $tx->is_finished, 'transaction is finished';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'Hello!', 'right content';

# Stop
kill 'INT', $pid;
sleep 1 while _port($port);

# SO_REUSEPORT
SKIP: {
  skip 'SO_REUSEPORT support required!', 2 unless eval { _reuse_port() };

  my $port   = Mojo::IOLoop::Server->generate_port;
  my $daemon = Mojo::Server::Daemon->new(
    listen => ["http://127.0.0.1:$port"],
    silent => 1
  )->start;
  ok !$daemon->ioloop->acceptor($daemon->acceptors->[0])
    ->handle->getsockopt(SOL_SOCKET, SO_REUSEPORT),
    'no SO_REUSEPORT socket option';
  $daemon = Mojo::Server::Daemon->new(
    listen => ["http://127.0.0.1:$port?reuse=1"],
    silent => 1
  );
  $daemon->start;
  ok $daemon->ioloop->acceptor($daemon->acceptors->[0])
    ->handle->getsockopt(SOL_SOCKET, SO_REUSEPORT),
    'SO_REUSEPORT socket option';
}

sub _port { IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => shift) }

sub _reuse_port {
  IO::Socket::INET->new(
    Listen    => 1,
    LocalPort => Mojo::IOLoop::Server->generate_port,
    ReusePort => 1
  );
}

done_testing();
