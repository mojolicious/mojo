package Mojo::UserAgent::Server;
use Mojo::Base -base;

use Mojo::IOLoop;
use Mojo::Server::Daemon;

has ioloop => sub { Mojo::IOLoop->singleton };

sub app {
  my ($self, $app) = @_;

  # Singleton application
  state $singleton;
  return $singleton = $app ? $app : $singleton unless ref $self;

  # Default to singleton application
  return $self->{app} || $singleton unless $app;
  $self->{app} = $app;
  return $self;
}

sub restart {
  my $self = shift;
  delete $self->{port};
  $self->_restart;
}

sub url {
  my $self = shift;
  $self->_restart(@_)
    if !$self->{server} || $self->{server}->ioloop ne $self->ioloop || @_;
  return Mojo::URL->new("$self->{proto}://localhost:$self->{port}/");
}

sub _restart {
  my ($self, $proto) = @_;

  my $server = $self->{server} = Mojo::Server::Daemon->new(
    app    => $self->app,
    ioloop => $self->ioloop,
    silent => 1
  );
  die "Couldn't find a free TCP port for application.\n"
    unless my $port = $self->{port} ||= Mojo::IOLoop->generate_port;
  $self->{proto} = $proto ||= 'http';
  $server->listen(["$proto://127.0.0.1:$port"])->start;
}

1;

=encoding utf8

=head1 NAME

Mojo::UserAgent::Server - Application server

=head1 SYNOPSIS

  use Mojo::UserAgent::Server;

  my $server = Mojo::UserAgent::Server->new;
  say $server->url;

=head1 DESCRIPTION

L<Mojo::UserAgent::Server> is an embedded web server based on
L<Mojo::Server::Daemon> that processes requests for L<Mojo::UserAgent>.

=head1 ATTRIBUTES

L<Mojo::UserAgent::Server> implements the following attributes.

=head2 ioloop

  my $loop = $server->ioloop;
  $server  = $server->ioloop(Mojo::IOLoop->new);

Event loop object to use for I/O operations, defaults to the global
L<Mojo::IOLoop> singleton.

=head1 METHODS

L<Mojo::UserAgent::Server> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 app

  my $app = Mojo::UserAgent::Server->app;
            Mojo::UserAgent::Server->app(MyApp->new);
  my $app = $server->app;
  $server = $server->app(MyApp->new);

Application this server handles, instance specific applications override the
global default.

  # Change application behavior
  $server->defaults(testing => 'oh yea!');

=head2 restart

  $server->restart;

Restart server with new port.

=head2 url

  my $url = $ua->url;
  my $url = $ua->url('http');
  my $url = $ua->url('https');

Get absolute L<Mojo::URL> object for C<app> and switch protocol if necessary.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
