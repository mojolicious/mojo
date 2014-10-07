package Mojo::Server::Morbo;
use Mojo::Base -base;

# "Linda: With Haley's Comet out of ice, Earth is experiencing the devastating
#         effects of sudden, intense global warming.
#  Morbo: Morbo is pleased but sticky."
use Mojo::Home;
use Mojo::Server::Daemon;
use POSIX 'WNOHANG';

has watch => sub { [qw(lib templates)] };

sub check {
  my $self = shift;

  # Discover files
  my @files;
  for my $watch (@{$self->watch}) {
    if (-d $watch) {
      my $home = Mojo::Home->new->parse($watch);
      push @files, $home->rel_file($_) for @{$home->list_files};
    }
    elsif (-r $watch) { push @files, $watch }
  }

  # Check files
  $self->_check($_) and return $_ for @files;
  return undef;
}

sub run {
  my ($self, $app) = @_;

  # Clean manager environment
  local $SIG{CHLD} = sub { $self->_reap };
  local $SIG{INT} = local $SIG{TERM} = local $SIG{QUIT} = sub {
    $self->{finished} = 1;
    kill 'TERM', $self->{running} if $self->{running};
  };
  unshift @{$self->watch}, $app;
  $self->{modified} = 1;

  # Prepare and cache listen sockets for smooth restarting
  my $daemon = Mojo::Server::Daemon->new(silent => 1)->start->stop;

  $self->_manage while !$self->{finished} || $self->{running};
  exit 0;
}

sub _check {
  my ($self, $file) = @_;

  # Check if modify time and/or size have changed
  my ($size, $mtime) = (stat $file)[7, 9];
  return undef unless defined $mtime;
  my $cache = $self->{cache} ||= {};
  my $stats = $cache->{$file} ||= [$^T, $size];
  return undef if $mtime <= $stats->[0] && $size == $stats->[1];
  return !!($cache->{$file} = [$mtime, $size]);
}

sub _manage {
  my $self = shift;

  if (defined(my $file = $self->check)) {
    say qq{File "$file" changed, restarting.} if $ENV{MORBO_VERBOSE};
    kill 'TERM', $self->{running} if $self->{running};
    $self->{modified} = 1;
  }

  $self->_reap;
  delete $self->{running} if $self->{running} && !kill 0, $self->{running};
  $self->_spawn if !$self->{running} && delete $self->{modified};
  sleep 1;
}

sub _reap { delete $_[0]{running} while (waitpid -1, WNOHANG) > 0 }

sub _spawn {
  my $self = shift;

  # Fork
  my $manager = $$;
  $ENV{MORBO_REV}++;
  die "Can't fork: $!" unless defined(my $pid = fork);

  # Manager
  return $self->{running} = $pid if $pid;

  # Worker
  $SIG{CHLD} = 'DEFAULT';
  $SIG{INT} = $SIG{TERM} = $SIG{QUIT} = sub { $self->{finished} = 1 };
  my $daemon = Mojo::Server::Daemon->new;
  $daemon->load_app($self->watch->[0]);
  $daemon->silent(1) if $ENV{MORBO_REV} > 1;
  $daemon->start;
  my $loop = $daemon->ioloop;
  $loop->recurring(
    1 => sub { shift->stop if !kill(0, $manager) || $self->{finished} });
  $loop->start;
  exit 0;
}

1;

=encoding utf8

=head1 NAME

Mojo::Server::Morbo - DOOOOOOOOOOOOOOOOOOM!

=head1 SYNOPSIS

  use Mojo::Server::Morbo;

  my $morbo = Mojo::Server::Morbo->new;
  $morbo->run('/home/sri/myapp.pl');

=head1 DESCRIPTION

L<Mojo::Server::Morbo> is a full featured, self-restart capable non-blocking
I/O HTTP and WebSocket server, built around the very well tested and reliable
L<Mojo::Server::Daemon>, with IPv6, TLS, Comet (long polling), keep-alive and
multiple event loop support. Note that the server uses signals for process
management, so you should avoid modifying signal handlers in your
applications.

To start applications with it you can use the L<morbo> script.

  $ morbo ./myapp.pl
  Server available at http://127.0.0.1:3000.

For better scalability (epoll, kqueue) and to provide IPv6, SOCKS5 as well as
TLS support, the optional modules L<EV> (4.0+), L<IO::Socket::IP> (0.20+),
L<IO::Socket::Socks> (0.64+) and L<IO::Socket::SSL> (1.84+) will be used
automatically if they are installed. Individual features can also be disabled
with the C<MOJO_NO_IPV6>, C<MOJO_NO_SOCKS> and C<MOJO_NO_TLS> environment
variables.

See L<Mojolicious::Guides::Cookbook/"DEPLOYMENT"> for more.

=head1 ATTRIBUTES

L<Mojo::Server::Morbo> implements the following attributes.

=head2 watch

  my $watch = $morbo->watch;
  $morbo    = $morbo->watch(['/home/sri/myapp']);

Files and directories to watch for changes, defaults to the application script
as well as the C<lib> and C<templates> directories in the current working
directory.

=head1 METHODS

L<Mojo::Server::Morbo> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 check

  my $file = $morbo->check;

Check if file from L</"watch"> has been modified since last check and return
its name or C<undef> if there have been no changes.

=head2 run

  $morbo->run('script/myapp');

Run server for application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
