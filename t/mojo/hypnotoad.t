use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_HYPNOTOAD to enable this test (developer only!)'
  unless $ENV{TEST_HYPNOTOAD} || $ENV{TEST_ALL};

use IO::Socket::INET;
use Mojo::File qw(curfile tempdir);
use Mojo::IOLoop::Server;
use Mojo::Server::Hypnotoad;
use Mojo::UserAgent;

subtest 'Configure' => sub {
  my $hypnotoad = Mojo::Server::Hypnotoad->new;
  $hypnotoad->prefork->app->config->{myserver} = {
    accepts            => 13,
    backlog            => 43,
    clients            => 1,
    graceful_timeout   => 23,
    heartbeat_interval => 7,
    heartbeat_timeout  => 9,
    inactivity_timeout => 5,
    keep_alive_timeout => 3,
    listen             => ['http://*:8081'],
    pid_file           => '/foo/bar.pid',
    proxy              => 1,
    requests           => 3,
    spare              => 4,
    trusted_proxies    => ['127.0.0.0/8'],
    upgrade_timeout    => 45,
    workers            => 7
  };
  is $hypnotoad->upgrade_timeout, 180, 'right default';
  $hypnotoad->configure('test');
  is_deeply $hypnotoad->prefork->listen, ['http://*:8080'], 'right value';
  $hypnotoad->configure('myserver');
  is $hypnotoad->prefork->accepts,            13, 'right value';
  is $hypnotoad->prefork->backlog,            43, 'right value';
  is $hypnotoad->prefork->graceful_timeout,   23, 'right value';
  is $hypnotoad->prefork->heartbeat_interval, 7,  'right value';
  is $hypnotoad->prefork->heartbeat_timeout,  9,  'right value';
  is $hypnotoad->prefork->inactivity_timeout, 5,  'right value';
  is $hypnotoad->prefork->keep_alive_timeout, 3,  'right value';
  is_deeply $hypnotoad->prefork->listen, ['http://*:8081'], 'right value';
  is $hypnotoad->prefork->max_clients,  1,              'right value';
  is $hypnotoad->prefork->max_requests, 3,              'right value';
  is $hypnotoad->prefork->pid_file,     '/foo/bar.pid', 'right value';
  ok $hypnotoad->prefork->reverse_proxy, 'reverse proxy enabled';
  is $hypnotoad->prefork->spare, 4, 'right value';
  is_deeply $hypnotoad->prefork->trusted_proxies, ['127.0.0.0/8'], 'right value';
  is $hypnotoad->prefork->workers, 7,  'right value';
  is $hypnotoad->upgrade_timeout,  45, 'right value';
};

subtest 'Hot deployment' => sub {
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

app->log->level('trace');

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

  my $prefix = curfile->dirname->dirname->sibling('script');
  open my $start, '-|', $^X, "$prefix/hypnotoad", $script;
  sleep 3;
  sleep 1 while !_port($port2);
  my $old = _pid($dir->child('hypnotoad.pid'));
  my $ua  = Mojo::UserAgent->new;

  subtest 'Application is alive' => sub {
    my $tx = $ua->get("http://127.0.0.1:$port1/hello");
    ok $tx->is_finished, 'transaction is finished';
    ok $tx->keep_alive,  'connection will be kept alive';
    ok !$tx->kept_alive, 'connection was not kept alive';
    is $tx->res->code, 200,                'right status';
    is $tx->res->body, 'Hello Hypnotoad!', 'right content';

    $tx = $ua->get("http://127.0.0.1:$port2/hello");
    ok $tx->is_finished, 'transaction is finished';
    ok $tx->keep_alive,  'connection will be kept alive';
    ok !$tx->kept_alive, 'connection was not kept alive';
    is $tx->res->code, 200,                'right status';
    is $tx->res->body, 'Hello Hypnotoad!', 'right content';

    $tx = $ua->get("http://127.0.0.1:$port1/hello");
    ok $tx->is_finished, 'transaction is finished';
    ok $tx->keep_alive,  'connection will be kept alive';
    ok $tx->kept_alive,  'connection was kept alive';
    is $tx->res->code, 200,                'right status';
    is $tx->res->body, 'Hello Hypnotoad!', 'right content';

    $tx = $ua->get("http://127.0.0.1:$port2/hello");
    ok $tx->is_finished, 'transaction is finished';
    ok $tx->keep_alive,  'connection will be kept alive';
    ok $tx->kept_alive,  'connection was kept alive';
    is $tx->res->code, 200,                'right status';
    is $tx->res->body, 'Hello Hypnotoad!', 'right content';
  };

  $script->spurt(<<'EOF');
use Mojolicious::Lite;

die if $ENV{HYPNOTOAD_PID};

app->start;
EOF
  open my $hot_deploy, '-|', $^X, "$prefix/hypnotoad", $script;

  while (1) {
    last if $log->slurp =~ qr/Zero downtime software upgrade failed/;
    sleep 1;
  }

  subtest 'Connection did not get lost' => sub {
    my $tx = $ua->get("http://127.0.0.1:$port1/hello");
    ok $tx->is_finished, 'transaction is finished';
    ok $tx->keep_alive,  'connection will be kept alive';
    ok $tx->kept_alive,  'connection was kept alive';
    is $tx->res->code, 200,                'right status';
    is $tx->res->body, 'Hello Hypnotoad!', 'right content';

    $tx = $ua->get("http://127.0.0.1:$port2/hello");
    ok $tx->is_finished, 'transaction is finished';
    ok $tx->keep_alive,  'connection will be kept alive';
    ok $tx->kept_alive,  'connection was kept alive';
    is $tx->res->code, 200,                'right status';
    is $tx->res->body, 'Hello Hypnotoad!', 'right content';
  };

  subtest 'Request that will be served after graceful shutdown has been initiated' => sub {
    my $tx = $ua->build_tx(GET => "http://127.0.0.1:$port1/graceful");
    $ua->start($tx => sub { });
    Mojo::IOLoop->one_tick until $tx->req->is_finished;

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

app->log->level('trace');

get '/hello' => sub { shift->render(text => "Hello World \$\$!") };

app->start;
EOF
    open $hot_deploy, '-|', $^X, "$prefix/hypnotoad", $script;

    while (1) {
      sleep 1;
      next unless my $new = _pid($dir->child('hypnotoad.pid'));
      last if $new ne $old;
    }

    Mojo::IOLoop->one_tick until $tx->is_finished;
    ok !$tx->keep_alive, 'connection will not be kept alive';
    ok !$tx->kept_alive, 'connection was not kept alive';
    is $tx->res->code, 200,                  'right status';
    is $tx->res->body, 'Graceful shutdown!', 'right content';
  };

  subtest 'One uncertain request that may or may not be served by the old worker' => sub {
    my $tx = $ua->get("http://127.0.0.1:$port1/hello");
    is $tx->res->code, 200, 'right status';
    $tx = $ua->get("http://127.0.0.1:$port2/hello");
    is $tx->res->code, 200, 'right status';
  };

  subtest 'Application has been reloaded' => sub {
    my $tx = $ua->get("http://127.0.0.1:$port1/hello");
    ok $tx->is_finished, 'transaction is finished';
    ok !$tx->keep_alive, 'connection will not be kept alive';
    ok !$tx->kept_alive, 'connection was not kept alive';
    is $tx->res->code, 200, 'right status';
    my $first = $tx->res->body;
    like $first, qr/Hello World \d+!/, 'right content';

    $tx = $ua->get("http://127.0.0.1:$port2/hello");
    ok $tx->is_finished, 'transaction is finished';
    ok !$tx->keep_alive, 'connection will not be kept alive';
    ok !$tx->kept_alive, 'connection was not kept alive';
    is $tx->res->code, 200,    'right status';
    is $tx->res->body, $first, 'same content';

    $tx = $ua->get("http://127.0.0.1:$port1/hello");
    ok $tx->is_finished, 'transaction is finished';
    ok !$tx->keep_alive, 'connection will not be kept alive';
    ok !$tx->kept_alive, 'connection was not kept alive';
    is $tx->res->code, 200, 'right status';
    my $second = $tx->res->body;
    isnt $first, $second, 'different content';
    like $second, qr/Hello World \d+!/, 'right content';

    $tx = $ua->get("http://127.0.0.1:$port2/hello");
    ok $tx->is_finished, 'transaction is finished';
    ok !$tx->keep_alive, 'connection will not be kept alive';
    ok !$tx->kept_alive, 'connection was not kept alive';
    is $tx->res->code, 200,     'right status';
    is $tx->res->body, $second, 'same content';
  };

  open my $stop, '-|', $^X, "$prefix/hypnotoad", $script, '-s';
  sleep 1 while _port($port2);

  subtest 'Check log' => sub {
    my $log = $log->slurp;
    like $log, qr/Worker \d+ started/,                                      'right message';
    like $log, qr/Starting zero downtime software upgrade \(180 seconds\)/, 'right message';
    like $log, qr/Upgrade successful, stopping $old/,                       'right message';
  };
};

sub _pid {
  my $path = shift;
  return undef unless open my $file, '<', $path;
  my $pid = <$file>;
  chomp $pid;
  return $pid;
}

sub _port { IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => shift) }

done_testing();
