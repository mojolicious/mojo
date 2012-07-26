package Mojo::Server::Morbo;
use Mojo::Base -base;

use Mojo::Home;
use Mojo::Server::Daemon;
use POSIX 'WNOHANG';

has watch => sub { [qw(lib templates)] };

# "All in all, this is one day Mittens the kitten won't soon forget.
#  Kittens give Morbo gas.
#  In lighter news, the city of New New York is doomed.
#  Blame rests with known human Professor Hubert Farnsworth and his tiny,
#  inferior brain."
sub check_file {
  my ($self, $file) = @_;

  # Check if modify time and/or size have changed
  my ($size, $mtime) = (stat $file)[7, 9];
  return unless defined $mtime;
  my $cache = $self->{cache} ||= {};
  my $stats = $cache->{$file} ||= [$^T, $size];
  return if $mtime <= $stats->[0] && $size == $stats->[1];
  return !!($cache->{$file} = [$mtime, $size]);
}

sub run {
  my ($self, $app) = @_;

  # Watch files and manage worker
  $SIG{CHLD} = sub { $self->_reap };
  $SIG{INT} = $SIG{TERM} = $SIG{QUIT} = sub {
    $self->{finished} = 1;
    kill 'TERM', $self->{running} if $self->{running};
  };
  unshift @{$self->watch}, $app;
  $self->{modified} = 1;
  $self->_manage while !$self->{finished} || $self->{running};
  exit 0;
}

# "And so with two weeks left in the campaign, the question on everyone's
#  mind is, who will be the president of Earth?
#  Jack Johnson or bitter rival John Jackson.
#  Two terrific candidates, Morbo?
#  All humans are vermin in the eyes of Morbo!"
sub _manage {
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
  for my $file (@files) {
    next unless $self->check_file($file);
    say qq{File "$file" changed, restarting.} if $ENV{MORBO_VERBOSE};
    kill 'TERM', $self->{running} if $self->{running};
    $self->{modified} = 1;
  }

  # Housekeeping
  $self->_reap;
  delete $self->{running} if $self->{running} && !kill 0, $self->{running};
  $self->_spawn if !$self->{running} && delete $self->{modified};
  sleep 1;
}

sub _reap {
  my $self = shift;
  while ((my $pid = waitpid -1, WNOHANG) > 0) { delete $self->{running} }
}

# "Morbo cannot read his teleprompter.
#  He forgot how you say that letter that looks like a man wearing a hat.
#  It's a T. It goes 'tuh'.
#  Hello, little man. I will destroy you!"
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

=head1 NAME

Mojo::Server::Morbo - DOOOOOOOOOOOOOOOOOOM!

=head1 SYNOPSIS

  use Mojo::Server::Morbo;

  my $morbo = Mojo::Server::Morbo->new;
  $morbo->run('./myapp.pl');

=head1 DESCRIPTION

L<Mojo::Server::Morbo> is a full featured self-restart capable non-blocking
I/O HTTP 1.1 and WebSocket server built around the very well tested and
reliable L<Mojo::Server::Daemon> with C<IPv6>, C<TLS> and C<libev> support.

To start applications with it you can use the L<morbo> script.

  $ morbo myapp.pl
  Server available at http://127.0.0.1:3000.

Optional modules L<EV> (4.0+), L<IO::Socket::IP> (0.16+) and
L<IO::Socket::SSL> (1.75+) are supported transparently and used if installed.
Individual features can also be disabled with the C<MOJO_NO_IPV6> and
C<MOJO_NO_TLS> environment variables.

See L<Mojolicious::Guides::Cookbook> for more.

=head1 ATTRIBUTES

L<Mojo::Server::Morbo> implements the following attributes.

=head2 C<watch>

  my $watch = $morbo->watch;
  $morbo    = $morbo->watch(['/home/sri/myapp']);

Files and directories to watch for changes, defaults to the application script
as well as the C<lib> and C<templates> directories in the current working
directory.

=head1 METHODS

L<Mojo::Server::Morbo> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<check_file>

  my $success = $morbo->check_file('/home/sri/lib/MyApp.pm');

Check if file has been modified since last check.

=head2 C<run>

  $morbo->run('script/myapp');

Run server for application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
