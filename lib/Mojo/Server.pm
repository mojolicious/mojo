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
    build_tx_cb => sub {
        sub {
            my $self = shift;

            # Reload
            if (my $reload = $self->reload) {
                local $ENV{MOJO_RELOAD} = $reload;
                if (my $e = Mojo::Loader->reload) { warn $e }
                delete $self->{app};
            }

            return $self->app->build_tx_cb->($self->app);
          }
    }
);
__PACKAGE__->attr(
    handler_cb => sub {
        sub { shift->app->handler(shift) }
    }
);
__PACKAGE__->attr(reload => sub { $ENV{MOJO_RELOAD} || 0 });
__PACKAGE__->attr(
    websocket_handshake_cb => sub {
        sub {
            my $self = shift;
            return $self->app->websocket_handshake_cb->($self->app, @_);
          }
    }
);

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
        my $tx = $self->build_tx_cb->($self);

        # Call the handler
        $tx = $self->handler_cb->($self);
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

=head2 C<build_tx_cb>

    my $btx = $server->build_tx_cb;
    $server = $server->build_tx_cb(sub {
        my $self = shift;
        return Mojo::Transaction::HTTP->new;
    });

Transaction builder callback.

=head2 C<handler_cb>

    my $handler = $server->handler_cb;
    $server     = $server->handler_cb(sub {
        my ($self, $tx) = @_;
    });

Handler callback.

=head2 C<reload>

    my $reload = $server->reload;
    $server    = $server->reload(1);

Activate automatic reloading.

=head2 C<websocket_handshake_cb>

    my $handshake = $server->websocket_handshake_cb;
    $server       = $server->websocket_handshake_cb(sub {
        my ($self, $tx) = @_;
    });

WebSocket handshake callback.

=head1 METHODS

L<Mojo::Server> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<run>

    $server->run;

Start server.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
