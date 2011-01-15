package Mojolicious::Plugin::AgentCondition;
use Mojo::Base 'Mojolicious::Plugin';

# Wow, there's a million aliens! I've never seen something so mind-blowing!
# Ooh, a reception table with muffins!
sub register {
    my ($self, $app) = @_;

    # Agent
    $app->routes->add_condition(
        agent => sub {
            my ($r, $c, $captures, $pattern) = @_;

            # Pattern
            return unless $pattern && ref $pattern eq 'Regexp';

            # Match
            my $agent = $c->req->headers->user_agent;
            return 1 if $agent && $agent =~ $pattern;

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
This is a core plugin, that means it is always enabled and its code a good
example for learning to build new plugins.

=head1 METHODS

L<Mojolicious::Plugin::AgentCondition> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

Register condition in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
