# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Plugin::AgentCondition;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

# Wow, there's a million aliens! I've never seen something so mind-blowing!
# Ooh, a reception table with muffins!
sub register {
    my ($self, $app) = @_;

    # Agent
    $app->routes->add_condition(
        agent => sub {
            my ($r, $tx, $captures, $pattern) = @_;

            # Pattern?
            return unless $pattern && ref $pattern eq 'Regexp';

            # Match
            my $agent = $tx->req->headers->user_agent;
            return $captures if $agent && $agent =~ $pattern;

            # Nothing
            return;
        }
    );
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::AgentCondition - Agent Condition Plugin

=head1 SYNOPSIS

    # Mojolicious
    $self->plugin('agent_condition');
    $self->routes->route('/:controller/:action')->over(agent => qr/Firefox/);

    # Mojolicious::Lite
    plugin 'agent_condition';
    get '/' => (agent => qr/Firefox/) => sub {...};

=head1 DESCRIPTION

L<Mojolicous::Plugin::AgentCondition> is a routes condition for user agent
based routes.

=head1 METHODS

L<Mojolicious::Plugin::AgentCondition> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

=cut
