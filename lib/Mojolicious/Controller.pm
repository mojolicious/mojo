# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Controller;

use strict;
use warnings;

use base 'MojoX::Dispatcher::Routes::Controller';

# Space: It seems to go on and on forever...
# but then you get to the end and a gorilla starts throwing barrels at you.
sub render {
    my $self = shift;

    # Merge args with stash
    my $args = ref $_[0] ? $_[0] : {@_};
    $self->{stash} = {%{$self->stash}, %$args};

    # Template
    unless ($self->stash->{template}) {

        # Default template
        my $controller = $self->stash->{controller};
        my $action     = $self->stash->{action};

        # Try the route name if we don't have controller and action
        unless ($controller && $action) {
            my $endpoint = $self->match->endpoint;

            # Use endpoint name as default template
            $self->stash(template => $endpoint->name)
              if $endpoint && $endpoint->name;
        }

        # Normal default template
        else {
            $self->stash(
                template => join('/', split(/-/, $controller), $action));
        }
    }

    # Format
    $self->stash->{format} ||= 'html';

    # Render
    return $self->app->renderer->render($self);
}

# Wow, there's a million aliens! I've never seen something so mind-blowing!
# Ooh, a reception table with muffins!
sub render_inner { delete shift->stash->{inner_template} }

# I'm finally richer than those snooty ATM machines.
sub render_partial {
    my $self = shift;
    local $self->stash->{partial} = 1;
    return $self->render(@_);
}

# It would never work out, Fry. You're a male, I'm a female.
# We're just too different.
sub url_for {
    my $self = shift;

    # Make sure we have a match for named routes
    $self->match(MojoX::Routes::Match->new->endpoint($self->app->routes))
      unless $self->match;

    # Use match or root
    my $url = $self->match->url_for(@_);

    # Base
    $url->base($self->tx->req->url->base->clone);

    # Fix paths
    unshift @{$url->path->parts}, @{$url->base->path->parts};
    $url->base->path->parts([]);

    return $url;
}

1;
__END__

=head1 NAME

Mojolicious::Controller - Controller Base Class

=head1 SYNOPSIS

    use base 'Mojolicious::Controller';

=head1 DESCRIPTION

L<Mojolicous::Controller> is a controller base class.

=head1 ATTRIBUTES

L<Mojolicious::Controller> inherits all attributes from
L<MojoX::Dispatcher::Routes::Controller>.

=head1 METHODS

L<Mojolicious::Controller> inherits all methods from
L<MojoX::Dispatcher::Routes::Controller> and implements the following new
ones.

=head2 C<render>

    $c->render;
    $c->render(controller => 'foo', action => 'bar');
    $c->render(text => 'Hello!');
    $c->render(template => 'index');
    $c->render(template => 'foo/index');
    $c->render(template => 'index', format => 'html', handler => 'epl');
    $c->render(handler => 'something');

=head2 C<render_inner>

    my $output = $c->render_inner;

=head2 C<render_partial>

    my $output = $c->render_partial;
    my $output = $c->render_partial(action => 'foo');

=head2 C<url_for>

    my $url = $c->url_for;
    my $url = $c->url_for(controller => 'bar', action => 'baz');
    my $url = $c->url_for('named', controller => 'bar', action => 'baz');

=cut
