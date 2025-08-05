package Mojo::Server::Prefork;
use Mojo::Base 'Mojo::Server::Daemon';

use Config;
use File::Spec::Functions qw(tmpdir);
use Mojo::File            qw(path);
use Mojo::Util            qw(steady_time);
use POSIX                 qw(WNOHANG);
use Scalar::Util          qw(weaken);

has accepts            => 10000;
has cleanup            => 1;
has graceful_timeout   => 120;
has heartbeat_timeout  => 50;
has heartbeat_interval => 5;
has pid_file           => sub { path(tmpdir, 'prefork.pid')->to_string };
has spare              => 2;
has workers            => 4;

sub DESTROY { path($_[0]->pid_file)->remove if $_[0]->cleanup }

sub check_pid {
  return undef unless -r (my $file = path(shift->pid_file));
  my $pid = $file->slurp;
  chomp $pid;

  # Running
  return $pid if $pid && kill 0, $pid;

  # Not running
  $file->remove;
  return undef;
}

sub ensure_pid_file {
  my ($self, $pid) = @_;

  # Check if PID file already exists
  return if -e (my $file = path($self->pid_file));

  # Create PID file
  if (my $err = eval { $file->spew("$pid\n")->chmod(0644) } ? undef : $@) {
    $self->app->log->error(qq{Can't create process id file "$file": $err})
      and die qq{Can't create process id file "$file": $err};
  }
  $self->app->log->info(qq{Creating process id file "$file"});
}

sub healthy {
  scalar grep { $_->{healthy} } values %{shift->{pool}};
}

sub run {
  my $self = shift;

  # No fork emulation support
  say 'Pre-forking does not support fork emulation.' and exit 0 if $Config{d_pseudofork};

  # Pipe for worker communication
  pipe($self->{reader}, $self->{writer}) or die "Can't create pipe: $!";

  # Clean manager environment
  local $SIG{CHLD} = sub {
    while ((my $pid = waitpid -1, WNOHANG) > 0) { $self->emit(reap => $pid)->_stopped($pid) }
  };
  local $SIG{INT}  = local $SIG{TERM} = sub { $self->_term };
  local $SIG{QUIT} = sub { $self->_term(1) };
  local $SIG{TTIN} = sub { $self->workers($self->workers + 1) };
  local $SIG{TTOU} = sub {
    $self->workers > 0 ? $self->workers($self->workers - 1) : return;
    for my $w (values %{$self->{pool}}) { ($w->{graceful} = steady_time) and last unless $w->{graceful} }
  };

  # Preload application before starting workers
  $self->start->app->log->info("Manager $$ started");
  $self->ioloop->max_accepts($self->accepts);
  $self->{running} = 1;
  $self->_manage while $self->{running};
  $self->app->log->info("Manager $$ stopped");
}

sub _heartbeat { shift->{writer}->syswrite("$$:$_[0]\n") or exit 0 }

sub _manage {
  my $self = shift;

  # Spawn more workers if necessary and check PID file
  if (!$self->{finished}) {
    my $graceful = grep { $_->{graceful} } values %{$self->{pool}};
    my $spare    = $self->spare;
    $spare = $graceful ? $graceful > $spare ? $spare : $graceful : 0;
    my $need = ($self->workers - keys %{$self->{pool}}) + $spare;
    $self->_spawn while $need-- > 0;
    $self->ensure_pid_file($$);
  }

  # Shutdown
  elsif (!keys %{$self->{pool}}) { return delete $self->{running} }

  # Wait for heartbeats
  $self->_wait;

  my $interval = $self->heartbeat_interval;
  my $ht       = $self->heartbeat_timeout;
  my $gt       = $self->graceful_timeout;
  my $log      = $self->app->log;
  my $time     = steady_time;

  for my $pid (keys %{$self->{pool}}) {
    next unless my $w = $self->{pool}{$pid};

    # No heartbeat (graceful stop)
    $log->info("Worker $pid has no heartbeat ($ht seconds), restarting (see FAQ for more)") and $w->{graceful} = $time
      if !$w->{graceful} && ($w->{time} + $interval + $ht <= $time);

    # Graceful stop with timeout
    my $graceful = $w->{graceful} ||= $self->{graceful} ? $time : undef;
    $log->info("Stopping worker $pid gracefully ($gt seconds)") and (kill 'QUIT', $pid or $self->_stopped($pid))
      if $graceful && !$w->{quit}++;
    $w->{force} = 1 if $graceful && $graceful + $gt <= $time;

    # Normal stop
    $log->warn("Stopping worker $pid immediately") and (kill 'KILL', $pid or $self->_stopped($pid))
      if $w->{force} || ($self->{finished} && !$graceful);
  }
}

sub _spawn {
  my $self = shift;

  # Manager
  die "Can't fork: $!" unless defined(my $pid = fork);
  return $self->emit(spawn => $pid)->{pool}{$pid} = {time => steady_time} if $pid;

  # Heartbeat messages
  my $loop     = $self->cleanup(0)->ioloop;
  my $finished = 0;
  $loop->on(finish => sub { $finished = 1 });
  weaken $self;
  my $cb = sub { $self->_heartbeat($finished) };
  $loop->next_tick($cb);
  $loop->recurring($self->heartbeat_interval => $cb);

  # Clean worker environment
  $SIG{$_} = 'DEFAULT' for qw(CHLD INT TERM TTIN TTOU);
  $SIG{QUIT} = sub { $loop->stop_gracefully };
  $loop->on(finish => sub { $self->max_requests(1) });
  delete $self->{reader};
  srand;

  $self->app->log->info("Worker $$ started");
  $loop->start;
  exit 0;
}

sub _stopped {
  my ($self, $pid) = @_;

  return unless my $w = delete $self->{pool}{$pid};

  my $log = $self->app->log;
  $log->info("Worker $pid stopped");
  $log->error("Worker $pid stopped too early, shutting down") and $self->_term unless $w->{healthy};
}

sub _term {
  my ($self, $graceful) = @_;
  @{$self->emit(finish => $graceful)}{qw(finished graceful)} = (1, $graceful);
}

sub _wait {
  my $self = shift;

  # Poll for heartbeats
  my $reader = $self->emit('wait')->{reader};
  return unless Mojo::Util::_readable(1000, fileno($reader));
  return unless $reader->sysread(my $chunk, 4194304);

  # Update heartbeats (and stop gracefully if necessary)
  my $time = steady_time;
  while ($chunk =~ /(\d+):(\d)\n/g) {
    next unless my $w = $self->{pool}{$1};
    @$w{qw(healthy time)} = (1, $time) and $self->emit(heartbeat => $1);
    if ($2) {
      $w->{graceful} ||= $time;
      $w->{quit}++;
    }
  }
}

1;

=encoding utf8

=head1 NAME

Mojo::Server::Prefork - Pre-forking non-blocking I/O HTTP and WebSocket server

=head1 SYNOPSIS

  use Mojo::Server::Prefork;

  my $prefork = Mojo::Server::Prefork->new(listen => ['http://*:8080']);
  $prefork->unsubscribe('request')->on(request => sub ($prefork, $tx) {

    # Request
    my $method = $tx->req->method;
    my $path   = $tx->req->url->path;

    # Response
    $tx->res->code(200);
    $tx->res->headers->content_type('text/plain');
    $tx->res->body("$method request for $path!");

    # Resume transaction
    $tx->resume;
  });
  $prefork->run;

=head1 DESCRIPTION

L<Mojo::Server::Prefork> is a full featured, UNIX optimized, pre-forking non-blocking I/O HTTP and WebSocket server,
built around the very well tested and reliable L<Mojo::Server::Daemon>, with IPv6, TLS, SNI, UNIX domain socket, Comet
(long polling), keep-alive and multiple event loop support. Note that the server uses signals for process management,
so you should avoid modifying signal handlers in your applications.

For better scalability (epoll, kqueue) and to provide non-blocking name resolution, SOCKS5 as well as TLS support, the
optional modules L<EV> (4.32+), L<Net::DNS::Native> (0.15+), L<IO::Socket::Socks> (0.64+) and L<IO::Socket::SSL>
(1.84+) will be used automatically if possible. Individual features can also be disabled with the C<MOJO_NO_NNR>,
C<MOJO_NO_SOCKS> and C<MOJO_NO_TLS> environment variables.

See L<Mojolicious::Guides::Cookbook/"DEPLOYMENT"> for more.

=head1 MANAGER SIGNALS

The L<Mojo::Server::Prefork> manager process can be controlled at runtime with the following signals.

=head2 INT, TERM

Shut down server immediately.

=head2 QUIT

Shut down server gracefully.

=head2 TTIN

Increase worker pool by one.

=head2 TTOU

Decrease worker pool by one.

=head1 WORKER SIGNALS

L<Mojo::Server::Prefork> worker processes can be controlled at runtime with the following signals.

=head2 QUIT

Stop worker gracefully.

=head1 EVENTS

L<Mojo::Server::Prefork> inherits all events from L<Mojo::Server::Daemon> and can emit the following new ones.

=head2 finish

  $prefork->on(finish => sub ($prefork, $graceful) {...});

Emitted when the server shuts down.

  $prefork->on(finish => sub ($prefork, $graceful) {
    say $graceful ? 'Graceful server shutdown' : 'Server shutdown';
  });

=head2 heartbeat

  $prefork->on(heartbeat => sub ($prefork, $pid) {...});

Emitted when a heartbeat message has been received from a worker.

  $prefork->on(heartbeat => sub ($prefork, $pid) { say "Worker $pid has a heartbeat" });

=head2 reap

  $prefork->on(reap => sub ($prefork, $pid) {...});

Emitted when a child process exited.

  $prefork->on(reap => sub ($prefork, $pid) { say "Worker $pid stopped" });

=head2 spawn

  $prefork->on(spawn => sub ($prefork, $pid) {...});

Emitted when a worker process is spawned.

  $prefork->on(spawn => sub ($prefork, $pid) { say "Worker $pid started" });

=head2 wait

  $prefork->on(wait => sub ($prefork) {...});

Emitted when the manager starts waiting for new heartbeat messages.

  $prefork->on(wait => sub ($prefork) {
    my $workers = $prefork->workers;
    say "Waiting for heartbeat messages from $workers workers";
  });

=head1 ATTRIBUTES

L<Mojo::Server::Prefork> inherits all attributes from L<Mojo::Server::Daemon> and implements the following new ones.

=head2 accepts

  my $accepts = $prefork->accepts;
  $prefork    = $prefork->accepts(100);

Maximum number of connections a worker is allowed to accept, before stopping gracefully and then getting replaced with
a newly started worker, passed along to L<Mojo::IOLoop/"max_accepts">, defaults to C<10000>. Setting the value to C<0>
will allow workers to accept new connections indefinitely. Note that up to half of this value can be subtracted
randomly to improve load balancing, and to make sure that not all workers restart at the same time.

=head2 cleanup

  my $bool = $prefork->cleanup;
  $prefork = $prefork->cleanup($bool);

Delete L</"pid_file"> automatically once it is not needed anymore, defaults to a true value.

=head2 graceful_timeout

  my $timeout = $prefork->graceful_timeout;
  $prefork    = $prefork->graceful_timeout(15);

Maximum amount of time in seconds stopping a worker gracefully may take before being forced, defaults to C<120>. Note
that this value should usually be a little larger than the maximum amount of time you expect any one request to take.

=head2 heartbeat_interval

  my $interval = $prefork->heartbeat_interval;
  $prefork     = $prefork->heartbeat_interval(3);

Heartbeat interval in seconds, defaults to C<5>.

=head2 heartbeat_timeout

  my $timeout = $prefork->heartbeat_timeout;
  $prefork    = $prefork->heartbeat_timeout(2);

Maximum amount of time in seconds before a worker without a heartbeat will be stopped gracefully, defaults to C<50>.
Note that this value should usually be a little larger than the maximum amount of time you expect any one operation to
block the event loop.

=head2 pid_file

  my $file = $prefork->pid_file;
  $prefork = $prefork->pid_file('/tmp/prefork.pid');

Full path of process id file, defaults to C<prefork.pid> in a temporary directory.

=head2 spare

  my $spare = $prefork->spare;
  $prefork  = $prefork->spare(4);

Temporarily spawn up to this number of additional workers if there is a need, defaults to C<2>. This allows for new
workers to be started while old ones are still shutting down gracefully, drastically reducing the performance cost of
worker restarts.

=head2 workers

  my $workers = $prefork->workers;
  $prefork    = $prefork->workers(10);

Number of worker processes, defaults to C<4>. A good rule of thumb is two worker processes per CPU core for
applications that perform mostly non-blocking operations, blocking operations often require more and benefit from
decreasing concurrency with L<Mojo::Server::Daemon/"max_clients"> (often as low as C<1>).

=head1 METHODS

L<Mojo::Server::Prefork> inherits all methods from L<Mojo::Server::Daemon> and implements the following new ones.

=head2 check_pid

  my $pid = $prefork->check_pid;

Get process id for running server from L</"pid_file"> or delete it if server is not running.

  say 'Server is not running' unless $prefork->check_pid;

=head2 ensure_pid_file

  $prefork->ensure_pid_file($pid);

Ensure L</"pid_file"> exists.

=head2 healthy

  my $healthy = $prefork->healthy;

Number of currently active worker processes with a heartbeat.

=head2 run

  $prefork->run;

Run server and wait for L</"MANAGER SIGNALS">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
