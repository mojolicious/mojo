package Mojo::Server::Morbo;
use Mojo::Base -base;

# "Linda: With Haley's Comet out of ice, Earth is experiencing the devastating
#         effects of sudden, intense global warming.
#  Morbo: Morbo is pleased but sticky."
use Config;
use Mojo::Loader qw(load_class);
use Mojo::Server::Daemon;
use Mojo::Util qw(steady_time);
use POSIX      qw(WNOHANG _exit setpgid);

has backend => sub {
  my $backend = $ENV{MOJO_MORBO_BACKEND} || 'Poll';
  $backend = "Mojo::Server::Morbo::Backend::$backend";
  return $backend->new unless my $e = load_class $backend;
  die $e if ref $e;
  die qq{Can't find Morbo backend class "$backend" in \@INC. (@INC)\n};
};
has daemon => sub { Mojo::Server::Daemon->new(silent => 1) };
has exec   => sub { [] };
has silent => 1;

sub run {
  my ($self, $app, @args) = @_;

  # No fork emulation support
  die "Morbo does not support fork emulation.\n" if $Config{d_pseudofork};

  # Clean manager environment
  local $SIG{INT} = local $SIG{TERM} = local $SIG{HUP} = sub {
    $self->{finished} = 1;
    $self->_stop($_) for grep {defined} $self->{worker}, keys %{$self->{commands}};
  };
  unshift @{$self->backend->watch}, $0 = $app;
  $self->{command}  = [$^X, $app, @args ? @args : 'daemon'];
  $self->{modified} = 1;

  # Prepare and cache listen sockets for smooth restarting (inherited by the server)
  $self->daemon->start->stop;
  $ENV{MOJO_LISTEN} = join ',', @{$self->daemon->listen};
  $ENV{PERL5LIB}    = join $Config{path_sep}, grep { !ref } @INC;

  # Commands (like asset bundlers in watch mode) need to know the mode too, and only get started once
  $ENV{MOJO_MODE} ||= 'development';

  # Commands get a pipe as STDIN that stays open until Morbo exits, so they can read from it without getting stopped
  # (process group is not in the foreground) and know when to exit if Morbo dies unexpectedly (like esbuild does)
  pipe(my $stdin, $self->{stdin}) or die "Can't create pipe: $!";
  $self->{commands} = {map { $self->_spawn($stdin, $_) => $_ } @{$self->exec}};
  close $stdin;

  $self->_manage until $self->{finished} && !$self->{worker} && !keys %{$self->{commands}};
  exit 0;
}

sub _manage {
  my $self = shift;

  if (my @files = @{$self->backend->modified_files}) {
    say @files == 1
      ? qq{File "@{[$files[0]]}" changed, restarting.}
      : qq{@{[scalar @files]} files changed, restarting.}
      unless $self->silent;
    $self->_stop($self->{worker});
    $self->{modified} = 1;
  }

  for my $pid (grep {defined} $self->{worker}, keys %{$self->{commands}}) {
    if (waitpid($pid, WNOHANG) == $pid) {
      delete $self->{kill}{$pid};
      if    ($self->{worker} && $self->{worker} == $pid) { delete $self->{worker} }
      elsif (!$self->{finished}) {
        my $cmd = $self->{commands}{$pid};
        warn $? & 127
          ? qq{Command "$cmd" was killed by signal @{[$? & 127]}.\n}
          : qq{Command "$cmd" exited with status @{[$? >> 8]}.\n};
      }
      delete $self->{commands}{$pid};
    }

    # Process did not stop in time
    elsif ($self->{kill}{$pid}) { kill 'KILL', -$pid if $self->{kill}{$pid} <= steady_time }

    # Process was started after the signal handler ran
    elsif ($self->{finished}) { $self->_stop($pid) }
  }

  $self->{worker} = $self->_spawn(undef, @{$self->{command}})
    if !$self->{worker} && !$self->{finished} && delete $self->{modified};
}

sub _spawn {
  my ($self, $stdin, @command) = @_;

  # Manager (process group gets set in both processes to avoid a race)
  die "Can't fork: $!" unless defined(my $pid = fork);
  if ($pid) { setpgid $pid, $pid; return $pid }

  # Worker (process group includes subprocesses)
  setpgid 0, 0;
  open STDIN, '<&', $stdin or warn "Can't redirect STDIN: $!\n" if $stdin;

  # Skip cleanup code inherited from the manager if exec fails
  exec(@command) or _exit 1;
}

sub _stop {
  my ($self, $pid) = @_;
  return unless $pid;
  kill 'TERM', -$pid;
  $self->{kill}{$pid} //= steady_time + 5;
}

1;

=encoding utf8

=head1 NAME

Mojo::Server::Morbo - Tonight at 11...DOOOOOOOOOOOOOOOM!

=head1 SYNOPSIS

  use Mojo::Server::Morbo;

  my $morbo = Mojo::Server::Morbo->new;
  $morbo->run('/home/sri/myapp.pl');
  $morbo->run('/home/sri/myapp.pl', 'prefork', '-w', 1);

  Mojo::Server::Morbo->new(exec => ['npx webpack --watch'])->run('/home/sri/myapp.pl');

=head1 DESCRIPTION

L<Mojo::Server::Morbo> is a self-restart capable development server. It starts your application with a server command,
like L<Mojolicious::Command::daemon> or L<Mojolicious::Command::prefork>, and restarts it whenever a file changes. Listen
sockets are only created once and then passed on to the server, so they should be configured with Morbo and not the
server command. Note that the server uses signals for process management, so you should avoid modifying signal handlers
in your applications.

Additional commands, like asset bundlers in watch mode, can be started alongside the server with L</"exec">. They only
get started once, are not restarted together with the server, and get stopped when Morbo shuts down.

To start applications with it you can use the L<morbo> script.

  $ morbo ./myapp.pl
  Web application available at http://127.0.0.1:3000

For better scalability (epoll, kqueue) and to provide non-blocking name resolution, SOCKS5 as well as TLS support, the
optional modules L<EV> (4.32+), L<Net::DNS::Native> (0.15+), L<IO::Socket::Socks> (0.64+) and L<IO::Socket::SSL>
(2.009+) will be used automatically if possible. Individual features can also be disabled with the C<MOJO_NO_NNR>,
C<MOJO_NO_SOCKS> and C<MOJO_NO_TLS> environment variables.

See L<Mojolicious::Guides::Cookbook/"DEPLOYMENT"> for more.

=head1 SIGNALS

The L<Mojo::Server::Morbo> process can be controlled at runtime with the following signals.

=head2 INT, TERM, HUP

Shut down server immediately. The server, all L</"exec"> commands and their subprocesses get a C<TERM> signal, and
will be killed if they have not stopped after 5 seconds, just like for restarts.

=head1 ATTRIBUTES

L<Mojo::Server::Morbo> implements the following attributes.

=head2 backend

  my $backend = $morbo->backend;
  $morbo      = $morbo->backend(Mojo::Server::Morbo::Backend::Poll->new);

Backend, usually a L<Mojo::Server::Morbo::Backend::Poll> object.

=head2 daemon

  my $daemon = $morbo->daemon;
  $morbo     = $morbo->daemon(Mojo::Server::Daemon->new);

L<Mojo::Server::Daemon> object used to create listen sockets. Other settings will be ignored, since the server runs in
a separate process, use options of the server command instead.

=head2 exec

  my $commands = $morbo->exec;
  $morbo       = $morbo->exec(['npx webpack --watch', 'npx tailwindcss -i app.css -o public/assets/app.css --watch']);

Shell commands to start alongside the server, like asset bundlers in watch mode. The C<MOJO_MODE> environment variable
will be set to the operating mode of your application, so commands can use it too. C<STDIN> of all commands is a pipe
that gets closed when Morbo exits, even if it gets killed unexpectedly, which some tools use to shut down. When a
command exits on its own, a message with its exit status is written to C<STDERR>.

=head2 silent

  my $bool = $morbo->silent;
  $morbo   = $morbo->silent($bool);

Disable console messages, defaults to a true value.

=head1 METHODS

L<Mojo::Server::Morbo> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 run

  $morbo->run('script/my_app');
  $morbo->run('script/my_app', 'prefork', '-w', 1);

Run server command for application and wait for L</"SIGNALS">. The command defaults to C<daemon>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
