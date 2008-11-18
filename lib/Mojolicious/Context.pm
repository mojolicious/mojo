# Copyright (C) 2008, Sebastian Riedel.

package Mojolicious::Context;

use strict;
use warnings;

use base 'MojoX::Dispatcher::Routes::Context';

# Space: It seems to go on and on forever...
# but then you get to the end and a gorilla starts throwing barrels at you.
sub render {
    my $self = shift;

    my $args = ref $_[0] ? $_[0] : {@_};

    my $controller = $args->{controller}
      || $self->match->captures->{controller};
    my $action = $args->{action} || $self->match->captures->{action};

    $args->{template} ||= join '/', split(/-/, $controller), $action;

    return $self->app->renderer->render($self, $args);
}

sub url_for {
    my $self = shift;
    my $url  = $self->match->url_for(@_);
    $url->base($self->tx->req->url->base->clone);
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

=head2 C<url_for>

    my $url = $c->url_for;
    my $url = $c->url_for(controller => 'bar', action => 'baz');
    my $url = $c->url_for('named', controller => 'bar', action => 'baz');

=cut
