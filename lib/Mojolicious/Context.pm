# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Context;

use strict;
use warnings;

use base 'MojoX::Dispatcher::Routes::Context';

use MojoX::Routes::Match;

# Space: It seems to go on and on forever...
# but then you get to the end and a gorilla starts throwing barrels at you.
sub render {
    my $self = shift;

    # Merge args with stash
    my $args = ref $_[0] ? $_[0] : {@_};
    $self->{stash} = {%{$self->stash}, %$args};

    # Template
    unless ($self->stash->{template} || $self->stash->{template_path}) {

        # Default template
        my $controller = $self->stash->{controller};
        my $action     = $self->stash->{action};

        # Nothing to render
        return undef unless $controller && $action;

        $self->stash->{template} = join '/', split(/-/, $controller), $action;
    }

    # Format
    $self->stash->{format} ||= 'html';

    # Render
    return $self->app->renderer->render($self);
}

sub render_inner {
    my $self = shift;
    local $self->stash->{template}      = $self->stash->{inner_template};
    local $self->stash->{template_path} = $self->stash->{inner_template_path};
    return $self->render_partial(@_);
}

sub render_partial {
    my $self = shift;
    local $self->stash->{partial} = 1;
    return $self->render(@_);
}

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

Mojolicious::Context - Context

=head1 SYNOPSIS

    use Mojolicious::Context;

    my $c = Mojolicious::Context->new;

=head1 DESCRIPTION

L<Mojolicous::Context> is a context container.

=head1 ATTRIBUTES

L<Mojolicious::Context> inherits all attributes from
L<MojoX::Dispatcher::Routes::Context>.

=head1 METHODS

L<Mojolicious::Context> inherits all methods from
L<MojoX::Dispatcher::Routes::Context> and implements the following new ones.

=head2 C<render>

    $c->render;
    $c->render(action => 'foo');

=head2 C<render_inner>

    $c->render_inner;
    $c->render_inner(action => 'foo');

=head2 C<render_partial>

    $c->render_partial;
    $c->render_partial(action => 'foo');

=head2 C<url_for>

    my $url = $c->url_for;
    my $url = $c->url_for(controller => 'bar', action => 'baz');
    my $url = $c->url_for('named', controller => 'bar', action => 'baz');

=cut
