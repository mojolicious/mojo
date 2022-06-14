use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_MORBO to enable this test (developer only!)' unless $ENV{TEST_MORBO} || $ENV{TEST_ALL};

use Mojo::File qw(curfile);
use lib curfile->sibling('lib')->to_string;

use IO::Socket::INET ();
use Mojo::File       qw(tempdir);
use Mojo::IOLoop::Server;
use Mojo::Server::Morbo::Backend;
use Mojo::Server::Daemon;
use Mojo::Server::Morbo;
use Mojo::UserAgent;
use Socket      qw(SO_REUSEPORT SOL_SOCKET);
use Time::HiRes qw(sleep);

# Start
my $dir    = tempdir;
my $script = $dir->child('myapp.pl');
my $subdir = $dir->child('test', 'stuff')->make_path;
my $morbo  = Mojo::Server::Morbo->new();
$morbo->backend->watch([$subdir, $script]);
is_deeply $morbo->backend->modified_files, [], 'no files have changed';
my $started = $dir->child('started1.txt');
$script->spurt(<<EOF);
use Mojolicious::Lite;
use Mojo::File qw(path);
use Mojo::IOLoop;

app->log->level('fatal');

Mojo::IOLoop->next_tick(sub { path('$started')->touch });

get '/hello' => {text => 'Hello Morbo!'};

app->start;
EOF
my $port   = Mojo::IOLoop::Server->generate_port;
my $prefix = curfile->dirname->dirname->sibling('script');
my $pid    = open my $server, '-|', $^X, "$prefix/morbo", '-l', "http://127.0.0.1:$port", $script;
sleep 0.1 while !_port($port);
my $ua = Mojo::UserAgent->new;

subtest 'Basics' => sub {
  my $tx = $ua->get("http://127.0.0.1:$port/hello");
  ok $tx->is_finished, 'transaction is finished';
  is $tx->res->code, 200,            'right status';
  is $tx->res->body, 'Hello Morbo!', 'right content';

  $tx = $ua->get("http://127.0.0.1:$port/hello");
  ok $tx->is_finished, 'transaction is finished';
  is $tx->res->code, 200,            'right status';
  is $tx->res->body, 'Hello Morbo!', 'right content';
};

subtest 'Update script without changing size' => sub {
  my ($size, $mtime) = (stat $script)[7, 9];
  $started = $started->sibling('started2.txt');
  $script->spurt(<<EOF);
use Mojolicious::Lite;
use Mojo::File qw(path);
use Mojo::IOLoop;

app->log->level('fatal');

Mojo::IOLoop->next_tick(sub { path('$started')->touch });

get '/hello' => {text => 'Hello World!'};

app->start;
EOF
  is_deeply $morbo->backend->modified_files, [$script], 'file has changed';
  ok((stat $script)[9] > $mtime, 'modify time has changed');
  is((stat $script)[7], $size, 'still equal size');
  sleep 0.1 until -f $started;

  # Application has been reloaded
  my $tx = $ua->get("http://127.0.0.1:$port/hello");
  ok $tx->is_finished, 'transaction is finished';
  is $tx->res->code, 200,            'right status';
  is $tx->res->body, 'Hello World!', 'right content';

  # Same result
  $tx = $ua->get("http://127.0.0.1:$port/hello");
  ok $tx->is_finished, 'transaction is finished';
  is $tx->res->code, 200,            'right status';
  is $tx->res->body, 'Hello World!', 'right content';
};

subtest 'Update script without changing mtime' => sub {
  my ($size, $mtime) = (stat $script)[7, 9];
  is_deeply $morbo->backend->modified_files, [], 'no files have changed';
  $started = $started->sibling('started3.txt');
  $script->spurt(<<"EOF");
use Mojolicious::Lite;
use Mojo::File qw(path);
use Mojo::IOLoop;

app->log->level('fatal');

Mojo::IOLoop->next_tick(sub { path('$started')->touch });

my \$message = 'Failed!';
hook before_server_start => sub { \$message = 'Hello!' };

get '/hello' => sub { shift->render(text => \$message) };

app->start;
EOF
  utime $mtime, $mtime, $script;
  is_deeply $morbo->backend->modified_files, [$script], 'file has changed';
  ok((stat $script)[9] == $mtime, 'modify time has not changed');
  isnt((stat $script)[7], $size, 'size has changed');
  sleep 0.1 until -f $started;

  # Application has been reloaded again
  my $tx = $ua->get("http://127.0.0.1:$port/hello");
  ok $tx->is_finished, 'transaction is finished';
  is $tx->res->code, 200,      'right status';
  is $tx->res->body, 'Hello!', 'right content';

  # Same result
  $tx = $ua->get("http://127.0.0.1:$port/hello");
  ok $tx->is_finished, 'transaction is finished';
  is $tx->res->code, 200,      'right status';
  is $tx->res->body, 'Hello!', 'right content';
};

subtest 'New file(s)' => sub {
  is_deeply $morbo->backend->modified_files, [], 'directory has not changed';
  my @new = map { $subdir->child("$_.txt") } qw/test testing/;
  $_->spurt('whatever') for @new;
  is_deeply $morbo->backend->modified_files, \@new, 'two files have changed';
  $subdir->child('.hidden.txt')->spurt('whatever');
  is_deeply $morbo->backend->modified_files, [], 'directory has not changed again';
};

subtest 'Broken symlink' => sub {
  plan skip_all => 'Symlink support required!' unless eval { symlink '', ''; 1 };
  my $missing = $subdir->child('missing.txt');
  my $broken  = $subdir->child('broken.txt');
  symlink $missing, $broken;
  ok -l $broken,  'symlink created';
  ok !-f $broken, 'symlink target does not exist';
  my $warned;
  local $SIG{__WARN__} = sub { $warned++ };
  is_deeply $morbo->backend->modified_files, [], 'directory has not changed';
  ok !$warned, 'no warnings';
};

# Stop
kill 'INT', $pid;
sleep 0.1 while _port($port);

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

sub _port { IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => shift) }

sub _reuse_port { IO::Socket::INET->new(Listen => 1, LocalPort => Mojo::IOLoop::Server->generate_port, ReusePort => 1) }

done_testing();
