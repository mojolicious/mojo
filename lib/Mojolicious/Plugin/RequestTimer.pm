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
    $app->hook(
        before_dispatch => sub {
            shift->stash('mojo.started' => [Time::HiRes::gettimeofday()]);
        }
    );

    # End timer
    $app->hook(
        after_dispatch => sub {
            my $self = shift;
            return unless my $started = $self->stash('mojo.started');
            my $elapsed = sprintf '%f',
              Time::HiRes::tv_interval($started,
                [Time::HiRes::gettimeofday()]);
            my $rps     = $elapsed == 0 ? '??' : sprintf '%.3f', 1 / $elapsed;
            my $res     = $self->res;
            my $code    = $res->code || 200;
            my $message = $res->message || $res->default_message($code);
            $self->app->log->debug("$code $message (${elapsed}s, $rps/s).");
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
timing information.

=head1 METHODS

L<Mojolicious::Plugin::RequestTimer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

Register plugin hooks in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
