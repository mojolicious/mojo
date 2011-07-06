#!/usr/bin/env perl

use strict;
use warnings;

# Disable Bonjour, IPv6, epoll and kqueue
BEGIN { $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1 }

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
plan tests => 26;

# "I ate the blue ones... they taste like burning."
use_ok 'Mojo::Server::Hypnotoad';

# Prepare script
my $cwd = cwd;
my $dir = File::Temp::tempdir(CLEANUP => 1);
chdir $dir;
my $command = Mojo::Command->new;
my $script  = $command->rel_file('myapp.pl');
$command->write_rel_file('myapp.pl', <<EOF);
use Mojolicious::Lite;

app->log->level('fatal');

get '/hello' => {text => 'Hello Hypnotoad!'};

app->start;
EOF

# Prepare config
my $port = Mojo::IOLoop->generate_port;
$command->write_rel_file('hypnotoad.conf', <<EOF);
{listen => "http://*:$port", workers => 1};
EOF

# Start
my $prefix = "$FindBin::Bin/../../script";
open my $start, '-|', $^X, "$prefix/hypnotoad", $script;
sleep 1
  while !IO::Socket::INET->new(
  Proto    => 'tcp',
  PeerAddr => 'localhost',
  PeerPort => $port
  );
my $old = _pid();

my $ua = Mojo::UserAgent->new;

# Application is alive
my $tx = $ua->get("http://127.0.0.1:$port/hello");
ok $tx->is_done,    'transaction is done';
is $tx->keep_alive, 1, 'connection will be kept alive';
is $tx->kept_alive, undef, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Same result
$tx = $ua->get("http://127.0.0.1:$port/hello");
ok $tx->is_done,    'transaction is done';
is $tx->keep_alive, 1, 'connection will be kept alive';
is $tx->kept_alive, 1, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Update script
$command->write_rel_file('myapp.pl', <<EOF);
use Mojolicious::Lite;

app->log->level('fatal');

get '/hello' => {text => 'Hello World!'};

app->start;
EOF
open my $hot_deploy, '-|', $^X, "$prefix/hypnotoad", $script;

# Keep alive connection
$tx = $ua->get("http://127.0.0.1:$port/hello");
ok $tx->is_done,    'transaction is done';
is $tx->keep_alive, 1, 'connection will be kept alive';
is $tx->kept_alive, 1, 'connection was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Drop keep alive connections
$ua = Mojo::UserAgent->new;

# Wait for hot deployment to finish
while (1) {
  sleep 1;
  $tx = Mojo::UserAgent->new->get("http://127.0.0.1:$port/hello");
  next unless $tx->res->body eq 'Hello World!';
  next unless my $new = _pid();
  last if $new ne $old;
}

# Application is alive
$tx = $ua->get("http://127.0.0.1:$port/hello");
ok $tx->is_done,    'transaction is done';
is $tx->keep_alive, 1, 'connection will be kept alive';
is $tx->kept_alive, undef, 'connection was not kept alive';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello World!', 'right content';

# Same result
$tx = $ua->get("http://127.0.0.1:$port/hello");
ok $tx->is_done,    'transaction is done';
is $tx->keep_alive, 1, 'connection will be kept alive';
is $tx->kept_alive, 1, 'connection was kept alive';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello World!', 'right content';

# Stop
open my $stop, '-|', $^X, "$prefix/hypnotoad", $script, '--stop';
sleep 1
  while IO::Socket::INET->new(
  Proto    => 'tcp',
  PeerAddr => 'localhost',
  PeerPort => $port
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
