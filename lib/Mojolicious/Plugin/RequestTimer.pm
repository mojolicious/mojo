# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Plugin::RequestTimer;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Time::HiRes ();

# I don't trust that doctor.
# I bet I've lost more patients than he's even treated.
sub register {
    my ($self, $app) = @_;

    # Start timer
    $app->plugins->add_hook(
        before_dispatch => sub {
            my ($self, $c) = @_;
            $c->stash(started => [Time::HiRes::gettimeofday()]);
        }
    );

    # End timer
    $app->plugins->add_hook(
        after_dispatch => sub {
            my ($self, $c) = @_;
            return unless my $started = $c->stash('started');
            my $elapsed = sprintf '%f',
              Time::HiRes::tv_interval($started,
                [Time::HiRes::gettimeofday()]);
            my $rps = $elapsed == 0 ? '??' : sprintf '%.3f', 1 / $elapsed;
            $c->app->log->debug("Request took $elapsed seconds ($rps/s).");
        }
    );
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::RequestTimer - Request Timer Plugin

=head1 SYNOPSIS

    # Mojolicious
    $self->plugin('request_timer');

    # Mojolicious::Lite
    plugin 'request_timer';

=head1 DESCRIPTION

L<Mojolicous::Plugin::RequestTimer> is a plugin to gather and log request
timing informations.

=head1 METHODS

L<Mojolicious::Plugin::RequestTimer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

=cut
