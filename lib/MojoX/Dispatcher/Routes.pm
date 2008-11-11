# Copyright (C) 2008, Sebastian Riedel.

package MojoX::Dispatcher::Routes;

use strict;
use warnings;

use base 'MojoX::Routes';

use Mojo::ByteStream;
use Mojo::Loader;

use constant DEBUG => $ENV{MOJOX_ROUTES_DEBUG} || 0;

__PACKAGE__->attr('controllers', chained => 1, default => sub { {} });
__PACKAGE__->attr('namespace',   chained => 1);

# Hey. What kind of party is this? There's no booze and only one hooker.
sub dispatch {
    my ($self, $c) = @_;

    my $match = $self->match($c->tx);
    $c->match($match);

    # Shortcut
    return 0 unless $match;

    # Walk the stack
    my $stack = $match->stack;
    for my $field (@$stack) {

        my $controller = $field->{controller};
        my $action     = $field->{action};

        my $class = Mojo::ByteStream->new($controller)->camelize;
        $class    = $self->namespace . "::$class";

        # Debug
        warn "-> $controller($class) :: $action\n" if DEBUG;

        # Shortcut
        next unless $class =~ /^[a-zA-Z0-9_:]+$/;

        # Cache
        my $instance = $self->controllers->{$class};

        # Captures
        $c->match->captures($field);

        # Dispatch
        my $done;
        eval {
            $instance = $self->controllers->{$class}
              = Mojo::Loader->load_build($class) unless $instance;

            # Run action
            $done = $instance->$action($c);
        };

        # Error
        if ($@) {
            warn "Dispatch error (propably harmless):\n$@";
            return 0;
        }

        # Break the chain
        last unless $done;
    }

    # No stack, fail
    return 0 unless @$stack;

    # All seems ok
    return 1;
}

1;
__END__

=head1 NAME

MojoX::Dispatcher::Routes - Routes Dispatcher

=head1 SYNOPSIS

    use MojoX::Dispatcher::Routes;

    my $dispatcher = MojoX::Dispatcher::Routes->new;

=head1 DESCRIPTION

L<MojoX::Dispatcher::Routes> is a dispatcher based on L<MojoX::Routes>.

=head2 ATTRIBUTES

L<MojoX::Dispatcher::Routes> inherits all attributes from L<MojoX::Routes>
and implements the follwing the ones.

=head2 C<controllers>

    my $controllers = $dispatcher->controllers;
    $dispatcher     = $dispatcher->controllers({ ... });

=head2 C<namespace>

    my $namespace = $dispatcher->namespace;
    $dispatcher   = $dispatcher->namespace('Foo::Bar::Controller');

=head1 METHODS

L<MojoX::Dispatcher::Routes> inherits all methods from L<MojoX::Routes> and
implements the follwing the ones.

=head2 C<dispatch>

    my $success = $dispatcher->dispatch(
        MojoX::Dispatcher::Routes::Context->new
    );

=cut