use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_PREFORK to enable this test (developer only!)' unless $ENV{TEST_PREFORK} || $ENV{TEST_ALL};

use Mojo::File qw(curfile path tempdir);
use Mojo::IOLoop::Server;
use Mojo::Server::Prefork;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json);
use Mojolicious;

# Manage and clean up PID file
my $prefork = Mojo::Server::Prefork->new;
my $dir     = tempdir;
ok $prefork->pid_file, 'has default path';
my $file = $dir->child('prefork.pid');
$prefork->pid_file($file);
ok !$prefork->check_pid, 'no process id';
$prefork->ensure_pid_file(-23);
ok -e $file, 'file exists';
is path($file)->slurp, "-23\n", 'right process id';
ok !$prefork->check_pid, 'no process id';
ok !-e $file, 'file has been cleaned up';
$prefork->ensure_pid_file($$);
ok -e $file, 'file exists';
is path($file)->slurp, "$$\n", 'right process id';
is $prefork->check_pid, $$, 'right process id';
undef $prefork;
ok !-e $file, 'file has been cleaned up';

# Bad PID file
my $bad = curfile->sibling('does_not_exist', 'test.pid');
$prefork = Mojo::Server::Prefork->new(pid_file => $bad);
$prefork->app->log->level('debug')->unsubscribe('message');
my $log = '';
my $cb  = $prefork->app->log->on(message => sub { $log .= pop });
eval { $prefork->ensure_pid_file($$) };
like $@,     qr/Can't create process id file/, 'right error';
unlike $log, qr/Creating process id file/,     'right message';
like $log,   qr/Can't create process id file/, 'right message';
$prefork->app->log->unsubscribe(message => $cb);

# Small webapp to count callbacks
my $counter = Mojolicious->new;
my ($counter_events, $counter_spawned, $counter_server);
$counter->hook(
  before_app_start => sub {
    my $app = shift;
    $counter_events  = {};
    $counter_spawned = {};
    $counter_server  = {};
  }
);
$counter->routes->get(
  '/events' => sub {
    my $c = shift;
    $c->render(json => {events => $counter_events, spawned => $counter_spawned, server => $counter_server});
  }
);
$counter->routes->post(
  '/triggered/:pid' => sub {
    my $c   = shift;
    my $pid = $c->stash('pid');
    $counter_events->{$pid}++;
    $c->rendered(201);
  }
);
$counter->routes->post(
  '/spawned/:pid' => sub {
    my $c   = shift;
    my $pid = $c->stash('pid');
    $counter_spawned->{$pid}++;
    $c->rendered(201);
  }
);
$counter->routes->post(
  '/server/:pid' => sub {
    my $c   = shift;
    my $pid = $c->stash('pid');
    $counter_server->{$pid}++;
    $c->rendered(201);
  }
);
$counter->log->level('fatal');    # Silence!

my $dport = Mojo::IOLoop::Server::->generate_port;
my $durl  = "http://localhost:$dport";
my $dpid  = fork;
die "fork: $!" unless defined $dpid;

if (0 == $dpid) {
  my $daemon = Mojo::Server::Daemon->new(listen => ["http://*:$dport"], app => $counter);
  my $loop   = $daemon->ioloop;
  $loop->recurring(0.5 => sub { exit if 1 == getppid() });    # Failsafe
  $daemon->run;
  exit;
}

# Multiple workers and graceful shutdown
my $port = Mojo::IOLoop::Server::->generate_port;
$prefork = Mojo::Server::Prefork->new(heartbeat_interval => 0.5, listen => ["http://*:$port"], pid_file => $file);
$prefork->unsubscribe('request');
$prefork->on(
  request => sub {
    my ($prefork, $tx) = @_;
    $tx->res->code(200)->body('just works!');
    $tx->resume;
  }
);
is $prefork->workers, 4, 'start with four workers';
my (@spawn, @reap, $worker, $tx, $graceful);
$prefork->on(
  spawn => sub {
    my ($prefork, $pid) = @_;
    push @spawn, $pid;
    Mojo::UserAgent->new->post("$durl/spawned/$pid");
  }
);
$prefork->on(
  heartbeat => sub {
    my ($prefork, $pid) = @_;
    $worker = $pid;
    return if $prefork->healthy < 4;
    $tx = Mojo::UserAgent->new->get("http://127.0.0.1:$port");
    kill 'QUIT', $$;
  }
);
$prefork->on(reap   => sub { push @reap, pop });
$prefork->on(finish => sub { $graceful = pop });
$prefork->app->log->level('debug')->unsubscribe('message');
$log = '';
$cb  = $prefork->app->log->on(message => sub { $log .= pop });
is $prefork->healthy, 0, 'no healthy workers';
my @server;
$prefork->app->hook(
  before_server_start => sub {
    my ($server, $app) = @_;
    push @server, $server->workers, $app->mode;
    Mojo::UserAgent->new->post("$durl/server/$$");
  }
);
$prefork->app->hook(
  before_app_start => sub {
    my $app = shift;
    Mojo::UserAgent->new->post("$durl}triggered/$$");
  }
);
$prefork->run;
is_deeply \@server, [4, 'development'], 'hook has been emitted once';
is scalar @spawn, 4, 'four workers spawned';
is scalar @reap,  4, 'four workers reaped';
ok !!grep { $worker eq $_ } @spawn, 'worker has a heartbeat';
ok $graceful, 'server has been stopped gracefully';
is_deeply [sort @spawn], [sort @reap], 'same process ids';
is $tx->res->code, 200,           'right status';
is $tx->res->body, 'just works!', 'right content';
like $log, qr/Listening at/,                                         'right message';
like $log, qr/Manager $$ started/,                                   'right message';
like $log, qr/Creating process id file/,                             'right message';
like $log, qr/Stopping worker $spawn[0] gracefully \(120 seconds\)/, 'right message';
like $log, qr/Worker $spawn[0] stopped/,                             'right message';
like $log, qr/Manager $$ stopped/,                                   'right message';
$prefork->app->log->unsubscribe(message => $cb);

# Process id file
is $prefork->check_pid, $$, 'right process id';
my $pid = $prefork->pid_file;
ok -e $pid, 'process id file has been created';
undef $prefork;
ok !-e $pid, 'process id file has been removed';

# One worker and immediate shutdown
$port = Mojo::IOLoop::Server->generate_port;
$prefork
  = Mojo::Server::Prefork->new(accepts => 500, heartbeat_interval => 0.5, listen => ["http://*:$port"], workers => 1);
$prefork->unsubscribe('request');
$prefork->on(
  request => sub {
    my ($prefork, $tx) = @_;
    $tx->res->code(200)->body('works too!');
    $tx->resume;
  }
);
my $count = $tx = $graceful = undef;
@spawn = @reap = ();
$prefork->on(
  spawn => sub {
    my ($prefork, $pid) = @_;
    push @spawn, $pid;
    Mojo::UserAgent->new->post("$durl/spawned/$pid");
  }
);
$prefork->once(
  heartbeat => sub {
    $tx = Mojo::UserAgent->new->get("http://127.0.0.1:$port");
    kill 'TERM', $$;
  }
);
$prefork->on(reap   => sub { push @reap, pop });
$prefork->on(finish => sub { $graceful = pop });
$prefork->app->hook(
  before_server_start => sub {
    my ($server, $app) = @_;
    Mojo::UserAgent->new->post("$durl/server/$$");
  }
);
$prefork->app->hook(
  before_app_start => sub {
    my $app = shift;
    Mojo::UserAgent->new->post("$durl/triggered/$$");
  }
);
$prefork->run;
is $prefork->ioloop->max_accepts, 500, 'right value';
is scalar @spawn, 1, 'one worker spawned';
is scalar @reap,  1, 'one worker reaped';
ok !$graceful, 'server has been stopped immediately';
is $tx->res->code, 200,          'right status';
is $tx->res->body, 'works too!', 'right content';

my $events = Mojo::UserAgent->new->get("$durl/events")->res->body;
my $href   = decode_json($events);
is ref $href, 'HASH', 'right response type';
is ref $href->{events},  'HASH', 'right events key';
is ref $href->{spawned}, 'HASH', 'right spawned key';
is ref $href->{server},  'HASH', 'right server key';

my $event_count   = scalar keys %{$href->{events}};
my $spawned_count = scalar keys %{$href->{spawned}};
my $server_count  = scalar keys %{$href->{server}};

is $event_count,   2, 'right amount of events';
is $spawned_count, 5, 'right amount of spawned servers';
is $server_count,  1, 'right amount of master servers';

sub all_values_one {
  my $href = shift;
  foreach my $val (values %$href) {
    return 0 unless 1 == $val;
  }
  return 1;
}

is all_values_one($href->{events}),  1, '1 before_app_start trigger per process';
is all_values_one($href->{spawned}), 1, '1 spawn trigger per process';

my $foreign = 0;
foreach my $pid (keys %{$href->{events}}) {
  $foreign++ unless exists $href->{spawned}->{$pid} || exists $href->{server}->{$pid};
}

is $foreign, 0, 'no before_app_start ran in foreign processes';

kill 'TERM', $dpid;

done_testing();
