package Mojo::Server;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::Loader;
use Scalar::Util 'blessed';

has app => sub {
  my $self = shift;

  # App in environment
  return $ENV{MOJO_APP} if ref $ENV{MOJO_APP};

  # Load
  if (my $e = Mojo::Loader->load($self->app_class)) {
    die $e if ref $e;
  }

  $self->app_class->new;
};
has app_class =>
  sub { ref $ENV{MOJO_APP} || $ENV{MOJO_APP} || 'Mojo::HelloWorld' };
has on_request => sub {
  sub {
    my $app = shift->app;
    my $tx  = shift;
    $app->handler($tx);
  };
};
has on_transaction => sub {
  sub {
    my $self = shift;

    # Reload
    if ($self->reload) {
      if (my $e = Mojo::Loader->reload) { warn $e }
      delete $self->{app};
    }

    $self->app->on_transaction->($self->app);
  };
};
has on_websocket => sub {
  sub {
    my $self = shift;
    $self->app->on_websocket->($self->app, @_)->server_handshake;
  };
};
has reload => sub { $ENV{MOJO_RELOAD} || 0 };

sub load_app {
  my ($self, $file) = @_;
  my $app;
  local $ENV{MOJO_APP_LOADER} = 1;
  unless ($app = do $file) {
    die qq/Can't load application "$file": $@/ if $@;
    die qq/Can't load application "$file": $!/ unless defined $app;
    die qq/Can't load application' "$file".\n/ unless $app;
  }
  die qq/"$file" is not a valid application.\n/
    unless blessed $app && $app->isa('Mojo');
  $self->app($app);
}

# "Are you saying you're never going to eat any animal again? What about
#  bacon?
#  No.
#  Ham?
#  No.
#  Pork chops?
#  Dad, those all come from the same animal.
#  Heh heh heh. Ooh, yeah, right, Lisa. A wonderful, magical animal."
sub run { croak 'Method "run" not implemented by subclass' }

1;
__END__

=head1 NAME

Mojo::Server - HTTP Server Base Class

=head1 SYNOPSIS

  use Mojo::Base 'Mojo::Server';

  sub run {
    my $self = shift;

    # Get a transaction
    my $tx = $self->on_transaction->($self);

    # Call the handler
    $tx = $self->on_request->($self);
  }

=head1 DESCRIPTION

L<Mojo::Server> is an abstract HTTP server base class.

=head1 ATTRIBUTES

L<Mojo::Server> implements the following attributes.

=head2 C<app>

  my $app = $server->app;
  $server = $server->app(MojoSubclass->new);

Application this server handles, defaults to a L<Mojo::HelloWorld> object.

=head2 C<app_class>

  my $app_class = $server->app_class;
  $server       = $server->app_class('MojoSubclass');

Class of the application this server handles, defaults to
L<Mojo::HelloWorld>.

=head2 C<on_request>

  my $handler = $server->on_request;
  $server     = $server->on_request(sub {
    my ($self, $tx) = @_;
  });

Request callback.

=head2 C<on_transaction>

  my $btx = $server->on_transaction;
  $server = $server->on_transaction(sub {
    my $self = shift;
    return Mojo::Transaction::HTTP->new;
  });

Transaction builder callback.

=head2 C<on_websocket>

  my $handshake = $server->on_websocket;
  $server       = $server->on_websocket(sub {
    my ($self, $tx) = @_;
  });

WebSocket handshake callback.

=head2 C<reload>

  my $reload = $server->reload;
  $server    = $server->reload(1);

Activate automatic reloading.

=head1 METHODS

L<Mojo::Server> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<load_app>

  $server->load_app('./myapp.pl');

Load application from script.
Note that this method is EXPERIMENTAL and might change without warning!

  print Mojo::Server->new->load_app('./myapp.pl')->app->home;

=head2 C<run>

  $server->run;

Start server.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
