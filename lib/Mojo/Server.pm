package Mojo::Server;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';
use Mojo::Loader;

__PACKAGE__->attr(
    app => sub {
        my $self = shift;

        # App in environment
        return $ENV{MOJO_APP} if ref $ENV{MOJO_APP};

        # Load
        if (my $e = Mojo::Loader->load($self->app_class)) {
            die $e if ref $e;
        }

        return $self->app_class->new;
    }
);
__PACKAGE__->attr(app_class =>
      sub { ref $ENV{MOJO_APP} || $ENV{MOJO_APP} || 'Mojo::HelloWorld' });
__PACKAGE__->attr(
    on_build_tx => sub {
        sub {
            my $self = shift;

            # Reload
            if ($self->reload) {
                if (my $e = Mojo::Loader->reload) { warn $e }
                delete $self->{app};
            }

            return $self->app->on_build_tx->($self->app);
          }
    }
);
__PACKAGE__->attr(
    on_handler => sub {
        sub {

            # Application
            my $app = shift->app;

            # Transaction
            my $tx = shift;

            # Handler
            $app->handler($tx);

            # Delayed
            $app->log->debug(
                'Waiting for delayed response, forgot to render or resume?')
              unless $tx->is_writing;
          }
    }
);
__PACKAGE__->attr(
    on_websocket_handshake => sub {
        sub {
            my $self = shift;
            return $self->app->on_websocket_handshake->($self->app, @_);
          }
    }
);
__PACKAGE__->attr(reload => sub { $ENV{MOJO_RELOAD} || 0 });

# DEPRECATED in Comet!
*build_tx_cb            = \&on_build_tx;
*handler_cb             = \&on_handler;
*websocket_handshake_cb = \&on_websocket_handshake;

# Are you saying you're never going to eat any animal again? What about bacon?
# No.
# Ham?
# No.
# Pork chops?
# Dad, those all come from the same animal.
# Heh heh heh. Ooh, yeah, right, Lisa. A wonderful, magical animal.
sub run { croak 'Method "run" not implemented by subclass' }

1;
__END__

=head1 NAME

Mojo::Server - HTTP Server Base Class

=head1 SYNOPSIS

    use base 'Mojo::Server';

    sub run {
        my $self = shift;

        # Get a transaction
        my $tx = $self->on_build_tx->($self);

        # Call the handler
        $tx = $self->on_handler->($self);
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

=head2 C<on_build_tx>

    my $btx = $server->on_build_tx;
    $server = $server->on_build_tx(sub {
        my $self = shift;
        return Mojo::Transaction::HTTP->new;
    });

Transaction builder callback.

=head2 C<on_handler>

    my $handler = $server->on_handler;
    $server     = $server->on_handler(sub {
        my ($self, $tx) = @_;
    });

Handler callback.

=head2 C<on_websocket_handshake>

    my $handshake = $server->on_websocket_handshake;
    $server       = $server->on_websocket_handshake(sub {
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

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
