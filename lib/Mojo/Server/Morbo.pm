package Mojo::Server::Morbo;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::Home;
use Mojo::Server::Daemon;
use POSIX 'WNOHANG';

use constant DEBUG => $ENV{MORBO_DEBUG} || 0;

has listen => sub { [] };
has watch  => sub { [qw/lib templates/] };

# Cache stats
my $STATS = {};

# "All in all, this is one day Mittens the kitten won’t soon forget.
#  Kittens give Morbo gas.
#  In lighter news, the city of New New York is doomed.
#  Blame rests with known human Professor Hubert Farnsworth and his tiny,
#  inferior brain."
sub run {
  my ($self, $app) = @_;
  warn "MANAGER STARTED $$\n" if DEBUG;

  # Watch files and manage worker
  $SIG{CHLD} = sub { $self->_reap };
  $SIG{INT} = $SIG{TERM} = $SIG{QUIT} = sub {
    $self->{_done} = 1;
    kill 'TERM', $self->{_running} if $self->{_running};
  };
  unshift @{$self->watch}, $app;
  $self->{_modified} = 1;
  $self->_manage while !$self->{_done} || $self->{_running};
  exit 0;
}

# "And so with two weeks left in the campaign, the question on everyone’s
#  mind is, who will be the president of Earth?
#  Jack Johnson or bitter rival John Jackson.
#  Two terrific candidates, Morbo?
#  All humans are vermin in the eyes of Morbo!"
sub _manage {
  my $self = shift;

  # Discover files
  warn "DISCOVERING NEW FILES\n" if DEBUG;
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
    warn "CHECKING $file\n" if DEBUG;
    next unless defined(my $mtime = (stat $file)[9]);

    # Startup time as default
    $STATS->{$file} = $^T unless defined $STATS->{$file};

    # Modified
    if ($mtime > $STATS->{$file}) {
      warn "MODIFIED $file\n" if DEBUG;
      kill 'TERM', $self->{_running} if $self->{_running};
      $self->{_modified} = 1;
      $STATS->{$file} = $mtime;
    }
  }

  # Housekeeping
  $self->_reap;
  delete $self->{_running} if $self->{_running} && !kill 0, $self->{_running};
  $self->_spawn if !$self->{_running} && delete $self->{_modified};
  sleep 1;
}

sub _reap {
  my $self = shift;
  while ((my $pid = waitpid -1, WNOHANG) > 0) {
    warn "WORKER STOPPED $pid\n" if DEBUG;
    delete $self->{_running};
  }
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
  croak "Can't fork: $!" unless defined(my $pid = fork);

  # Manager
  return $self->{_running} = $pid if $pid;

  # Worker
  warn "WORKER STARTED $$\n" if DEBUG;
  $SIG{CHLD} = 'DEFAULT';
  $SIG{INT} = $SIG{TERM} = $SIG{QUIT} = sub { $self->{_done} = 1 };
  my $daemon = Mojo::Server::Daemon->new;
  $daemon->load_app($self->watch->[0]);
  $daemon->silent(1) if $ENV{MORBO_REV} > 1;
  $daemon->listen($self->listen) if @{$self->listen};
  $daemon->prepare_ioloop;
  my $loop = $daemon->ioloop;
  $loop->recurring(
    1 => sub { shift->stop if !kill(0, $manager) || $self->{_done} });
  $loop->start;
  exit 0;
}

1;
__END__

=head1 NAME

Mojo::Server::Morbo - DOOOOOOOOOOOOOOOOOOM!

=head1 SYNOPSIS

  use Mojo::Server::Morbo;

  my $morbo = Mojo::Server::Morbo->new;
  $morbo->run('./myapp.pl');

=head1 DESCRIPTION

L<Mojo::Server::Morbo> is a full featured self-restart capable async io HTTP
1.1 and WebSocket server built around the very well tested and reliable
L<Mojo::Server::Daemon> with C<IPv6>, C<TLS>, C<Bonjour>, C<epoll> and
C<kqueue> support.

To start applications with it you can use the L<morbo> script.

  % morbo myapp.pl

Optional modules L<IO::KQueue>, L<IO::Epoll>, L<IO::Socket::IP>,
L<IO::Socket::SSL> and L<Net::Rendezvous::Publish> are supported
transparently and used if installed.

Note that this module is EXPERIMENTAL and might change without warning!

=head1 ATTRIBUTES

L<Mojo::Server::Morbo> implements the following attributes.

=head2 C<listen>

  my $listen = $morbo->listen;
  $morbo     = $morbo->listen(['http://*:3000']);

List of ports and files to listen on, defaults to C<http://*:3000>.

=head2 C<watch>

  my $watch = $morbo->watch;
  $morbo    = $morbo->watch(['/home/sri/myapp']);

Files and directories to watch for changes, defaults to the application
script as well as the C<lib> and C<templates> directories in the current
working directory.

=head1 METHODS

L<Mojo::Server::Morbo> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<run>

  $morbo->run('script/myapp');

Start server.

=head1 DEBUGGING

You can set the C<MORBO_DEBUG> environment variable to get some advanced
diagnostics information printed to C<STDERR>.

  MORBO_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
