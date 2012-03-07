use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More;

use Cwd 'cwd';
use File::Temp;
use FindBin;
use IO::File;
use IO::Socket::INET;
use Mojo::Command;
use Mojo::IOLoop;
use Mojo::UserAgent;

plan skip_all => 'set TEST_HYPNOTOAD to enable this test (developer only!)'
  unless $ENV{TEST_HYPNOTOAD};
plan tests => 50;

# "I ate the blue ones... they taste like burning."
use Mojo::Server::Hypnotoad;

# Prepare script
my $cwd = cwd;
my $dir = File::Temp::tempdir(CLEANUP => 1);
chdir $dir;
my $command = Mojo::Command->new;
my $script  = $command->rel_file('myapp.pl');
my $port1   = Mojo::IOLoop->generate_port;
my $port2   = Mojo::IOLoop->generate_port;
$command->write_rel_file('myapp.pl', <<EOF);
use Mojolicious::Lite;

plugin Config => {
  default => {
    hypnotoad =>
      {listen => ['http://*:$port1', 'http://*:$port2'], workers => 1}
  }
};

app->log->level('fatal');

get '/hello' => {text => 'Hello Hypnotoad!'};

app->start;
EOF

# Start
my $prefix = "$FindBin::Bin/../../script";
open my $start, '-|', $^X, "$prefix/hypnotoad", $script;
sleep 1
  while !IO::Socket::INET->new(
  Proto    => 'tcp',
  PeerAddr => 'localhost',
  PeerPort => $port2
  );
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
$command->write_rel_file('myapp.pl', <<EOF);
use Mojolicious::Lite;

plugin Config => {
  default => {
    hypnotoad =>
      {listen => ['http://*:$port1', 'http://*:$port2'], workers => 1}
  }
};

app->log->level('fatal');

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

# Drop keep alive connections
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
sleep 1
  while IO::Socket::INET->new(
  Proto    => 'tcp',
  PeerAddr => 'localhost',
  PeerPort => $port2
  );

# Cleanup
chdir $cwd;

sub _pid {
  return
    unless my $file = IO::File->new($command->rel_file('hypnotoad.pid'), '<');
  my $pid = <$file>;
  chomp $pid;
  return $pid;
}
