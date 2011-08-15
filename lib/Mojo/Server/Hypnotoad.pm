package Mojo::Server::Hypnotoad;
use Mojo::Base -base;

use Carp 'croak';
use Cwd 'abs_path';
use Fcntl ':flock';
use File::Basename 'dirname';
use File::Spec;
use IO::File;
use IO::Poll 'POLLIN';
use List::Util 'shuffle';
use Mojo::Server::Daemon;
use POSIX qw/setsid WNOHANG/;
use Scalar::Util 'weaken';

# Preload
use Mojo::UserAgent;

use constant DEBUG => $ENV{HYPNOTOAD_DEBUG} || 0;

sub DESTROY {
  my $self = shift;

  # Worker or command
  return unless $self->{done};

  # Manager
  return unless my $file = $self->{config}->{pid_file};
  unlink $file if -w $file;
}

# "Marge? Since I'm not talking to Lisa,
#  would you please ask her to pass me the syrup?
#  Dear, please pass your father the syrup, Lisa.
#  Bart, tell Dad I will only pass the syrup if it won't be used on any meat
#  product.
#  You dunkin' your sausages in that syrup homeboy?
#  Marge, tell Bart I just want to drink a nice glass of syrup like I do
#  every morning.
#  Tell him yourself, you're ignoring Lisa, not Bart.
#  Bart, thank your mother for pointing that out.
#  Homer, you're not not-talking to me and secondly I heard what you said.
#  Lisa, tell your mother to get off my case.
#  Uhhh, dad, Lisa's the one you're not talking to.
#  Bart, go to your room."
sub run {
  my ($self, $app, $config) = @_;

  # No windows support
  _exit('Hypnotoad not available for Windows.')
    if $^O eq 'MSWin32' || $^O =~ /cygwin/;

  # Application
  $ENV{HYPNOTOAD_APP} ||= abs_path $app;

  # Config
  $ENV{HYPNOTOAD_CONFIG} ||= abs_path $config;

  # This is a production server
  $ENV{MOJO_MODE} ||= 'production';

  # Executable
  $ENV{HYPNOTOAD_EXE} ||= $0;
  $0 = $ENV{HYPNOTOAD_APP};

  # Clean start
  exec $ENV{HYPNOTOAD_EXE} unless $ENV{HYPNOTOAD_REV}++;

  # Preload application
  my $daemon = $self->{daemon} = Mojo::Server::Daemon->new;
  warn "APPLICATION $ENV{HYPNOTOAD_APP}\n" if DEBUG;
  $daemon->load_app($ENV{HYPNOTOAD_APP});

  # Load configuration
  $self->_config;

  # Testing
  _exit('Everything looks good!') if $ENV{HYPNOTOAD_TEST};

  # Stop running server
  $self->_stop if $ENV{HYPNOTOAD_STOP};

  # Initiate hot deployment
  $self->_hot_deploy unless $ENV{HYPNOTOAD_PID};

  # Prepare loop
  $daemon->prepare_ioloop;

  # Pipe for worker communication
  pipe($self->{reader}, $self->{writer})
    or croak "Can't create pipe: $!";
  $self->{poll} = IO::Poll->new;
  $self->{poll}->mask($self->{reader}, POLLIN);

  # Daemonize
  if (!DEBUG && !$ENV{HYPNOTOAD_FOREGROUND}) {

    # Fork and kill parent
    die "Can't fork: $!" unless defined(my $pid = fork);
    exit 0 if $pid;
    setsid or die "Can't start a new session: $!";

    # Close file handles
    open STDIN,  '</dev/null';
    open STDOUT, '>/dev/null';
    open STDERR, '>&STDOUT';
  }

  # Manager environment
  my $c = $self->{config};
  $SIG{INT} = $SIG{TERM} = sub { $self->{done} = 1 };
  $SIG{CHLD} = sub {
    while ((my $pid = waitpid -1, WNOHANG) > 0) { $self->_reap($pid) }
  };
  $SIG{QUIT} = sub { $self->{done} = $self->{graceful} = 1 };
  $SIG{USR2} = sub { $self->{upgrade} ||= time };
  $SIG{TTIN} = sub { $c->{workers}++ };
  $SIG{TTOU} = sub {
    return unless $c->{workers};
    $c->{workers}--;
    $self->{workers}->{shuffle keys %{$self->{workers}}}->{graceful} ||= time;
  };

  # Mainloop
  warn "MANAGER STARTED $$\n" if DEBUG;
  $self->_manage while 1;
}

sub _config {
  my $self = shift;

  # Load config file
  my $file = $ENV{HYPNOTOAD_CONFIG};
  warn "CONFIG $file\n" if DEBUG;
  my $c = {};
  if (-r $file) {
    unless ($c = do $file) {
      die qq/Can't load config file "$file": $@/ if $@;
      die qq/Can't load config file "$file": $!/ unless defined $c;
      die qq/Config file "$file" did not return a hashref.\n/
        unless ref $c eq 'HASH';
    }
  }
  $self->{config} = $c;

  # Hypnotoad settings
  $c->{graceful_timeout}   ||= 30;
  $c->{heartbeat_interval} ||= 5;
  $c->{heartbeat_timeout}  ||= 5;
  $c->{lock_file}
    ||= File::Spec->catfile($ENV{MOJO_TMPDIR} || File::Spec->tmpdir,
    "hypnotoad.$$.lock");
  $c->{pid_file}
    ||= File::Spec->catfile(dirname($ENV{HYPNOTOAD_APP}), 'hypnotoad.pid');
  $c->{upgrade_timeout} ||= 30;
  $c->{workers}         ||= 4;

  # Daemon settings
  $ENV{MOJO_REVERSE_PROXY} = 1 if $c->{proxy};
  my $daemon = $self->{daemon};
  $daemon->backlog($c->{backlog}) if defined $c->{backlog};
  $daemon->max_clients($c->{clients} || 1000);
  $daemon->group($c->{group}) if $c->{group};
  $daemon->max_requests($c->{keep_alive_requests}      || 25);
  $daemon->keep_alive_timeout($c->{keep_alive_timeout} || 5);
  $daemon->user($c->{user}) if $c->{user};
  $daemon->websocket_timeout($c->{websocket_timeout} || 300);
  $daemon->ioloop->max_accepts($c->{accepts} || 1000);
  my $listen = $c->{listen} || ['http://*:8080'];
  $listen = [$listen] unless ref $listen;
  $daemon->listen($listen);
}

sub _exit { print shift, "\n" and exit 0 }

sub _heartbeat {
  my $self = shift;

  # Poll for heartbeats
  my $poll = $self->{poll};
  $poll->poll(1);
  return unless $poll->handles(POLLIN);
  return unless $self->{reader}->sysread(my $chunk, 4194304);

  # Update heartbeats
  while ($chunk =~ /(\d+)\n/g) {
    my $pid = $1;
    $self->{workers}->{$pid}->{time} = time if $self->{workers}->{$pid};
  }
}

sub _hot_deploy {
  my $self = shift;

  # Make sure server is running
  return unless my $pid = $self->_pid;
  return unless kill 0, $pid;

  # Start hot deployment
  kill 'USR2', $pid;
  _exit("Starting hot deployment for Hypnotoad server $pid.");
}

sub _manage {
  my $self = shift;

  # Housekeeping
  my $c = $self->{config};
  if (!$self->{done}) {

    # Spawn more workers
    $self->_spawn while keys %{$self->{workers}} < $c->{workers};

    # Check PID file
    $self->_pid_file;
  }

  # Shutdown
  elsif (!keys %{$self->{workers}}) { exit 0 }

  # Upgraded
  if ($ENV{HYPNOTOAD_PID} && $ENV{HYPNOTOAD_PID} ne $$) {
    warn "STOPPING MANAGER $ENV{HYPNOTOAD_PID}\n" if DEBUG;
    kill 'QUIT', $ENV{HYPNOTOAD_PID};
  }
  $ENV{HYPNOTOAD_PID} = $$;

  # Check heartbeat
  $self->_heartbeat;

  # Upgrade
  if ($self->{upgrade} && !$self->{done}) {

    # Fresh start
    unless ($self->{new}) {
      warn "UPGRADING\n" if DEBUG;
      croak "Can't fork: $!" unless defined(my $pid = fork);
      $self->{new} = $pid if $pid;
      exec $ENV{HYPNOTOAD_EXE} unless $pid;
    }

    # Timeout
    kill 'KILL', $self->{new}
      if $self->{upgrade} + $c->{upgrade_timeout} <= time;
  }

  # Workers
  while (my ($pid, $w) = each %{$self->{workers}}) {

    # No heartbeat
    my $interval = $c->{heartbeat_interval};
    my $timeout  = $c->{heartbeat_timeout};
    if ($w->{time} + $interval + $timeout <= time) {

      # Try graceful
      warn "STOPPING WORKER $pid\n" if DEBUG;
      $w->{graceful} ||= time;
    }

    # Graceful stop
    $w->{graceful} ||= time if $self->{graceful};
    if ($w->{graceful}) {
      warn "QUIT $pid\n" if DEBUG;
      kill 'QUIT', $pid;

      # Timeout
      $w->{force} = 1
        if $w->{graceful} + $c->{graceful_timeout} <= time;
    }

    # Normal stop
    if (($self->{done} && !$self->{graceful}) || $w->{force}) {

      # Kill
      warn "KILL $pid\n" if DEBUG;
      kill 'KILL', $pid;
    }
  }
}

sub _pid {
  my $self = shift;
  return unless my $file = IO::File->new($self->{config}->{pid_file}, '<');
  my $pid = <$file>;
  chomp $pid;
  return $pid;
}

sub _pid_file {
  my $self = shift;

  # Don't need a PID file anymore
  return if $self->{done};

  # Check if PID file already exists
  my $file = $self->{config}->{pid_file};
  return if -e $file;

  # Create PID file
  warn "PID $file\n" if DEBUG;
  croak qq/Can't create PID file "$file": $!/
    unless my $pid = IO::File->new($file, '>', 0644);
  print $pid $$;
}

# "Dear Mr. President, there are too many states nowadays.
#  Please eliminate three.
#  P.S. I am not a crackpot."
sub _reap {
  my ($self, $pid) = @_;

  # Clean up failed upgrade
  if (($self->{new} || '') eq $pid) {
    warn "UPGRADE FAILED\n" if DEBUG;
    delete $self->{upgrade};
    delete $self->{new};
  }

  # Clean up worker
  else {
    warn "WORKER DIED $pid\n" if DEBUG;
    delete $self->{workers}->{$pid};
  }
}

# "I hope this has taught you kids a lesson: kids never learn."
sub _spawn {
  my $self = shift;

  # Fork
  croak "Can't fork: $!" unless defined(my $pid = fork);

  # Manager
  return $self->{workers}->{$pid} = {time => time} if $pid;

  # Worker
  my $daemon = $self->{daemon};
  my $loop   = $daemon->ioloop;
  my $c      = $self->{config};

  # Prepare lock file
  my $file = $c->{lock_file};
  my $lock = IO::File->new("> $file")
    or croak qq/Can't open lock file "$file": $!/;

  # Accept mutex
  $loop->on_lock(
    sub {

      # Blocking
      my $l;
      if ($_[1]) {
        eval {
          local $SIG{ALRM} = sub { die "alarm\n" };
          my $old = alarm 1;
          $l = flock $lock, LOCK_EX;
          alarm $old;
        };
        if ($@) {
          die $@ unless $@ eq "alarm\n";
          $l = 0;
        }
      }

      # Non blocking
      else { $l = flock $lock, LOCK_EX | LOCK_NB }

      return $l;
    }
  );
  $loop->on_unlock(sub { flock $lock, LOCK_UN });

  # Heartbeat
  weaken $self;
  $loop->recurring(
    $c->{heartbeat_interval} => sub {
      return unless shift->max_connections;
      $self->{writer}->syswrite("$$\n") or exit 0;
    }
  );

  # Clean worker environment
  $SIG{INT} = $SIG{TERM} = $SIG{CHLD} = $SIG{USR2} = $SIG{TTIN} = $SIG{TTOU} =
    'DEFAULT';
  $SIG{QUIT} = sub { $loop->max_connections(0) };
  delete $self->{reader};
  delete $self->{poll};
  $daemon->setuidgid;

  # Start
  warn "WORKER STARTED $$\n" if DEBUG;
  $loop->start;
  exit 0;
}

sub _stop {
  _exit('Hypnotoad server not running.') unless my $pid = shift->_pid;
  kill 'QUIT', $pid;
  _exit("Stopping Hypnotoad server $pid gracefully.");
}

1;
__END__

=head1 NAME

Mojo::Server::Hypnotoad - ALL GLORY TO THE HYPNOTOAD!

=head1 SYNOPSIS

  use Mojo::Server::Hypnotoad;

  my $toad = Mojo::Server::Hypnotoad->new;
  $toad->run('./myapp.pl', './hypnotoad.conf');

=head1 DESCRIPTION

L<Mojo::Server::Hypnotoad> is a full featured UNIX optimized preforking
non-blocking I/O HTTP 1.1 and WebSocket server built around the very well
tested and reliable L<Mojo::Server::Daemon> with C<IPv6>, C<TLS>, C<Bonjour>,
C<libev> and hot deployment support that just works.

To start applications with it you can use the L<hypnotoad> script.

  $ hypnotoad myapp.pl
  Server available at http://127.0.0.1:8080.

You can run the exact same command again for automatic hot deployment.

  $ hypnotoad myapp.pl
  Starting hot deployment for Hypnotoad server 31841.

For L<Mojolicious> and L<Mojolicious::Lite> applications it will default to
C<production> mode.

Optional modules L<EV>, L<IO::Socket::IP>, L<IO::Socket::SSL> and
L<Net::Rendezvous::Publish> are supported transparently and used if
installed.

See L<Mojolicious::Guides::Cookbook> for deployment recipes.

=head1 SIGNALS

You can control C<hypnotoad> at runtime with signals.

=head2 Manager

=over 2

=item C<INT>, C<TERM>

Shutdown server immediately.

=item C<QUIT>

Shutdown server gracefully.

=item C<TTIN>

Increase worker pool by one.

=item C<TTOU>

Decrease worker pool by one.

=item C<USR2>

Attempt zero downtime software upgrade (hot deployment) without losing any
incoming connections.

  Manager (old)
  |- Worker [1]
  |- Worker [2]
  |- Worker [3]
  |- Worker [4]
  `- Manager
     |- Worker [1]
     |- Worker [2]
     |- Worker [3]
     `- Worker [4]

The new manager will automatically send a C<QUIT> signal to the old manager
and take over serving requests after starting up successfully.

=back

=head2 Worker

=over 2

=item C<INT>, C<TERM>

Stop worker immediately.

=item C<QUIT>

Stop worker gracefully.

=back

=head1 CONFIGURATION

C<Hypnotoad> configuration files are normal Perl scripts returning a hash.

  # hypnotoad.conf
  {listen => ['http://*:3000', 'http://*:4000'], workers => 10};

The following parameters are currently available:

=head2 C<accepts>

  accepts => 100

Maximum number of connections a worker is allowed to accept before stopping
gracefully, defaults to C<1000>.
Setting the value to C<0> will allow workers to accept new connections
infinitely.

=head2 C<backlog>

  backlog => 128

Listen backlog size, defaults to C<SOMAXCONN>.

=head2 C<clients>

  clients => 100

Maximum number of parallel client connections per worker process, defaults to
C<1000>.

=head2 C<graceful_timeout>

  graceful_timeout => 15

Time in seconds a graceful worker stop may take before being forced, defaults
to C<30>.

=head2 C<group>

  group => 'staff'

Group name for worker processes.

=head2 C<heartbeat_interval>

  heartbeat_interval => 3

Heartbeat interval in seconds, defaults to C<5>.

=head2 C<heartbeat_timeout>

  heartbeat_timeout => 2

Time in seconds before a worker without a heartbeat will be stopped, defaults
to C<5>.

=head2 C<keep_alive_requests>

  keep_alive_requests => 50

Number of keep alive requests per connection, defaults to C<25>.

=head2 C<keep_alive_timeout>

  keep_alive_timeout => 10

Maximum amount of time in seconds a connection can be inactive before being
dropped, defaults to C<15>.

=head2 C<listen>

  listen => ['http://*:80']

List of one or more locations to listen on, defaults to C<http://*:8080>.

=head2 C<lock_file>

  lock_file => '/tmp/hypnotoad.lock'

Full path to accept mutex lock file, defaults to a random temporary file.

=head2 C<pid_file>

  pid_file => '/var/run/hypnotoad.pid'

Full path to PID file, defaults to C<hypnotoad.pid> in the same directory as
the application.

=head2 C<proxy>

  proxy => 1

Activate reverse proxy support, defaults to the value of
the C<MOJO_REVERSE_PROXY> environment variable.

=head2 C<upgrade_timeout>

  upgrade_timeout => 15

Time in seconds a zero downtime software upgrade may take before being
aborted, defaults to C<30>.

=head2 C<user>

  user => 'sri'

Username for worker processes.

=head2 C<websocket_timeout>

  websocket_timeout => 150

Maximum amount of time in seconds a WebSocket connection can be inactive
before being dropped, defaults to C<300>.

=head2 C<workers>

  workers => 10

Number of worker processes, defaults to C<4>.
A good rule of thumb is two worker processes per cpu core.

=head1 METHODS

L<Mojo::Server::Hypnotoad> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<run>

  $toad->run('script/myapp', 'hypnotoad.conf');

Start server.

=head1 DEBUGGING

You can set the C<HYPNOTOAD_DEBUG> environment variable to get some advanced
diagnostics information printed to C<STDERR>.

  HYPNOTOAD_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
