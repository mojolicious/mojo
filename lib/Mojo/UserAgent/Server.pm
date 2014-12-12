package Mojo::UserAgent::Server;
use Mojo::Base -base;

use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Scalar::Util 'weaken';

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

sub nb_url { shift->_url(1, @_) }

sub restart { shift->_restart(1) }

sub url { shift->_url(0, @_) }

sub _restart {
  my ($self, $full, $proto) = @_;
  delete @{$self}{qw(nb_port port)} if $full;

  $self->{proto} = $proto ||= 'http';

  # Blocking
  my $server = $self->{server}
    = Mojo::Server::Daemon->new(ioloop => $self->ioloop, silent => 1);
  weaken $server->app($self->app)->{app};
  my $port = $self->{port} ? ":$self->{port}" : '';
  $self->{port} = $server->listen(["$proto://127.0.0.1$port"])
    ->start->ioloop->acceptor($server->acceptors->[0])->port;

  # Non-blocking
  $server = $self->{nb_server} = Mojo::Server::Daemon->new(silent => 1);
  weaken $server->app($self->app)->{app};
  $port = $self->{nb_port} ? ":$self->{nb_port}" : '';
  $self->{nb_port} = $server->listen(["$proto://127.0.0.1$port"])
    ->start->ioloop->acceptor($server->acceptors->[0])->port;
}

sub _url {
  my ($self, $nb) = (shift, shift);
  $self->_restart(0, @_) if !$self->{server} || @_;
  my $port = $nb ? $self->{nb_port} : $self->{port};
  return Mojo::URL->new("$self->{proto}://127.0.0.1:$port/");
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
            Mojo::UserAgent::Server->app(Mojolicious->new);
  my $app = $server->app;
  $server = $server->app(Mojolicious->new);

Application this server handles, instance specific applications override the
global default.

  # Change application behavior
  $server->app->defaults(testing => 'oh yea!');

=head2 nb_url

  my $url = $ua->nb_url;
  my $url = $ua->nb_url('http');
  my $url = $ua->nb_url('https');

Get absolute L<Mojo::URL> object for server processing non-blocking requests
with L</"app"> and switch protocol if necessary.

=head2 restart

  $server->restart;

Restart server with new port.

=head2 url

  my $url = $ua->url;
  my $url = $ua->url('http');
  my $url = $ua->url('https');

Get absolute L<Mojo::URL> object for server processing blocking requests with
L</"app"> and switch protocol if necessary.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
