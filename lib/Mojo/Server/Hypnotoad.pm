package Mojo::Server::Hypnotoad;
use Mojo::Base -base;

# "Bender: I was God once.
#  God: Yes, I saw. You were doing well, until everyone died."
use Cwd 'abs_path';
use File::Basename 'dirname';
use File::Spec::Functions 'catfile';
use Mojo::Server::Prefork;
use Mojo::Util 'steady_time';
use POSIX 'setsid';
use Scalar::Util 'weaken';

sub run {
  my ($self, $path) = @_;

  # No Windows support
  _exit('Hypnotoad not available for Windows.') if $^O eq 'MSWin32';

  # Remember application for later
  $ENV{HYPNOTOAD_APP} ||= abs_path $path;

  # This is a production server
  $ENV{MOJO_MODE} ||= 'production';

  # Remember executable for later
  $ENV{HYPNOTOAD_EXE} ||= $0;
  $0 = $ENV{HYPNOTOAD_APP};

  # Clean start
  die "Can't exec: $!" if !$ENV{HYPNOTOAD_REV}++ && !exec $ENV{HYPNOTOAD_EXE};

  # Preload application and configure server
  my $prefork = $self->{prefork} = Mojo::Server::Prefork->new;
  my $app = $prefork->load_app($ENV{HYPNOTOAD_APP});
  $self->_config($app);
  weaken $self;
  $prefork->on(wait   => sub { $self->_manage });
  $prefork->on(reap   => sub { $self->_reap(pop) });
  $prefork->on(finish => sub { $self->{finished} = 1 });

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
  local $SIG{USR2} = sub { $self->{upgrade} ||= steady_time };
  $prefork->run;
}

sub _config {
  my ($self, $app) = @_;

  # Hypnotoad settings
  my $c = $app->config('hypnotoad') || {};
  $self->{upgrade_timeout} = $c->{upgrade_timeout} || 60;

  # Prefork settings
  $ENV{MOJO_REVERSE_PROXY} = $c->{proxy} if defined $c->{proxy};
  my $prefork = $self->{prefork}->listen($c->{listen} || ['http://*:8080']);
  my $file = catfile dirname($ENV{HYPNOTOAD_APP}), 'hypnotoad.pid';
  $prefork->pid_file($c->{pid_file} || $file);
  $prefork->max_clients($c->{clients}) if $c->{clients};
  $prefork->max_requests($c->{keep_alive_requests})
    if $c->{keep_alive_requests};
  defined $c->{$_} and $prefork->$_($c->{$_})
    for qw(accept_interval accepts backlog graceful_timeout group),
    qw(heartbeat_interval heartbeat_timeout inactivity_timeout lock_file),
    qw(lock_timeout multi_accept user workers);
}

sub _exit { say shift and exit 0 }

sub _hot_deploy {
  my $self = shift;

  # Make sure server is running
  return unless my $pid = $self->{prefork}->check_pid;

  # Start hot deployment
  kill 'USR2', $pid;
  _exit("Starting hot deployment for Hypnotoad server $pid.");
}

sub _manage {
  my $self = shift;

  # Upgraded
  my $log = $self->{prefork}->app->log;
  if ($ENV{HYPNOTOAD_PID} && $ENV{HYPNOTOAD_PID} ne $$) {
    $log->info("Upgrade successful, stopping $ENV{HYPNOTOAD_PID}.");
    kill 'QUIT', $ENV{HYPNOTOAD_PID};
  }
  $ENV{HYPNOTOAD_PID} = $$ unless ($ENV{HYPNOTOAD_PID} // '') eq $$;

  # Upgrade
  if ($self->{upgrade} && !$self->{finished}) {

    # Fresh start
    unless ($self->{new}) {
      $log->info('Starting zero downtime software upgrade.');
      die "Can't fork: $!" unless defined(my $pid = $self->{new} = fork);
      exec($ENV{HYPNOTOAD_EXE}) or die("Can't exec: $!") unless $pid;
    }

    # Timeout
    kill 'KILL', $self->{new}
      if $self->{upgrade} + $self->{upgrade_timeout} <= steady_time;
  }
}

sub _reap {
  my ($self, $pid) = @_;

  # Clean up failed upgrade
  return unless ($self->{new} || '') eq $pid;
  $self->{prefork}->app->log->info('Zero downtime software upgrade failed.');
  delete $self->{$_} for qw(new upgrade);
}

sub _stop {
  _exit('Hypnotoad server not running.')
    unless my $pid = shift->{prefork}->check_pid;
  kill 'QUIT', $pid;
  _exit("Stopping Hypnotoad server $pid gracefully.");
}

1;

=head1 NAME

Mojo::Server::Hypnotoad - ALL GLORY TO THE HYPNOTOAD!

=head1 SYNOPSIS

  use Mojo::Server::Hypnotoad;

  my $toad = Mojo::Server::Hypnotoad->new;
  $toad->run('/home/sri/myapp.pl');

=head1 DESCRIPTION

L<Mojo::Server::Hypnotoad> is a full featured, UNIX optimized, preforking
non-blocking I/O HTTP and WebSocket server, built around the very well tested
and reliable L<Mojo::Server::Prefork>, with C<IPv6>, C<TLS>, C<Comet> (long
polling), C<keep-alive>, connection pooling, timeout, cookie, multipart,
multiple event loop and hot deployment support that just works. Note that the
server uses signals for process management, so you should avoid modifying
signal handlers in your applications.

To start applications with it you can use the L<hypnotoad> script.

  $ hypnotoad myapp.pl
  Server available at http://127.0.0.1:8080.

You can run the same command again for automatic hot deployment.

  $ hypnotoad myapp.pl
  Starting hot deployment for Hypnotoad server 31841.

For L<Mojolicious> and L<Mojolicious::Lite> applications it will default to
C<production> mode.

Optional modules L<EV> (4.0+), L<IO::Socket::IP> (0.16+) and
L<IO::Socket::SSL> (1.75+) are supported transparently through
L<Mojo::IOLoop>, and used if installed. Individual features can also be
disabled with the MOJO_NO_IPV6 and MOJO_NO_TLS environment variables.

See L<Mojolicious::Guides::Cookbook> for more.

=head1 SIGNALS

L<Mojo::Server::Hypnotoad> can be controlled at runtime with the following
signals.

=head2 Manager

=over 2

=item INT, TERM

Shutdown server immediately.

=item QUIT

Shutdown server gracefully.

=item TTIN

Increase worker pool by one.

=item TTOU

Decrease worker pool by one.

=item USR2

Attempt zero downtime software upgrade (hot deployment) without losing any
incoming connections.

  Manager (old)
  |- Worker [1]
  |- Worker [2]
  |- Worker [3]
  |- Worker [4]
  +- Manager (new)
     |- Worker [1]
     |- Worker [2]
     |- Worker [3]
     +- Worker [4]

The new manager will automatically send a C<QUIT> signal to the old manager
and take over serving requests after starting up successfully.

=back

=head2 Worker

=over 2

=item INT, TERM

Stop worker immediately.

=item QUIT

Stop worker gracefully.

=back

=head1 SETTINGS

L<Mojo::Server::Hypnotoad> can be configured with the following settings, see
L<Mojolicious::Guides::Cookbook/"Hypnotoad"> for examples.

=head2 accept_interval

  accept_interval => 0.5

Interval in seconds for trying to reacquire the accept mutex, defaults to
C<0.025>. Note that changing this value can affect performance and idle CPU
usage.

=head2 accepts

  accepts => 100

Maximum number of connections a worker is allowed to accept before stopping
gracefully, defaults to C<1000>. Setting the value to C<0> will allow workers
to accept new connections indefinitely. Note that up to half of this value can
be subtracted randomly to improve load balancing, and that worker processes
will stop sending heartbeat messages once the limit has been reached.

=head2 backlog

  backlog => 128

Listen backlog size, defaults to C<SOMAXCONN>.

=head2 clients

  clients => 100

Maximum number of parallel client connections per worker process, defaults to
C<1000>. Note that depending on how much your application may block, you might
want to decrease this value and increase C<workers> instead for better
performance.

=head2 graceful_timeout

  graceful_timeout => 15

Maximum amount of time in seconds stopping a worker gracefully may take before
being forced, defaults to C<20>.

=head2 group

  group => 'staff'

Group name for worker processes.

=head2 heartbeat_interval

  heartbeat_interval => 3

Heartbeat interval in seconds, defaults to C<5>.

=head2 heartbeat_timeout

  heartbeat_timeout => 2

Maximum amount of time in seconds before a worker without a heartbeat will be
stopped gracefully, defaults to C<20>.

=head2 inactivity_timeout

  inactivity_timeout => 10

Maximum amount of time in seconds a connection can be inactive before getting
closed, defaults to C<15>. Setting the value to C<0> will allow connections to
be inactive indefinitely.

=head2 keep_alive_requests

  keep_alive_requests => 50

Number of keep-alive requests per connection, defaults to C<25>.

=head2 listen

  listen => ['http://*:80']

List of one or more locations to listen on, defaults to C<http://*:8080>. See
also L<Mojo::Server::Daemon/"listen"> for more examples.

=head2 lock_file

  lock_file => '/tmp/hypnotoad.lock'

Full path of accept mutex lock file prefix, to which the process id will be
appended, defaults to a random temporary path.

=head2 lock_timeout

  lock_timeout => 0.5

Maximum amount of time in seconds a worker may block when waiting for the
accept mutex, defaults to C<1>. Note that changing this value can affect
performance and idle CPU usage.

=head2 multi_accept

  multi_accept => 100

Number of connections to accept at once, defaults to C<50>.

=head2 pid_file

  pid_file => '/var/run/hypnotoad.pid'

Full path to process id file, defaults to C<hypnotoad.pid> in the same
directory as the application. Note that this value can only be changed after
the server has been stopped.

=head2 proxy

  proxy => 1

Activate reverse proxy support, which allows for the C<X-Forwarded-For> and
C<X-Forwarded-HTTPS> headers to be picked up automatically, defaults to the
value of the MOJO_REVERSE_PROXY environment variable.

=head2 upgrade_timeout

  upgrade_timeout => 45

Maximum amount of time in seconds a zero downtime software upgrade may take
before getting canceled, defaults to C<60>.

=head2 user

  user => 'sri'

Username for worker processes.

=head2 workers

  workers => 10

Number of worker processes, defaults to C<4>. A good rule of thumb is two
worker processes per CPU core.

=head1 METHODS

L<Mojo::Server::Hypnotoad> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 run

  $toad->run('script/myapp');

Run server for application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
