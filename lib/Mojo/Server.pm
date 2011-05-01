package Mojo::Server;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::Loader;

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

    # Handle transaction
    $app->handler($tx);

    # Delayed
    $app->log->debug(
      'Waiting for delayed response, forgot to render or resume?')
      unless $tx->is_writing;
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

# DEPRECATED in Smiling Cat Face With Heart-Shaped Eyes!
sub on_build_tx {
  warn <<EOF;
Mojo::Server->on_build_tx is DEPRECATED in favor of
Mojo::Server->on_transaction!!!
EOF
  shift->on_transaction(@_);
}

# DEPRECATED in Smiling Cat Face With Heart-Shaped Eyes!
sub on_handler {
  warn <<EOF;
Mojo::Server->on_handler is DEPRECATED in favor of
Mojo::Server->on_request!!!
EOF
  shift->on_request(@_);
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

=head2 C<run>

  $server->run;

Start server.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
