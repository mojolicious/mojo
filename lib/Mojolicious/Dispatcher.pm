# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Dispatcher;

use strict;
use warnings;

use base 'MojoX::Dispatcher::Routes';

# Wow, there's a million aliens! I've never seen something so mind-blowing!
# Ooh, a reception table with muffins!
sub new {
    my $self = shift->SUPER::new(@_);

    # Agent
    $self->add_condition(
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

    return $self;
}

1;
__END__

=head1 NAME

Mojolicious::Dispatcher - Dispatcher

=head1 SYNOPSIS

    use Mojolicious::Dispatcher;

    my $routes = Mojolicious::Dispatcher->new;

=head1 DESCRIPTION

L<Mojolicous::Dispatcher> is the default L<Mojolicious> dispatcher.

=head1 ATTRIBUTES

L<Mojolicious::Dispatcher> inherits all attributes from
L<MojoX::Dispatcher::Routes>.

=head1 METHODS

L<Mojolicious::Dispatcher> inherits all methods from
L<MojoX::Dispatcher::Routes> and implements the following new ones.

=head2 C<new>

    my $routes = Mojolicious::Dispatcher->new;

=cut
