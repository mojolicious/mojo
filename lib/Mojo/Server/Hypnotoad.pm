package Mojo::Server::Hypnotoad;
use Mojo::Base -base;

use Carp 'croak';
use Cwd 'abs_path';
use Fcntl ':flock';
use File::Basename 'dirname';
use File::Spec::Functions qw/catfile tmpdir/;
use IO::File;
use IO::Poll 'POLLIN';
use List::Util 'shuffle';
use Mojo::Server::Daemon;
use POSIX qw/setsid WNOHANG/;
use Scalar::Util 'weaken';
use Time::HiRes 'ualarm';

# Preload
use Mojo::UserAgent;

sub DESTROY {
  my $self = shift;

  # Worker or command
  return unless $self->{finished};

  # Manager
  if (my $file = $self->{config}->{pid_file})  { unlink $file if -w $file }
  if (my $file = $self->{config}->{lock_file}) { unlink $file if -w $file }
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
  my ($self, $path, $config) = @_;

  # No windows support
  _exit('Hypnotoad not available for Windows.') if $^O eq 'MSWin32';

  # Application
  $ENV{HYPNOTOAD_APP} ||= abs_path $path;

  # DEPRECATED in Leaf Fluttering In Wind!
  $ENV{HYPNOTOAD_CONFIG} ||= abs_path $config;

  # This is a production server
  $ENV{MOJO_MODE} ||= 'production';

  # Executable
  $ENV{HYPNOTOAD_EXE} ||= $0;
  $0 = $ENV{HYPNOTOAD_APP};

  # Clean start
  exec $ENV{HYPNOTOAD_EXE} unless $ENV{HYPNOTOAD_REV}++;

  # Preload application and configure server
  my $daemon = $self->{daemon} = Mojo::Server::Daemon->new;
  $self->_config(my $app = $daemon->load_app($ENV{HYPNOTOAD_APP}));

  # Testing
  _exit('Everything looks good!') if $ENV{HYPNOTOAD_TEST};

  # Stop running server
  $self->_stop if $ENV{HYPNOTOAD_STOP};

  # Initiate hot deployment
  $self->_hot_deploy unless $ENV{HYPNOTOAD_PID};

  # Daemonize as early as possible (but not for restarts)
  if (!$ENV{HYPNOTOAD_FOREGROUND} && $ENV{HYPNOTOAD_REV} < 3) {

    # Fork and kill parent
    die "Can't fork: $!" unless defined(my $pid = fork);
    exit 0 if $pid;
    setsid or die "Can't start a new session: $!";

    # Close file handles
    open STDIN,  '</dev/null';
    open STDOUT, '>/dev/null';
    open STDERR, '>&STDOUT';
  }

  # Start accepting connections
  ($self->{log} = $app->log)
    ->info(qq/Hypnotoad server $$ started for "$ENV{HYPNOTOAD_APP}"./);
  $daemon->start;

  # Pipe for worker communication
  pipe($self->{reader}, $self->{writer})
    or croak "Can't create pipe: $!";
  $self->{poll} = IO::Poll->new;
  $self->{poll}->mask($self->{reader}, POLLIN);

  # Manager environment
  my $c = $self->{config};
  $SIG{INT} = $SIG{TERM} = sub { $self->{finished} = 1 };
  $SIG{CHLD} = sub {
    while ((my $pid = waitpid -1, WNOHANG) > 0) { $self->_reap($pid) }
  };
  $SIG{QUIT} = sub { $self->{finished} = $self->{graceful} = 1 };
  $SIG{USR2} = sub { $self->{upgrade} ||= time };
  $SIG{TTIN} = sub { $c->{workers}++ };
  $SIG{TTOU} = sub {
    return unless $c->{workers};
    $c->{workers}--;
    $self->{workers}->{shuffle keys %{$self->{workers}}}->{graceful} ||= time;
  };

  # Mainloop
  $self->_manage while 1;
}

sub _config {
  my ($self, $app) = @_;

  # Load configuration from application
  my $c = $app->config('hypnotoad') || {};

  # DEPRECATED in Leaf Fluttering In Wind!
  if (-r (my $file = $ENV{HYPNOTOAD_CONFIG})) {
    warn "Hypnotoad config files are DEPRECATED!\n";
    unless ($c = do $file) {
      die qq/Can't load config file "$file": $@/ if $@;
      die qq/Can't load config file "$file": $!/ unless defined $c;
      die qq/Config file "$file" did not return a hashref.\n/
        unless ref $c eq 'HASH';
    }
  }

  # Hypnotoad settings
  $self->{config} = $c;
  $c->{graceful_timeout}   ||= 30;
  $c->{heartbeat_interval} ||= 5;
  $c->{heartbeat_timeout}  ||= 10;
  $c->{lock_file} ||= catfile($ENV{MOJO_TMPDIR} || tmpdir, 'hypnotoad.lock');
  $c->{lock_file} .= ".$$";
  $c->{lock_timeout} ||= '0.5';
  $c->{pid_file} ||= catfile(dirname($ENV{HYPNOTOAD_APP}), 'hypnotoad.pid');
  $c->{upgrade_timeout} ||= 60;
  $c->{workers}         ||= 4;

  # Daemon settings
  $ENV{MOJO_REVERSE_PROXY} = 1 if $c->{proxy};
  my $daemon = $self->{daemon};
  $daemon->backlog($c->{backlog}) if defined $c->{backlog};
  $daemon->max_clients($c->{clients} || 1000);
  $daemon->group($c->{group}) if $c->{group};
  $daemon->max_requests($c->{keep_alive_requests}      || 25);
  $daemon->inactivity_timeout($c->{inactivity_timeout} || 15);
  $daemon->user($c->{user}) if $c->{user};
  $daemon->ioloop->max_accepts($c->{accepts} || 1000);
  my $listen = $c->{listen} || ['http://*:8080'];
  $listen = [$listen] unless ref $listen;
  $daemon->listen($listen);

  # DEPRECATED in Leaf Fluttering In Wind!
  $daemon->inactivity_timeout($c->{keep_alive_timeout})
    if $c->{keep_alive_timeout};
}

sub _exit { say shift and exit 0 }

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
  if (!$self->{finished}) {

    # Spawn more workers
    $self->_spawn while keys %{$self->{workers}} < $c->{workers};

    # Check PID file
    $self->_pid_file;
  }

  # Shutdown
  elsif (!keys %{$self->{workers}}) { exit 0 }

  # Upgraded
  if ($ENV{HYPNOTOAD_PID} && $ENV{HYPNOTOAD_PID} ne $$) {
    $self->{log}->info("Upgrade successful, stopping $ENV{HYPNOTOAD_PID}.");
    kill 'QUIT', $ENV{HYPNOTOAD_PID};
  }
  $ENV{HYPNOTOAD_PID} = $$;

  # Check heartbeat
  $self->_heartbeat;

  # Upgrade
  if ($self->{upgrade} && !$self->{finished}) {

    # Fresh start
    unless ($self->{new}) {
      $self->{log}->info('Starting zero downtime software upgrade.');
      croak "Can't fork: $!" unless defined(my $pid = fork);
      $self->{new} = $pid ? $pid : exec($ENV{HYPNOTOAD_EXE});
    }

    # Timeout
    kill 'KILL', $self->{new}
      if $self->{upgrade} + $c->{upgrade_timeout} <= time;
  }

  # Workers
  while (my ($pid, $w) = each %{$self->{workers}}) {

    # No heartbeat (graceful stop)
    my $interval = $c->{heartbeat_interval};
    my $timeout  = $c->{heartbeat_timeout};
    if ($w->{time} + $interval + $timeout <= time) {
      $self->{log}->info("Worker $pid has no heartbeat, restarting.");
      $w->{graceful} ||= time;
    }

    # Graceful stop with timeout
    $w->{graceful} ||= time if $self->{graceful};
    if ($w->{graceful}) {
      $self->{log}->debug("Trying to stop worker $pid gracefully.");
      kill 'QUIT', $pid;
      $w->{force} = 1 if $w->{graceful} + $c->{graceful_timeout} <= time;
    }

    # Normal stop
    if (($self->{finished} && !$self->{graceful}) || $w->{force}) {
      $self->{log}->debug("Stopping worker $pid.");
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
  return if $self->{finished};

  # Check if PID file already exists
  return if -e (my $file = $self->{config}->{pid_file});

  # Create PID file
  $self->{log}->info(qq/Creating PID file "$file"./);
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
    $self->{log}->info('Zero downtime software upgrade failed.');
    delete $self->{upgrade};
    delete $self->{new};
  }

  # Clean up worker
  else {
    $self->{log}->debug("Worker $pid stopped.");
    delete $self->{workers}->{$pid};
  }
}

# "I hope this has taught you kids a lesson: kids never learn."
sub _spawn {
  my $self = shift;

  # Manager
  croak "Can't fork: $!" unless defined(my $pid = fork);
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
  $loop->lock(
    sub {

      # Blocking
      my $l;
      if ($_[1]) {
        eval {
          local $SIG{ALRM} = sub { die "alarm\n" };
          my $old = ualarm $c->{lock_timeout} * 1000000;
          $l = flock $lock, LOCK_EX;
          ualarm $old;
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
  $loop->unlock(sub { flock $lock, LOCK_UN });

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
  $self->{log}->debug("Worker $$ started.");
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
  $toad->run('./myapp.pl');

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
installed. Individual features can also be disabled with the
C<MOJO_NO_BONJOUR>, C<MOJO_NO_IPV6> and C<MOJO_NO_TLS> environment variables.

See L<Mojolicious::Guides::Cookbook> for deployment recipes.

=head1 SIGNALS

L<Mojo::Server::Hypnotoad> can be controlled at runtime with the following
signals.

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
  `- Manager (new)
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

=head1 SETTINGS

L<Mojo::Server::Hypnotoad> can be configured with the following settings, see
L<Mojolicious::Guides::Cookbook/"Hypnotoad"> for examples.

=head2 C<accepts>

  accepts => 100

Maximum number of connections a worker is allowed to accept before stopping
gracefully, defaults to C<1000>. Setting the value to C<0> will allow workers
to accept new connections infinitely.

=head2 C<backlog>

  backlog => 128

Listen backlog size, defaults to C<SOMAXCONN>.

=head2 C<clients>

  clients => 100

Maximum number of parallel client connections per worker process, defaults to
C<1000>.

=head2 C<graceful_timeout>

  graceful_timeout => 15

Maximum amount of time in seconds a graceful worker stop may take before
being forced, defaults to C<30>.

=head2 C<group>

  group => 'staff'

Group name for worker processes.

=head2 C<heartbeat_interval>

  heartbeat_interval => 3

Heartbeat interval in seconds, defaults to C<5>.

=head2 C<heartbeat_timeout>

  heartbeat_timeout => 2

Maximum amount of time in seconds before a worker without a heartbeat will be
stopped, defaults to C<10>.

=head2 C<inactivity_timeout>

  inactivity_timeout => 10

Maximum amount of time in seconds a connection can be inactive before getting
dropped, defaults to C<15>. Setting the value to C<0> will allow connections
to be inactive indefinitely.

=head2 C<keep_alive_requests>

  keep_alive_requests => 50

Number of keep alive requests per connection, defaults to C<25>.

=head2 C<listen>

  listen => ['http://*:80']

List of one or more locations to listen on, defaults to C<http://*:8080>. See
also L<Mojo::Server::Daemon/"listen"> for more examples.

=head2 C<lock_file>

  lock_file => '/tmp/hypnotoad.lock'

Full path to accept mutex lock file, defaults to a random temporary file.

=head2 C<lock_timeout>

  lock_timeout => 1

Maximum amount of time in seconds a worker may block when waiting for the
accept mutex, defaults to C<0.5>.

=head2 C<pid_file>

  pid_file => '/var/run/hypnotoad.pid'

Full path to PID file, defaults to C<hypnotoad.pid> in the same directory as
the application. Note that this value can only be changed after the server
has been stopped.

=head2 C<proxy>

  proxy => 1

Activate reverse proxy support, defaults to the value of
the C<MOJO_REVERSE_PROXY> environment variable.

=head2 C<upgrade_timeout>

  upgrade_timeout => 30

Maximum amount of time in seconds a zero downtime software upgrade may take
before getting canceled, defaults to C<60>.

=head2 C<user>

  user => 'sri'

Username for worker processes.

=head2 C<workers>

  workers => 10

Number of worker processes, defaults to C<4>. A good rule of thumb is two
worker processes per cpu core.

=head1 METHODS

L<Mojo::Server::Hypnotoad> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<run>

  $toad->run('script/myapp');

Run server for application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
