# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Server;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp;
use Mojo::Loader;

use constant RELOAD => $ENV{MOJO_RELOAD} || 0;

__PACKAGE__->attr(
    app => (
        default => sub {
            my $e = Mojo::Loader->load_build(shift->app_class);
            die $e if ref $e eq 'Mojo::Loader::Exception';
            return $e;
        }
    )
);
__PACKAGE__->attr(
    app_class => (default => sub { $ENV{MOJO_APP} ||= 'Mojo::HelloWorld' }));
__PACKAGE__->attr(
    build_tx_cb => (
        default => sub {
            return sub {
                my $self = shift;

                # Reload
                if (RELOAD) {
                    my $e = Mojo::Loader->reload;
                    warn $e if $e;
                    delete $self->{app};
                }

                return $self->app->build_tx;
              }
        }
    )
);
__PACKAGE__->attr(
    continue_handler_cb => (
        default => sub {
            return sub {
                my ($self, $tx) = @_;
                if ($self->app->can('continue_handler')) {
                    $self->app->continue_handler($tx);
                }
                else { $tx->res->code(100) }
                return $tx;
            };
        }
    )
);
__PACKAGE__->attr(
    handler_cb => (
        default => sub {
            return sub {
                my ($self, $tx) = @_;
                $self->app->handler($tx);
                return $tx;
            };
        }
    )
);

# It's up to the subclass to decide where log messages go
sub log {
    my ($self, $msg) = @_;
    my $time = localtime(time);
    warn "[$time] [$$] $msg\n";
}

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

L<Mojo::Server> is a HTTP server base class.
Subclasses should implement their own C<run> method.

The usual request cycle is like this.

    1. Build a new Mojo::Transaction objct with ->build_tx_cb
    2. Read request information from client
    3. Put request information into the transaction object
    4. Call ->handler_cb to build a response
    5. Get response information from the transaction object
    6. Write response information to client

=head1 ATTRIBUTES

=head2 C<app>

    my $app = $server->app;
    $server = $server->app(MojoSubclass->new);

Returns the instantiated Mojo application to serve.
Overrides C<app_class> if defined.

=head2 C<app_class>

    my $app_class = $server->app_class;
    $server       = $server->app_class('MojoSubclass');

Returns the class name of the Mojo application to serve.
Defaults to C<$ENV{MOJO_APP}> and falls back to C<Mojo::HelloWorld>.

=head2 C<build_tx_cb>

    my $btx = $server->build_tx_cb;
    $server = $server->build_tx_cb(sub {
        my $self = shift;
        return Mojo::Transaction->new;
    });

=head2 C<continue_handler_cb>

    my $handler = $server->continue_handler_cb;
    $server     = $server->continue_handler_cb(sub {
        my ($self, $tx) = @_;
        return $tx;
    });

=head2 C<handler_cb>

    my $handler = $server->handler_cb;
    $server     = $server->handler_cb(sub {
        my ($self, $tx) = @_;
        return $tx;
    });

=head1 METHODS

L<Mojo::Server> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<log>

    $server->log('Test 123');

=head2 C<run>

    $server->run;

=head1 BUNDLED SERVERS

L<Mojo::Server::CGI> - Serves a single CGI request.

L<Mojo::Server::Daemon> - Portable standalone HTTP server.

L<Mojo::Server::Daemon::Prefork> - Preforking standalone HTTP server.

L<Mojo::Server::FastCGI> - A FastCGI server.

=cut
