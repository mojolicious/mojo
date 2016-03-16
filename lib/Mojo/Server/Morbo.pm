package Mojo::Server::Morbo;
use Mojo::Base -base;

# "Linda: With Haley's Comet out of ice, Earth is experiencing the devastating
#         effects of sudden, intense global warming.
#  Morbo: Morbo is pleased but sticky."
use Mojo::Server::Daemon;
use Mojo::Util qw(deprecated files);
use POSIX 'WNOHANG';

has daemon => sub { Mojo::Server::Daemon->new };
has watch  => sub { [qw(lib templates)] };

# DEPRECATED!
sub check {
  deprecated 'Mojo::Server::Morbo::check is DEPRECATED'
    . ' in favor of Mojo::Server::Morbo::modified_files';
  return shift->modified_files->[0];
}

sub modified_files {
  my $self = shift;

  my $cache = $self->{cache} ||= {};
  my @files;
  for my $file (map { -f $_ && -r _ ? $_ : files $_ } @{$self->watch}) {
    my ($size, $mtime) = (stat $file)[7, 9];
    my $stats = $cache->{$file} ||= [$^T, $size];
    next if $mtime <= $stats->[0] && $size == $stats->[1];
    @$stats = ($mtime, $size);
    push @files, $file;
  }

  return \@files;
}

sub run {
  my ($self, $app) = @_;

  # Clean manager environment
  local $SIG{INT} = local $SIG{TERM} = sub {
    $self->{finished} = 1;
    kill 'TERM', $self->{worker} if $self->{worker};
  };
  unshift @{$self->watch}, $0 = $app;
  $self->{modified} = 1;

  # Prepare and cache listen sockets for smooth restarting
  $self->daemon->start->stop;

  $self->_manage until $self->{finished} && !$self->{worker};
  exit 0;
}

sub _manage {
  my $self = shift;

  if (my @files = @{$self->modified_files}) {
    say @files == 1
      ? qq{File "@{[$files[0]]}" changed, restarting.}
      : qq{@{[scalar @files]} files changed, restarting.}
      if $ENV{MORBO_VERBOSE};
    kill 'TERM', $self->{worker} if $self->{worker};
    $self->{modified} = 1;
  }

  if (my $pid = $self->{worker}) {
    delete $self->{worker} if waitpid($pid, WNOHANG) == $pid;
  }

  $self->_spawn if !$self->{worker} && delete $self->{modified};
  sleep 1;
}

sub _spawn {
  my $self = shift;

  # Manager
  my $manager = $$;
  die "Can't fork: $!" unless defined(my $pid = $self->{worker} = fork);
  return if $pid;

  # Worker
  my $daemon = $self->daemon;
  $daemon->load_app($self->watch->[0]);
  $daemon->ioloop->recurring(1 => sub { shift->stop unless kill 0, $manager });
  $daemon->run;
  exit 0;
}

1;

=encoding utf8

=head1 NAME

Mojo::Server::Morbo - Tonight at 11...DOOOOOOOOOOOOOOOM!

=head1 SYNOPSIS

  use Mojo::Server::Morbo;

  my $morbo = Mojo::Server::Morbo->new;
  $morbo->run('/home/sri/myapp.pl');

=head1 DESCRIPTION

L<Mojo::Server::Morbo> is a full featured, self-restart capable non-blocking
I/O HTTP and WebSocket server, built around the very well tested and reliable
L<Mojo::Server::Daemon>, with IPv6, TLS, SNI, Comet (long polling), keep-alive
and multiple event loop support. Note that the server uses signals for process
management, so you should avoid modifying signal handlers in your applications.

To start applications with it you can use the L<morbo> script.

  $ morbo ./myapp.pl
  Server available at http://127.0.0.1:3000

For better scalability (epoll, kqueue) and to provide non-blocking name
resolution, SOCKS5 as well as TLS support, the optional modules L<EV> (4.0+),
L<Net::DNS::Native> (0.15+), L<IO::Socket::Socks> (0.64+) and
L<IO::Socket::SSL> (1.94+) will be used automatically if possible. Individual
features can also be disabled with the C<MOJO_NO_NDN>, C<MOJO_NO_SOCKS> and
C<MOJO_NO_TLS> environment variables.

See L<Mojolicious::Guides::Cookbook/"DEPLOYMENT"> for more.

=head1 SIGNALS

The L<Mojo::Server::Morbo> process can be controlled at runtime with the
following signals.

=head2 INT, TERM

Shut down server immediately.

=head1 ATTRIBUTES

L<Mojo::Server::Morbo> implements the following attributes.

=head2 daemon

  my $daemon = $morbo->daemon;
  $morbo     = $morbo->daemon(Mojo::Server::Daemon->new);

L<Mojo::Server::Daemon> object this server manages.

=head2 watch

  my $watch = $morbo->watch;
  $morbo    = $morbo->watch(['/home/sri/my_app']);

Files and directories to watch for changes, defaults to the application script
as well as the C<lib> and C<templates> directories in the current working
directory.

=head1 METHODS

L<Mojo::Server::Morbo> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 modified_files

  my $files = $morbo->modified_files;

Check if files from L</"watch"> have been modified since the last check and
return an array reference with the results.

  # All files that have been modified
  say for @{$morbo->modified_files};

=head2 run

  $morbo->run('script/my_app');

Run server for application and wait for L</"SIGNALS">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
