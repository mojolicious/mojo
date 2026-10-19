use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Config;

plan skip_all => 'set TEST_MORBO to enable this test (developer only!)' unless $ENV{TEST_MORBO} || $ENV{TEST_ALL};
plan skip_all => 'Morbo does not support fork emulation' if $Config{d_pseudofork};

use Mojo::File qw(curfile tempdir);
use lib curfile->sibling('lib')->to_string;

use IO::Socket::INET ();
use Mojo::IOLoop::Server;
use Mojo::Server::Daemon;
use Mojo::Server::Morbo;
use Mojo::Server::Morbo::Backend;
use Mojo::UserAgent;
use Mojo::Util  qw(steady_time);
use Socket      qw(SO_REUSEPORT SOL_SOCKET);
use Time::HiRes qw(sleep);

my $dir   = tempdir;
my $morbo = curfile->dirname->dirname->sibling('script', 'morbo')->to_string;
my $ua    = Mojo::UserAgent->new;

subtest 'Watch for modified files' => sub {
  my $subdir = $dir->child('modified', 'stuff')->make_path;
  my $file   = $subdir->child('test.txt')->spew('Hello');
  my $morbo  = Mojo::Server::Morbo->new;
  $morbo->backend->watch([$subdir->dirname]);
  $morbo->backend->modified_files;
  is_deeply $morbo->backend->modified_files, [], 'no files have changed';

  my ($size, $mtime) = (stat $file)[7, 9];
  $file->spew('World');
  utime $mtime + 1, $mtime + 1, $file;
  is_deeply $morbo->backend->modified_files, [$file], 'file has changed';
  ok((stat $file)[9] > $mtime, 'modify time has changed');
  is((stat $file)[7], $size, 'still equal size');
  is_deeply $morbo->backend->modified_files, [], 'no files have changed';

  $mtime = (stat $file)[9];
  $file->spew('Hello World');
  utime $mtime, $mtime, $file;
  is_deeply $morbo->backend->modified_files, [$file], 'file has changed';
  ok((stat $file)[9] == $mtime, 'modify time has not changed');
  isnt((stat $file)[7], $size, 'size has changed');
  is_deeply $morbo->backend->modified_files, [], 'no files have changed';
};

subtest 'Watch for new and deleted files' => sub {
  my $subdir = $dir->child('new')->make_path;
  my $morbo  = Mojo::Server::Morbo->new;
  $morbo->backend->watch([$subdir]);
  is_deeply $morbo->backend->modified_files, [], 'no files have changed';

  my @new = map { $subdir->child("$_.txt") } qw(test testing);
  $_->spew('whatever') for @new;
  is_deeply $morbo->backend->modified_files, \@new, 'two files have been created';
  is_deeply $morbo->backend->modified_files, [],    'no files have changed';
  $subdir->child('.hidden.txt')->spew('whatever');
  is_deeply $morbo->backend->modified_files, [], 'hidden files are ignored';

  unlink $new[0];
  is_deeply $morbo->backend->modified_files, [$new[0]], 'file has been deleted';
  is_deeply $morbo->backend->modified_files, [],        'no files have changed';
};

subtest 'Broken symlink' => sub {
  plan skip_all => 'Symlink support required!' unless eval { symlink '', ''; 1 };
  my $subdir = $dir->child('symlink')->make_path;
  my $morbo  = Mojo::Server::Morbo->new;
  $morbo->backend->watch([$subdir]);
  my $broken = $subdir->child('broken.txt');
  symlink $subdir->child('missing.txt'), $broken;
  ok -l $broken,  'symlink created';
  ok !-f $broken, 'symlink target does not exist';
  my $warned;
  local $SIG{__WARN__} = sub { $warned++ };
  is_deeply $morbo->backend->modified_files, [], 'no files have changed';
  ok !$warned, 'no warnings';
};

subtest 'Default command (daemon)' => sub {
  my $script = _app('daemon.pl', 'Hello Morbo!');
  my $port   = Mojo::IOLoop::Server->generate_port;
  my $log    = $dir->child('daemon.log');
  my $pid    = _morbo($log, '-v', '-l', "http://127.0.0.1:$port", $script);
  ok _wait_for($port, 'Hello Morbo!'), 'server has been started';
  ok _wait_for($port, 'Hello Morbo!'), 'same result';

  _app('daemon.pl', 'Hello World!');
  ok _wait_for($port, 'Hello World!'), 'server has been restarted';
  like $log->slurp, qr/File ".*daemon\.pl" changed, restarting/, 'right message';
  is $ua->get("http://127.0.0.1:$port/server")->res->body, 'Mojo::Server::Daemon', 'right server';

  _app('daemon.pl', 'Failed!', q{hook before_server_start => sub { app->routes->find('hello')->to(text => 'Hook!') };});
  ok _wait_for($port, 'Hook!'), 'server has been restarted again';

  _stop($pid, $port);
};

subtest 'Prefork command with arguments' => sub {
  my $script = _app('prefork.pl', 'Hello Prefork!');
  my $port   = Mojo::IOLoop::Server->generate_port;
  my $pid    = _morbo($dir->child('prefork.log'), '-l', "http://127.0.0.1:$port", $script, 'prefork', '-w', 2);
  ok _wait_for($port, 'Hello Prefork!'), 'server has been started';

  _app('prefork.pl', 'Hello Again!');
  ok _wait_for($port, 'Hello Again!'), 'server has been restarted';
  is $ua->get("http://127.0.0.1:$port/server")->res->body, 'Mojo::Server::Prefork', 'right server';

  _stop($pid, $port);
};

subtest 'Recover from broken application' => sub {
  my $script = _app('broken.pl', 'Hello!');
  my $port   = Mojo::IOLoop::Server->generate_port;
  my $log    = $dir->child('broken.log');
  my $pid    = _morbo($log, '-l', "http://127.0.0.1:$port", $script);
  ok _wait_for($port, 'Hello!'), 'server has been started';

  $script->spew('use Mojolicious::Lite; get "/hello" => {text => "Broken!"; app->start;');
  my $deadline = steady_time + 30;
  sleep 0.1 until $log->slurp =~ /syntax error/ || steady_time > $deadline;
  like $log->slurp, qr/syntax error/, 'application is broken';

  _app('broken.pl', 'Fixed!');
  ok _wait_for($port, 'Fixed!'), 'server has been restarted after fixing the application';

  _stop($pid, $port);
};

subtest 'Kill server that does not stop' => sub {
  my $extra  = q{Mojo::IOLoop->next_tick(sub { $SIG{TERM} = 'IGNORE' });};
  my $script = _app('stuck.pl', 'Stuck!', $extra);
  my $port   = Mojo::IOLoop::Server->generate_port;
  my $pid    = _morbo($dir->child('stuck.log'), '-l', "http://127.0.0.1:$port", $script);
  ok _wait_for($port, 'Stuck!'), 'server has been started';

  my $start = steady_time;
  _app('stuck.pl', 'Unstuck!', $extra);
  ok _wait_for($port, 'Unstuck!'), 'server has been killed and restarted';
  ok steady_time - $start >= 4,    'server got time to stop';

  _stop($pid, $port);
};

subtest 'Stop subprocesses' => sub {
  my $file = $dir->child('subprocess.pid');
  my $extra
    = qq{die unless defined(my \$pid = fork); unless (\$pid) { sleep 1000; exit 0 } path('$file')->spew(\$pid);};
  my $script = _app('subprocess.pl', 'Hello!', $extra);
  my $port   = Mojo::IOLoop::Server->generate_port;
  my $pid    = _morbo($dir->child('subprocess.log'), '-l', "http://127.0.0.1:$port", $script);
  ok _wait_for($port, 'Hello!'),    'server has been started';
  ok my $subprocess = $file->slurp, 'subprocess has been started';
  ok kill(0, $subprocess),          'subprocess is running';

  _stop($pid, $port);
  my $deadline = steady_time + 30;
  sleep 0.1 while kill(0, $subprocess) && steady_time < $deadline;
  ok !kill(0, $subprocess), 'subprocess has been stopped';
};

subtest 'Exec commands' => sub {
  my $file = $dir->child('exec.txt');
  my $cmd  = $dir->child('exec.pl')->spew(<<EOF);
use Mojo::File qw(path);
die unless defined(my \$pid = fork);
unless (\$pid) { sleep 1000; exit 0 }
path('$file')->spew("\$\$ \$pid \$ENV{MOJO_MODE}");
sleep 1000;
EOF
  my $script = _app('exec_app.pl', 'Hello Exec!');
  my $port   = Mojo::IOLoop::Server->generate_port;
  my $log    = $dir->child('exec.log');
  my $pid = _morbo($log, '-l', "http://127.0.0.1:$port", '-x', qq{"$^X" "$cmd"}, '-x', qq{"$^X" -e "exit 3"}, $script);
  ok _wait_for($port, 'Hello Exec!'), 'server has been started';
  ok _wait_until(sub { -s $file }),   'command has been started';
  my ($command, $subprocess, $mode) = split ' ', $file->slurp;
  is $mode, 'development', 'right mode';
  ok kill(0, $command),    'command is running';
  ok kill(0, $subprocess), 'subprocess of command is running';
  ok _wait_until(sub { $log->slurp =~ /Command ".+exit 3"" exited with status 3\./ }), 'right message';

  _app('exec_app.pl', 'Hello Again!');
  ok _wait_for($port, 'Hello Again!'), 'server has been restarted';
  ok kill(0, $command),                'command has not been restarted';
  is((split ' ', $file->slurp)[0], $command, 'command has only been started once');

  _stop($pid, $port);
  ok _wait_until(sub { !kill(0, $command) }),    'command has been stopped';
  ok _wait_until(sub { !kill(0, $subprocess) }), 'subprocess of command has been stopped';
  unlike $log->slurp, qr/exec\.pl"" (?:exited|was killed)/, 'no message for commands stopped by Morbo';
};

subtest 'Exec commands that misbehave' => sub {
  my $file  = $dir->child('stuck_exec.txt');
  my $stuck = $dir->child('stuck_exec.pl')->spew(<<EOF);
use Mojo::File qw(path);
\$SIG{TERM} = 'IGNORE';
path('$file')->spew("\$\$ \$ENV{MOJO_MODE}");
sleep 1000;
EOF
  my $killed  = $dir->child('killed_exec.pl')->spew('kill KILL => $$; sleep 1000;');
  my $missing = $dir->child('missing_exec');
  my $script  = _app('stuck_exec_app.pl', 'Hello Stuck!', q{get '/mode' => sub { shift->render(text => app->mode) };});
  my $port    = Mojo::IOLoop::Server->generate_port;
  my $log     = $dir->child('stuck_exec.log');
  my @exec    = ('-x', "$^X $stuck", '-x', "$^X $killed", '-x', $missing);
  my $pid     = _morbo($log, '-m', 'testing', '-l', "http://127.0.0.1:$port", @exec, $script);
  ok _wait_for($port, 'Hello Stuck!'), 'server has been started';
  is $ua->get("http://127.0.0.1:$port/mode")->res->body, 'testing', 'right application mode';
  ok _wait_until(sub { -s $file }), 'command has been started';
  my ($command, $mode) = split ' ', $file->slurp;
  is $mode, 'testing', 'same mode for command';
  ok _wait_until(sub { $log->slurp =~ /Command ".+killed_exec\.pl" was killed by signal 9\./ }), 'right message';
  ok _wait_until(sub { $log->slurp =~ /Command ".+missing_exec" exited with status 1\./ }),      'right message';
  like $log->slurp, qr/Can't exec ".+missing_exec"/, 'right error';
  ok kill(0, $command), 'command is still running';

  my $start = steady_time;
  _stop($pid, $port);
  ok steady_time - $start >= 4, 'command got time to stop';
  ok !kill(0, $command),        'command has been killed';
  unlike $log->slurp, qr/stuck_exec\.pl" (?:exited|was killed)/, 'no message for commands stopped by Morbo';
};

subtest 'Exec commands can tell when Morbo is gone' => sub {
  my $file = $dir->child('stdin_exec.txt');
  my $cmd  = $dir->child('stdin_exec.pl')->spew(<<EOF);
use Mojo::File qw(path);
path('$file')->spew('started');
my \$input = join '', <STDIN>;
path('$file')->spew('stdin closed');
EOF
  my $script = _app('stdin_exec_app.pl', 'Hello Stdin!', q{get '/pid' => sub { shift->render(text => $$) };});
  my $port   = Mojo::IOLoop::Server->generate_port;
  my $pid    = _morbo($dir->child('stdin_exec.log'), '-l', "http://127.0.0.1:$port", '-x', "$^X $cmd", $script);
  ok _wait_for($port, 'Hello Stdin!'), 'server has been started';
  ok _wait_until(sub { -s $file }),    'command has been started';
  sleep 0.5;
  is $file->slurp, 'started', 'command is still waiting for input';

  my $server = $ua->get("http://127.0.0.1:$port/pid")->res->body;
  kill 'KILL', $pid;
  is waitpid($pid, 0), $pid, 'morbo has been killed';
  ok _wait_until(sub { $file->slurp eq 'stdin closed' }), 'command noticed that Morbo is gone';

  # The server does not use STDIN and needs to be cleaned up manually
  kill 'KILL', -$server;
  ok _wait_until(sub { !_port($port) }), 'server has been stopped';
};

subtest 'Stop on SIGHUP (terminal closed)' => sub {
  my $file   = $dir->child('hup_exec.txt');
  my $cmd    = $dir->child('hup_exec.pl')->spew(qq{use Mojo::File qw(path); path('$file')->spew(\$\$); sleep 1000;});
  my $script = _app('hup_app.pl', 'Hello HUP!');
  my $port   = Mojo::IOLoop::Server->generate_port;
  my $log    = $dir->child('hup.log');
  my $pid    = _morbo($log, '-l', "http://127.0.0.1:$port", '-x', "$^X $cmd", $script);
  ok _wait_for($port, 'Hello HUP!'), 'server has been started';
  ok _wait_until(sub { -s $file }),  'command has been started';
  my $command = $file->slurp;

  _stop($pid, $port, 'HUP');
  ok !kill(0, $command), 'command has been stopped';
};

subtest 'Wrong arguments' => sub {
  my $output = qx{"$^X" "$morbo" 2>&1};
  like $output, qr/Usage: morbo/, 'usage message';
  isnt $?, 0, 'failed';

  $output = qx{"$^X" "$morbo" ./myapp.pl -l http://127.0.0.1:3000 2>&1};
  like $output, qr/Morbo options need to come before the application, e\.g\. "morbo -l \.\.\. \.\/myapp\.pl"/,
    'right error';
  isnt $?, 0, 'failed';
};

subtest 'Custom backend' => sub {
  local $ENV{MOJO_MORBO_BACKEND} = 'TestBackend';
  local $ENV{MOJO_MORBO_TIMEOUT} = 2;
  my $test_morbo = Mojo::Server::Morbo->new;
  isa_ok $test_morbo->backend, 'Mojo::Server::Morbo::Backend::TestBackend', 'right backend';
  is_deeply $test_morbo->backend->modified_files, ['always_changed'], 'always changes';
  is $test_morbo->backend->watch_timeout, 2, 'right timeout';
};

subtest 'SO_REUSEPORT' => sub {
  plan skip_all => 'SO_REUSEPORT support required!' unless eval { _reuse_port() };
  my $port   = Mojo::IOLoop::Server->generate_port;
  my $daemon = Mojo::Server::Daemon->new(listen => ["http://127.0.0.1:$port"], silent => 1)->start;
  ok !$daemon->ioloop->acceptor($daemon->acceptors->[0])->handle->getsockopt(SOL_SOCKET, SO_REUSEPORT),
    'no SO_REUSEPORT socket option';
  $daemon = Mojo::Server::Daemon->new(listen => ["http://127.0.0.1:$port?reuse=1"], silent => 1);
  $daemon->start;
  ok $daemon->ioloop->acceptor($daemon->acceptors->[0])->handle->getsockopt(SOL_SOCKET, SO_REUSEPORT),
    'SO_REUSEPORT socket option';
};

subtest 'Abstract methods' => sub {
  eval { Mojo::Server::Morbo::Backend->modified_files };
  like $@, qr/Method "modified_files" not implemented by subclass/, 'right error';
};

sub _app {
  my ($name, $text, $extra) = (@_, '');
  return $dir->child($name)->spew(<<EOF);
use Mojolicious::Lite;
use Mojo::File qw(path);
use Mojo::IOLoop;

app->log->level('fatal');

$extra

my \$server = 'none';
hook before_server_start => sub { \$server = ref shift };

get '/hello' => {text => '$text'} => 'hello';
get '/server' => sub { shift->render(text => \$server) };

app->start;
EOF
}

sub _morbo {
  my ($log, @args) = @_;
  die "Can't fork: $!" unless defined(my $pid = fork);
  return $pid if $pid;
  open STDOUT, '>>', $log     or die "Can't open log: $!";
  open STDERR, '>&', \*STDOUT or die "Can't redirect STDERR: $!";
  exec $^X, $morbo, @args or exit 1;
}

sub _port { IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => shift) }

sub _reuse_port { IO::Socket::INET->new(Listen => 1, LocalPort => Mojo::IOLoop::Server->generate_port, ReusePort => 1) }

sub _stop {
  my ($pid, $port, $sig) = @_;
  kill $sig // 'INT', $pid;
  is waitpid($pid, 0), $pid, 'morbo has been stopped';
  is $?,               0,    'morbo exited cleanly';
  ok !_port($port), 'all server processes have been stopped';
}

sub _wait_until {
  my $cb       = shift;
  my $deadline = steady_time + 30;
  sleep 0.1 until $cb->() || steady_time > $deadline;
  return $cb->();
}

# Retry until the expected response arrives (the listen socket stays open between restarts)
sub _wait_for {
  my ($port, $text) = @_;
  my $deadline = steady_time + 30;
  while (steady_time < $deadline) {
    my $tx = $ua->get("http://127.0.0.1:$port/hello");
    return 1 if ($tx->res->body // '') eq $text;
    sleep 0.1;
  }
  return undef;
}

done_testing();
