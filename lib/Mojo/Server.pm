# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Server;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp;
use Mojo::Loader;

use constant RELOAD => $ENV{MOJO_RELOAD} || 0;

__PACKAGE__->attr('build_transaction_callback',
    chained => 1,
    default => sub {
        return sub {
            my $self = shift;

            # Reload
            if (RELOAD) {
                Mojo::Loader->reload;
                $self->_new_mojo_app;
            }
            return $self->{_mojo_app}->build_tx;
        }
    }
);
__PACKAGE__->attr('continue_handler_callback',
    chained => 1,
    default => sub {
        return sub {
            my ($self, $tx) = @_;
            $tx->res->code(100);
            return $tx;
        };
    }
);
__PACKAGE__->attr('handler_callback',
    chained => 1,
    default => sub {
        return sub {
            my ($self, $tx) = @_;
            $self->{_mojo_app}->handler($tx);
            return $tx;
        };
    }
);

*build_tx_cb         = \&build_transaction_callback;
*continue_handler_cb = \&continue_handler_callback;
*handler_cb          = \&handler_callback;

sub new {
    my $self = shift->SUPER::new();
    $self->_new_mojo_app;
    return $self;
}

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

sub _new_mojo_app {
    $ENV{MOJO_APP} ||= 'Mojo::HelloWorld';
    shift->{_mojo_app} = Mojo::Loader->load_build($ENV{MOJO_APP});
}

1;
__END__

=head1 NAME

Mojo::Server - Server Base Class

=head1 SYNOPSIS

    use base 'Mojo::Server';

=head1 DESCRIPTION

L<Mojo::Server> is a server base class.

=head1 ATTRIBUTES

=head2 C<build_tx_cb>

=head2 C<build_transaction_callback>

    my $btx = $server->build_tx_cb;
    $server = $server->build_tx_cb(sub {
        my $self = shift;
        return Mojo::Transaction->new;
    });
    my $btx = $server->build_transaction_callback;
    $server = $server->build_transaction_callback(sub {
        my $self = shift;
        return Mojo::Transaction->new;
    });

=head2 C<continue_handler_cb>

=head2 C<continue_handler_callback>

    my $handler = $server->continue_handler_cb;
    $server     = $server->continue_handler_cb(sub {
        my ($self, $tx) = @_;
        return $tx;
    });
    my $handler = $server->continue_handler_callback;
    $server     = $server->continue_handler_callback(sub {
        my ($self, $tx) = @_;
        return $tx;
    });

=head2 C<handler_cb>

=head2 C<handler_callback>

    my $handler = $server->handler_cb;
    $server     = $server->handler_cb(sub {
        my ($self, $tx) = @_;
        return $tx;
    });
    my $handler = $server->handler_callback;
    $server     = $server->handler_callback(sub {
        my ($self, $tx) = @_;
        return $tx;
    });

=head1 METHODS

L<Mojo::Server> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $server = Mojo::Server->new;

=head2 C<log>

    $server->log('Test 123');

=head2 C<run>

    $server->run;

=cut