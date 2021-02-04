package Mojo::Server::Morbo;
use Mojo::Base -base;

# "Linda: With Haley's Comet out of ice, Earth is experiencing the devastating
#         effects of sudden, intense global warming.
#  Morbo: Morbo is pleased but sticky."
use Mojo::Loader qw(load_class);
use Mojo::Server::Daemon;
use POSIX qw(WNOHANG);

has backend => sub {
  my $backend = $ENV{MOJO_MORBO_BACKEND} || 'Poll';
  $backend = "Mojo::Server::Morbo::Backend::$backend";
  return $backend->new unless my $e = load_class $backend;
  die $e if ref $e;
  die qq{Can't find Morbo backend class "$backend" in \@INC. (@INC)\n};
};
has daemon => sub { Mojo::Server::Daemon->new };
has silent => 1;

sub run {
  my ($self, $app) = @_;

  # Clean manager environment
  local $SIG{INT} = local $SIG{TERM} = sub {
    $self->{finished} = 1;
    kill 'TERM', $self->{worker} if $self->{worker};
  };
  unshift @{$self->backend->watch}, $0 = $app;
  $self->{modified} = 1;

  # Prepare and cache listen sockets for smooth restarting
  $self->daemon->start->stop;

  $self->_manage until $self->{finished} && !$self->{worker};
  exit 0;
}

sub _manage {
  my $self = shift;

  if (my @files = @{$self->backend->modified_files}) {
    say @files == 1
      ? qq{File "@{[$files[0]]}" changed, restarting.}
      : qq{@{[scalar @files]} files changed, restarting.}
      unless $self->silent;
    kill 'TERM', $self->{worker} if $self->{worker};
    $self->{modified} = 1;
  }

  if (my $pid = $self->{worker}) {
    delete $self->{worker} if waitpid($pid, WNOHANG) == $pid;
  }

  $self->_spawn if !$self->{worker} && delete $self->{modified};
}

sub _spawn {
  my $self = shift;

  # Manager
  my $manager = $$;
  die "Can't fork: $!" unless defined(my $pid = $self->{worker} = fork);
  return if $pid;

  # Worker
  my $daemon = $self->daemon;
  $daemon->load_app($self->backend->watch->[0])->server($daemon);
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

L<Mojo::Server::Morbo> is a full featured, self-restart capable non-blocking I/O HTTP and WebSocket server, built
around the very well tested and reliable L<Mojo::Server::Daemon>, with IPv6, TLS, SNI, UNIX domain socket, Comet (long
polling), keep-alive and multiple event loop support. Note that the server uses signals for process management, so you
should avoid modifying signal handlers in your applications.

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

=head2 INT, TERM

Shut down server immediately.

=head1 ATTRIBUTES

L<Mojo::Server::Morbo> implements the following attributes.

=head2 backend

  my $backend = $morbo->backend;
  $morbo      = $morbo->backend(Mojo::Server::Morbo::Backend::Poll->new);

Backend, usually a L<Mojo::Server::Morbo::Backend::Poll> object.

=head2 daemon

  my $daemon = $morbo->daemon;
  $morbo     = $morbo->daemon(Mojo::Server::Daemon->new);

L<Mojo::Server::Daemon> object this server manages.

=head2 silent

  my $bool = $morbo->silent;
  $morbo   = $morbo->silent($bool);

Disable console messages, defaults to a true value.

=head1 METHODS

L<Mojo::Server::Morbo> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 run

  $morbo->run('script/my_app');

Run server for application and wait for L</"SIGNALS">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
