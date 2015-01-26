use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_HYPNOTOAD to enable this test (developer only!)'
  unless $ENV{TEST_HYPNOTOAD};

use File::Spec::Functions 'catdir';
use File::Temp 'tempdir';
use FindBin;
use IO::Socket::INET;
use Mojo::IOLoop::Server;
use Mojo::Server::Hypnotoad;
use Mojo::UserAgent;
use Mojo::Util qw(slurp spurt);

# Configure
{
  my $hypnotoad = Mojo::Server::Hypnotoad->new;
  $hypnotoad->prefork->app->config->{myserver} = {
    accept_interval     => 33,
    accepts             => 13,
    backlog             => 43,
    clients             => 1,
    graceful_timeout    => 23,
    group               => 'testers',
    heartbeat_interval  => 7,
    heartbeat_timeout   => 9,
    keep_alive_requests => 3,
    inactivity_timeout  => 5,
    listen              => ['http://*:8081'],
    lock_file           => '/foo/bar.lock',
    lock_timeout        => 14,
    multi_accept        => 16,
    pid_file            => '/foo/bar.pid',
    proxy               => 1,
    upgrade_timeout     => 45,
    user                => 'tester',
    workers             => 7
  };
  is $hypnotoad->upgrade_timeout, 60, 'right default';
  $hypnotoad->configure('test');
  is_deeply $hypnotoad->prefork->listen, ['http://*:8080'], 'right value';
  $hypnotoad->configure('myserver');
  is $hypnotoad->prefork->accept_interval,    33,        'right value';
  is $hypnotoad->prefork->accepts,            13,        'right value';
  is $hypnotoad->prefork->backlog,            43,        'right value';
  is $hypnotoad->prefork->graceful_timeout,   23,        'right value';
  is $hypnotoad->prefork->group,              'testers', 'right value';
  is $hypnotoad->prefork->heartbeat_interval, 7,         'right value';
  is $hypnotoad->prefork->heartbeat_timeout,  9,         'right value';
  is $hypnotoad->prefork->inactivity_timeout, 5,         'right value';
  is_deeply $hypnotoad->prefork->listen, ['http://*:8081'], 'right value';
  is $hypnotoad->prefork->lock_file,    '/foo/bar.lock', 'right value';
  is $hypnotoad->prefork->lock_timeout, 14,              'right value';
  is $hypnotoad->prefork->max_clients,  1,               'right value';
  is $hypnotoad->prefork->max_requests, 3,               'right value';
  is $hypnotoad->prefork->multi_accept, 16,              'right value';
  is $hypnotoad->prefork->pid_file,     '/foo/bar.pid',  'right value';
  ok $hypnotoad->prefork->reverse_proxy, 'reverse proxy enabled';
  is $hypnotoad->prefork->user,          'tester', 'right value';
  is $hypnotoad->prefork->workers,       7, 'right value';
  is $hypnotoad->upgrade_timeout, 45, 'right value';
}

# Prepare script
my $dir = tempdir CLEANUP => 1;
my $script = catdir $dir, 'myapp.pl';
my $log    = catdir $dir, 'mojo.log';
my $port1  = Mojo::IOLoop::Server->generate_port;
my $port2  = Mojo::IOLoop::Server->generate_port;
spurt <<EOF, $script;
use Mojolicious::Lite;

app->log->path('$log');

plugin Config => {
  default => {
    hypnotoad => {
      inactivity_timeout => 3,
      listen => ['http://127.0.0.1:$port1', 'http://127.0.0.1:$port2'],
      workers => 1
    }
  }
};

app->log->level('debug');

get '/hello' => {text => 'Hello Hypnotoad!'};

app->start;
EOF

# Start
my $prefix = "$FindBin::Bin/../../script";
open my $start, '-|', $^X, "$prefix/hypnotoad", $script;
sleep 3;
sleep 1 while !_port($port2);
my $old = _pid();

my $ua = Mojo::UserAgent->new;

# Application is alive
my $tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Application is alive (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Same result
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Same result (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Update script
spurt <<EOF, $script;
use Mojolicious::Lite;

app->log->path('$log');

plugin Config => {
  default => {
    hypnotoad => {
      inactivity_timeout => 3,
      listen => ['http://127.0.0.1:$port1', 'http://127.0.0.1:$port2'],
      workers => 1
    }
  }
};

app->log->level('debug');

get '/hello' => {text => 'Hello World!'};

app->start;
EOF
open my $hot_deploy, '-|', $^X, "$prefix/hypnotoad", $script;

# Connection did not get lost
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Connection did not get lost (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Remove keep-alive connections
$ua = Mojo::UserAgent->new;

# Wait for hot deployment to finish
while (1) {
  sleep 1;
  next unless my $new = _pid();
  last if $new ne $old;
}

# Application has been reloaded
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello World!', 'right content';

# Application has been reloaded (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello World!', 'right content';

# Same result
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was kept alive';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello World!', 'right content';

# Same result (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was kept alive';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello World!', 'right content';

# Stop
open my $stop, '-|', $^X, "$prefix/hypnotoad", $script, '-s';
sleep 1 while _port($port2);

# Check log
$log = slurp $log;
like $log, qr/Worker \d+ started/,                      'right message';
like $log, qr/Starting zero downtime software upgrade/, 'right message';
like $log, qr/Upgrade successful, stopping $old/,       'right message';

sub _pid {
  return undef unless open my $file, '<', catdir($dir, 'hypnotoad.pid');
  my $pid = <$file>;
  chomp $pid;
  return $pid;
}

sub _port { IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => shift) }

done_testing();
