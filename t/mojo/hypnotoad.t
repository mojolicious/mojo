use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_HYPNOTOAD to enable this test (developer only!)'
  unless $ENV{TEST_HYPNOTOAD};

use FindBin;
use IO::Socket::INET;
use Mojo::File 'tempdir';
use Mojo::IOLoop::Server;
use Mojo::Server::Hypnotoad;
use Mojo::UserAgent;

# Configure
{
  my $hypnotoad = Mojo::Server::Hypnotoad->new;
  $hypnotoad->prefork->app->config->{myserver} = {
    accepts            => 13,
    backlog            => 43,
    clients            => 1,
    graceful_timeout   => 23,
    heartbeat_interval => 7,
    heartbeat_timeout  => 9,
    inactivity_timeout => 5,
    listen             => ['http://*:8081'],
    pid_file           => '/foo/bar.pid',
    proxy              => 1,
    requests           => 3,
    upgrade_timeout    => 45,
    workers            => 7
  };
  is $hypnotoad->upgrade_timeout, 60, 'right default';
  $hypnotoad->configure('test');
  is_deeply $hypnotoad->prefork->listen, ['http://*:8080'], 'right value';
  $hypnotoad->configure('myserver');
  is $hypnotoad->prefork->accepts,            13, 'right value';
  is $hypnotoad->prefork->backlog,            43, 'right value';
  is $hypnotoad->prefork->graceful_timeout,   23, 'right value';
  is $hypnotoad->prefork->heartbeat_interval, 7,  'right value';
  is $hypnotoad->prefork->heartbeat_timeout,  9,  'right value';
  is $hypnotoad->prefork->inactivity_timeout, 5,  'right value';
  is_deeply $hypnotoad->prefork->listen, ['http://*:8081'], 'right value';
  is $hypnotoad->prefork->max_clients,  1,              'right value';
  is $hypnotoad->prefork->max_requests, 3,              'right value';
  is $hypnotoad->prefork->pid_file,     '/foo/bar.pid', 'right value';
  ok $hypnotoad->prefork->reverse_proxy, 'reverse proxy enabled';
  is $hypnotoad->prefork->workers, 7, 'right value';
  is $hypnotoad->upgrade_timeout, 45, 'right value';
}

# Prepare script
my $dir    = tempdir;
my $script = $dir->child('myapp.pl');
my $log    = $dir->child('mojo.log');
my $port1  = Mojo::IOLoop::Server->generate_port;
my $port2  = Mojo::IOLoop::Server->generate_port;
$script->spurt(<<EOF);
use Mojolicious::Lite;
use Mojo::IOLoop;

app->log->path('$log');

plugin Config => {
  default => {
    hypnotoad => {
      listen => ['http://127.0.0.1:$port1', 'http://127.0.0.1:$port2'],
      workers => 1
    }
  }
};

app->log->level('debug');

get '/hello' => {text => 'Hello Hypnotoad!'};

my \$graceful;
Mojo::IOLoop->singleton->on(finish => sub { \$graceful++ });

get '/graceful' => sub {
  my \$c = shift;
  my \$id;
  \$id = Mojo::IOLoop->recurring(0 => sub {
    return unless \$graceful;
    \$c->render(text => 'Graceful shutdown!');
    Mojo::IOLoop->remove(\$id);
  });
};

app->start;
EOF

# Start
my $prefix = "$FindBin::Bin/../../script";
open my $start, '-|', $^X, "$prefix/hypnotoad", $script;
sleep 3;
sleep 1 while !_port($port2);
my $old = _pid();

# Application is alive
my $ua = Mojo::UserAgent->new;
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
ok $tx->kept_alive,  'connection was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Same result (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Update script (broken)
$script->spurt(<<'EOF');
use Mojolicious::Lite;

die if $ENV{HYPNOTOAD_PID};

app->start;
EOF
open my $hot_deploy, '-|', $^X, "$prefix/hypnotoad", $script;

# Wait for hot deployment to fail
while (1) {
  last if $log->slurp =~ qr/Zero downtime software upgrade failed/;
  sleep 1;
}

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

# Request that will be served after graceful shutdown has been initiated
$tx = $ua->build_tx(GET => "http://127.0.0.1:$port1/graceful");
$ua->start($tx => sub { });
Mojo::IOLoop->one_tick until $tx->req->is_finished;

# Update script
$script->spurt(<<EOF);
use Mojolicious::Lite;

app->log->path('$log');

plugin Config => {
  default => {
    hypnotoad => {
      accepts => 2,
      inactivity_timeout => 3,
      listen => ['http://127.0.0.1:$port1', 'http://127.0.0.1:$port2'],
      requests => 1,
      workers => 1
    }
  }
};

app->log->level('debug');

get '/hello' => sub { shift->render(text => "Hello World \$\$!") };

app->start;
EOF
open $hot_deploy, '-|', $^X, "$prefix/hypnotoad", $script;

# Wait for hot deployment to finish
while (1) {
  sleep 1;
  next unless my $new = _pid();
  last if $new ne $old;
}

# Request that will be served by an old worker that is still running
Mojo::IOLoop->one_tick until $tx->is_finished;
ok !$tx->keep_alive, 'connection will not be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Graceful shutdown!', 'right content';

# Application has been reloaded
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok !$tx->keep_alive, 'connection will not be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
my $first = $tx->res->body;
like $first, qr/Hello World \d+!/, 'right content';

# Application has been reloaded (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok !$tx->keep_alive, 'connection will not be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, $first, 'same content';

# Same result
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok !$tx->keep_alive, 'connection will not be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
my $second = $tx->res->body;
isnt $first, $second, 'different content';
like $second, qr/Hello World \d+!/, 'right content';

# Same result (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok !$tx->keep_alive, 'connection will not be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, $second, 'same content';

# Stop
open my $stop, '-|', $^X, "$prefix/hypnotoad", $script, '-s';
sleep 1 while _port($port2);

# Check log
$log = $log->slurp;
like $log, qr/Worker \d+ started/,                      'right message';
like $log, qr/Starting zero downtime software upgrade/, 'right message';
like $log, qr/Upgrade successful, stopping $old/,       'right message';

sub _pid {
  return undef unless open my $file, '<', $dir->child('hypnotoad.pid');
  my $pid = <$file>;
  chomp $pid;
  return $pid;
}

sub _port { IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => shift) }

done_testing();
