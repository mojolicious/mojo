package Mojo::Server::Morbo;
use Mojo::Base -base;

use Carp 'croak';
use Cwd 'abs_path';
use Mojo::Home;
use Mojo::Server::Daemon;
use POSIX 'WNOHANG';

use constant DEBUG => $ENV{MORBO_DEBUG} || 0;

has 'app';
has listen => sub { [] };
has watch  => sub { [qw/lib templates public/] };

# Cache stats
my $STATS = {};

# "Kittens give Morbo gas."
sub run {
  my $self = shift;
  warn "MANAGER STARTED $$\n" if DEBUG;

  # Manager signals
  $SIG{INT} = $SIG{TERM} = $SIG{QUIT} = sub { $self->{_done} = 1 };
  $SIG{CHLD} = sub {
    while ((waitpid -1, WNOHANG) > 0) { $self->{_running} = 0 }
  };

  # Resolve paths
  @{$self->watch} = map { abs_path $_ } @{$self->watch};
  $self->app(abs_path $self->app);
  push @{$self->watch}, $self->app;

  # Manage
  $self->_manage while 1;
}

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
      $STATS->{$file} = $mtime;
    }
  }

  # Housekeeping
  exit 0 if !$self->{_running} && $self->{_done};
  unless ($self->{_done}) {
    $self->_spawn if !$self->{_running};
    sleep 1;
  }
  kill 'TERM', $self->{_running} if $self->{_done};
}

# "Hello little man. I WILL DESTROY YOU!"
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
  $SIG{INT} = $SIG{TERM} = $SIG{CHLD} = 'DEFAULT';
  my $daemon = Mojo::Server::Daemon->new;
  $daemon->load_app($self->app);
  $daemon->silent(1) if $ENV{MORBO_REV} > 1;
  $daemon->listen($self->listen) if @{$self->listen};
  $daemon->prepare_ioloop;
  my $loop = $daemon->ioloop;
  $loop->recurring(1 => sub { shift->stop unless kill 0, $manager });
  $loop->start;

  exit 0;
}

1;
__END__

=head1 NAME

Mojo::Server::Morbo - DOOOOOOOOOOOOOOOOOOM!

=head1 SYNOPSIS

  use Mojo::Server::Morbo;

=head1 DESCRIPTION

L<Mojo::Server::Morbo> is a HTTP 1.1 and WebSocket development server.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 ATTRIBUTES

L<Mojo::Server::Morbo> implements the following attributes.

=head2 C<app>

  my $app = $morbo->app;
  $morbo  = $morbo->app('/home/sri/myapp.pl');

Application script.

=head2 C<listen>

  my $listen = $morbo->listen;
  $morbo     = $morbo->listen(['http://*:3000']);

List of ports and files to listen on, defaults to C<http://*:3000>.

=head2 C<watch>

  my $watch = $morbo->watch;
  $morbo    = $morbo->watch(['/home/sri/myapp']);

Files and directories to watch for changes, defaults to the application
script as well as the C<lib>, C<templates> and C<public> directories in the
current working directory.

=head1 METHODS

L<Mojo::Server::Morbo> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<run>

  $morbo->run;

Start server.

=head1 DEBUGGING

You can set the C<MORBO_DEBUG> environment variable to get some advanced
diagnostics information printed to C<STDERR>.

  MORBO_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
