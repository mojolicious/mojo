package Mojo::Server::Prefork;
use Mojo::Base 'Mojo::Server::Daemon';

use Fcntl ':flock';
use File::Spec::Functions qw(catfile tmpdir);
use IO::Poll qw(POLLIN POLLPRI);
use List::Util 'shuffle';
use Mojo::Util 'steady_time';
use POSIX 'WNOHANG';
use Scalar::Util 'weaken';
use Time::HiRes ();

has accepts => 1000;
has [qw(accept_interval multi_accept)];
has [qw(cleanup lock_timeout)] => 1;
has [qw(graceful_timeout heartbeat_timeout)] => 20;
has heartbeat_interval => 5;
has lock_file          => sub { catfile tmpdir, 'prefork.lock' };
has pid_file           => sub { catfile tmpdir, 'prefork.pid' };
has workers            => 4;

sub DESTROY {
  my $self = shift;

  # Worker
  return unless $self->cleanup;

  # Manager
  if (my $file = $self->{lock_file}) { unlink $file if -w $file }
  if (my $file = $self->pid_file)    { unlink $file if -w $file }
}

sub check_pid {
  my $file = shift->pid_file;
  return undef unless open my $handle, '<', $file;
  my $pid = <$handle>;
  chomp $pid;

  # Running
  return $pid if $pid && kill 0, $pid;

  # Not running
  unlink $file if -w $file;
  return undef;
}

sub ensure_pid_file {
  my $self = shift;

  # Check if PID file already exists
  return if -e (my $file = $self->pid_file);

  # Create PID file
  $self->app->log->info(qq{Creating process id file "$file"});
  die qq{Can't create process id file "$file": $!}
    unless open my $handle, '>', $file;
  chmod 0644, $handle;
  print $handle $$;
}

sub healthy {
  scalar grep { $_->{healthy} } values %{shift->{pool}};
}

sub run {
  my $self = shift;

  # No Windows support
  say 'Preforking is not available for Windows.' and exit 0
    if $^O eq 'MSWin32';

  # Prepare lock file and event loop
  $self->{lock_file} = $self->lock_file . ".$$";
  my $loop = $self->ioloop->max_accepts($self->accepts);
  $loop->$_($self->$_ // $loop->$_) for qw(accept_interval multi_accept);

  # Pipe for worker communication
  pipe($self->{reader}, $self->{writer}) or die "Can't create pipe: $!";
  $self->{poll} = IO::Poll->new;
  $self->{poll}->mask($self->{reader}, POLLIN | POLLPRI);

  # Clean manager environment
  local $SIG{CHLD} = sub {
    while ((my $pid = waitpid -1, WNOHANG) > 0) {
      $self->emit(reap => $pid)->_stopped($pid);
    }
  };
  local $SIG{INT} = local $SIG{TERM} = sub { $self->_term };
  local $SIG{QUIT} = sub { $self->_term(1) };
  local $SIG{TTIN} = sub { $self->workers($self->workers + 1) };
  local $SIG{TTOU} = sub {
    $self->workers($self->workers - 1) if $self->workers > 0;
    return unless $self->workers;
    $self->{pool}{shuffle keys %{$self->{pool}}}{graceful} ||= steady_time;
  };

  # Preload application before starting workers
  $self->start->app->log->info("Manager $$ started");
  $self->{running} = 1;
  $self->_manage while $self->{running};
}

sub _heartbeat { shift->{writer}->syswrite("$$:$_[0]\n") or exit 0 }

sub _manage {
  my $self = shift;

  # Spawn more workers if necessary and check PID file
  if (!$self->{finished}) {
    $self->_spawn while keys %{$self->{pool}} < $self->workers;
    $self->ensure_pid_file;
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
    $log->error("Worker $pid has no heartbeat, restarting")
      and $w->{graceful} = $time
      if !$w->{graceful} && ($w->{time} + $interval + $ht <= $time);

    # Graceful stop with timeout
    my $graceful = $w->{graceful} ||= $self->{graceful} ? $time : undef;
    $log->debug("Stopping worker $pid gracefully")
      and (kill 'QUIT', $pid or $self->_stopped($pid))
      if $graceful && !$w->{quit}++;
    $w->{force} = 1 if $graceful && $graceful + $gt <= $time;

    # Normal stop
    $log->debug("Stopping worker $pid")
      and (kill 'KILL', $pid or $self->_stopped($pid))
      if $w->{force} || ($self->{finished} && !$graceful);
  }
}

sub _spawn {
  my $self = shift;

  # Manager
  die "Can't fork: $!" unless defined(my $pid = fork);
  return $self->emit(spawn => $pid)->{pool}{$pid} = {time => steady_time}
    if $pid;

  # Prepare lock file
  my $file = $self->cleanup(0)->{lock_file};
  $self->app->log->error(qq{Can't open lock file "$file": $!})
    unless open my $handle, '>', $file;

  # Change user/group
  $self->setuidgid;

  # Accept mutex
  weaken $self;
  my $loop = $self->ioloop->lock(
    sub {

      # Non-blocking
      return flock $handle, LOCK_EX | LOCK_NB unless shift;

      # Blocking ("ualarm" can't be imported on Windows)
      my $lock;
      eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        my $old = Time::HiRes::ualarm $self->lock_timeout * 1000000;
        $lock = flock $handle, LOCK_EX;
        Time::HiRes::ualarm $old;
        1;
      } or $lock = $@ eq "alarm\n" ? 0 : die $@;
      return $lock;
    }
  );
  $loop->unlock(sub { flock $handle, LOCK_UN });

  # Heartbeat messages
  my $cb = sub { $self->_heartbeat(shift->max_connections ? 0 : 1) };
  $loop->next_tick($cb);
  $loop->recurring($self->heartbeat_interval => $cb);

  # Clean worker environment
  $SIG{$_} = 'DEFAULT' for qw(CHLD INT TERM TTIN TTOU);
  $SIG{QUIT} = sub { $loop->max_connections(0) };
  delete @$self{qw(poll reader)};
  srand;

  $self->app->log->debug("Worker $$ started");
  $loop->start;
  exit 0;
}

sub _stopped {
  my ($self, $pid) = @_;

  return unless my $w = delete $self->{pool}{$pid};

  my $log = $self->app->log;
  $log->debug("Worker $pid stopped");
  $log->error("Worker $pid stopped too early, shutting down") and $self->_term
    unless $w->{healthy};
}

sub _term {
  my ($self, $graceful) = @_;
  @{$self->emit(finish => $graceful)}{qw(finished graceful)} = (1, $graceful);
}

sub _wait {
  my $self = shift;

  # Poll for heartbeats
  my $poll = $self->emit('wait')->{poll};
  $poll->poll(1);
  return unless $poll->handles(POLLIN | POLLPRI);
  return unless $self->{reader}->sysread(my $chunk, 4194304);

  # Update heartbeats (and stop gracefully if necessary)
  my $time = steady_time;
  while ($chunk =~ /(\d+):(\d)\n/g) {
    next unless my $w = $self->{pool}{$1};
    @$w{qw(healthy time)} = (1, $time) and $self->emit(heartbeat => $1);
    $w->{graceful} ||= $time if $2;
  }
}

1;

=encoding utf8

=head1 NAME

Mojo::Server::Prefork - Preforking non-blocking I/O HTTP and WebSocket server

=head1 SYNOPSIS

  use Mojo::Server::Prefork;

  my $prefork = Mojo::Server::Prefork->new(listen => ['http://*:8080']);
  $prefork->unsubscribe('request');
  $prefork->on(request => sub {
    my ($prefork, $tx) = @_;

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

L<Mojo::Server::Prefork> is a full featured, UNIX optimized, preforking
non-blocking I/O HTTP and WebSocket server, built around the very well tested
and reliable L<Mojo::Server::Daemon>, with IPv6, TLS, Comet (long polling),
keep-alive and multiple event loop support. Note that the server uses signals
for process management, so you should avoid modifying signal handlers in your
applications.

For better scalability (epoll, kqueue) and to provide non-blocking name
resolution, SOCKS5 as well as TLS support, the optional modules L<EV> (4.0+),
L<Net::DNS::Native> (0.15+), L<IO::Socket::Socks> (0.64+) and
L<IO::Socket::SSL> (1.84+) will be used automatically if possible. Individual
features can also be disabled with the C<MOJO_NO_NDN>, C<MOJO_NO_SOCKS> and
C<MOJO_NO_TLS> environment variables.

See L<Mojolicious::Guides::Cookbook/"DEPLOYMENT"> for more.

=head1 MANAGER SIGNALS

The L<Mojo::Server::Prefork> manager process can be controlled at runtime with
the following signals.

=head2 INT, TERM

Shut down server immediately.

=head2 QUIT

Shut down server gracefully.

=head2 TTIN

Increase worker pool by one.

=head2 TTOU

Decrease worker pool by one.

=head1 WORKER SIGNALS

L<Mojo::Server::Prefork> worker processes can be controlled at runtime with
the following signals.

=head2 INT, TERM

Stop worker immediately.

=head2 QUIT

Stop worker gracefully.

=head1 EVENTS

L<Mojo::Server::Prefork> inherits all events from L<Mojo::Server::Daemon> and
can emit the following new ones.

=head2 finish

  $prefork->on(finish => sub {
    my ($prefork, $graceful) = @_;
    ...
  });

Emitted when the server shuts down.

  $prefork->on(finish => sub {
    my ($prefork, $graceful) = @_;
    say $graceful ? 'Graceful server shutdown' : 'Server shutdown';
  });

=head2 heartbeat

  $prefork->on(heartbeat => sub {
    my ($prefork, $pid) = @_;
    ...
  });

Emitted when a heartbeat message has been received from a worker.

  $prefork->on(heartbeat => sub {
    my ($prefork, $pid) = @_;
    say "Worker $pid has a heartbeat";
  });

=head2 reap

  $prefork->on(reap => sub {
    my ($prefork, $pid) = @_;
    ...
  });

Emitted when a child process dies.

  $prefork->on(reap => sub {
    my ($prefork, $pid) = @_;
    say "Worker $pid stopped";
  });

=head2 spawn

  $prefork->on(spawn => sub {
    my ($prefork, $pid) = @_;
    ...
  });

Emitted when a worker process is spawned.

  $prefork->on(spawn => sub {
    my ($prefork, $pid) = @_;
    say "Worker $pid started";
  });

=head2 wait

  $prefork->on(wait => sub {
    my $prefork = shift;
    ...
  });

Emitted when the manager starts waiting for new heartbeat messages.

  $prefork->on(wait => sub {
    my $prefork = shift;
    my $workers = $prefork->workers;
    say "Waiting for heartbeat messages from $workers workers";
  });

=head1 ATTRIBUTES

L<Mojo::Server::Prefork> inherits all attributes from L<Mojo::Server::Daemon>
and implements the following new ones.

=head2 accept_interval

  my $interval = $prefork->accept_interval;
  $prefork     = $prefork->accept_interval(0.5);

Interval in seconds for trying to reacquire the accept mutex, passed along to
L<Mojo::IOLoop/"accept_interval">. Note that changing this value can affect
performance and idle CPU usage.

=head2 accepts

  my $accepts = $prefork->accepts;
  $prefork    = $prefork->accepts(100);

Maximum number of connections a worker is allowed to accept before stopping
gracefully and then getting replaced with a newly started worker, passed along
to L<Mojo::IOLoop/"max_accepts">, defaults to C<1000>. Setting the value to
C<0> will allow workers to accept new connections indefinitely. Note that up
to half of this value can be subtracted randomly to improve load balancing.

=head2 cleanup

  my $bool = $prefork->cleanup;
  $prefork = $prefork->cleanup($bool);

Delete L</"lock_file"> and L</"pid_file"> automatically once they are not
needed anymore, defaults to a true value.

=head2 graceful_timeout

  my $timeout = $prefork->graceful_timeout;
  $prefork    = $prefork->graceful_timeout(15);

Maximum amount of time in seconds stopping a worker gracefully may take before
being forced, defaults to C<20>.

=head2 heartbeat_interval

  my $interval = $prefork->heartbeat_intrval;
  $prefork     = $prefork->heartbeat_interval(3);

Heartbeat interval in seconds, defaults to C<5>.

=head2 heartbeat_timeout

  my $timeout = $prefork->heartbeat_timeout;
  $prefork    = $prefork->heartbeat_timeout(2);

Maximum amount of time in seconds before a worker without a heartbeat will be
stopped gracefully, defaults to C<20>.

=head2 lock_file

  my $file = $prefork->lock_file;
  $prefork = $prefork->lock_file('/tmp/prefork.lock');

Full path of accept mutex lock file prefix, to which the process id will be
appended, defaults to a random temporary path.

=head2 lock_timeout

  my $timeout = $prefork->lock_timeout;
  $prefork    = $prefork->lock_timeout(0.5);

Maximum amount of time in seconds a worker may block when waiting for the
accept mutex, defaults to C<1>. Note that changing this value can affect
performance and idle CPU usage.

=head2 multi_accept

  my $multi = $prefork->multi_accept;
  $prefork  = $prefork->multi_accept(100);

Number of connections to accept at once, passed along to
L<Mojo::IOLoop/"multi_accept">.

=head2 pid_file

  my $file = $prefork->pid_file;
  $prefork = $prefork->pid_file('/tmp/prefork.pid');

Full path of process id file, defaults to a random temporary path.

=head2 workers

  my $workers = $prefork->workers;
  $prefork    = $prefork->workers(10);

Number of worker processes, defaults to C<4>. A good rule of thumb is two
worker processes per CPU core for applications that perform mostly
non-blocking operations, blocking operations often require more and benefit
from decreasing the number of concurrent L<Mojo::Server::Daemon/"clients">
(often as low as C<1>).

=head1 METHODS

L<Mojo::Server::Prefork> inherits all methods from L<Mojo::Server::Daemon> and
implements the following new ones.

=head2 check_pid

  my $pid = $prefork->check_pid;

Get process id for running server from L</"pid_file"> or delete it if server
is not running.

  say 'Server is not running' unless $prefork->check_pid;

=head2 ensure_pid_file

  $prefork->ensure_pid_file;

Ensure L</"pid_file"> exists.

=head2 healthy

  my $healthy = $prefork->healthy;

Number of currently active worker processes with a heartbeat.

=head2 run

  $prefork->run;

Run server.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
