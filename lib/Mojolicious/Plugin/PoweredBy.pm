# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Plugin::PoweredBy;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

# It's just like the story of the grasshopper and the octopus.
# All year long, the grasshopper kept burying acorns for the winter,
# while the octopus mooched off his girlfriend and watched TV.
# But then the winter came, and the grasshopper died,
# and the octopus ate all his acorns.
# And also he got a racecar. Is any of this getting through to you?
sub register {
    my ($self, $app, $args) = @_;

    # Name
    my $name = $args->{name} || 'Mojolicious (Perl)';

    # Add header
    $app->plugins->add_hook(
        after_build_tx => sub {
            my ($self, $tx) = @_;
            $tx->res->headers->header('X-Powered-By' => $name);
        }
    );
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::PoweredBy - Powered By Plugin

=head1 SYNOPSIS

    # Mojolicious
    $self->plugin('powered_by');
    $self->plugin(powered_by => (name => 'MyApp 1.0'));

    # Mojolicious::Lite
    plugin 'powered_by';
    plugin powered_by => (name => 'MyApp 1.0');

=head1 DESCRIPTION

L<Mojolicous::Plugin::PoweredBy> is a plugin that adds an C<X-Powered-By>
header which defaults to C<Mojolicious (Perl)>.

=head1 METHODS

L<Mojolicious::Plugin::PoweredBy> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

=cut
