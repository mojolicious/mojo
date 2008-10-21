# Copyright (C) 2008, Sebastian Riedel.

package Mojolicious;

use strict;
use warnings;

use base 'Mojo';

use Mojo::Home;
use Mojolicious::Context;
use Mojolicious::Dispatcher;
use Mojolicious::Renderer;
use MojoX::Dispatcher::Static;
use MojoX::Types;

__PACKAGE__->attr('home', chained => 1, default => sub { Mojo::Home->new });
__PACKAGE__->attr('renderer',
    chained => 1,
    default => sub { Mojolicious::Renderer->new }
);
__PACKAGE__->attr('routes',
    chained => 1,
    default => sub { Mojolicious::Dispatcher->new }
);
__PACKAGE__->attr('static',
    chained => 1,
    default => sub { MojoX::Dispatcher::Static->new }
);
__PACKAGE__->attr('types',
    chained => 1,
    default => sub { MojoX::Types->new }
);

*build_ctx = \&build_context;

# The usual constructor stuff
sub new {
    my $self = shift->SUPER::new();

    # Namespace
    $self->routes->namespace(ref $self);

    # Types
    $self->renderer->types($self->types);
    $self->static->types($self->types);

    # Root
    $self->home->detect(ref $self);
    $self->renderer->root($self->home->relative_directory('templates'));
    $self->static->root($self->home->relative_directory('public'));

    # Startup
    $self->startup(@_);

    return $self;
}

sub build_context {
    return Mojolicious::Context->new(
        mojolicious => shift,
        transaction => shift
    );
}

# You could just overload this method
sub dispatch {
    my ($self, $c) = @_;

    # Try to find a static file
    $self->static->dispatch($c) unless $c->res->code;

    # Use routes if we don't have a response code yet
    $self->routes->dispatch($c) unless $c->res->code;
}

# Bite my shiny metal ass!
sub handler {
    my ($self, $tx) = @_;

    # Build context and dispatch
    $self->dispatch($self->build_ctx($tx));

    return $tx;
}

# This will run once at startup
sub startup {}

1;
__END__

=head1 NAME

Mojolicious - Web Framework

=head1 SYNOPSIS

    use base 'Mojolicious';

    sub startup {
        my $self = shift;

        my $r = $self->routes;

        $r->route('/:controller/:action')
          ->to(controller => 'foo', action => 'bar');
    }

=head1 DESCRIPTION

L<Mojolicous> is a web framework built upon L<Mojo>.

=head1 ATTRIBUTES

L<Mojolicious> inherits all attributes from L<Mojo> and implements the
following new ones.

=head2 C<home>

    my $home = $mojo->home;
    $mojo    = $mojo->home(Mojo::Home->new);

=head2 C<renderer>

    my $renderer = $mojo->renderer;
    $mojo        = $mojo->renderer(Mojolicious::Renderer->new);

=head2 C<routes>

    my $routes = $mojo->routes;
    $mojo      = $mojo->routes(Mojolicious::Dispatcher->new);

=head2 C<static>

    my $static = $mojo->static;
    $mojo      = $mojo->static(MojoX::Dispatcher::Static->new);

=head2 C<types>

    my $types = $mojo->types;
    $mojo     = $mojo->types(MojoX::Types->new)

=head1 METHODS

L<Mojolicious> inherits all methods from L<Mojo> and implements the following
new ones.

=head2 C<new>

    my $mojo = Mojolicious->new;

=head2 C<build_ctx>

=head2 C<build_context>

    my $c = $mojo->build_ctx($tx);
    my $c = $mojo->build_context($tx);

=head2 C<dispatch>

    $mojo->dispatch($c);

=head2 C<handler>

    $tx = $mojo->handler($tx);

=head2 C<startup>

    $mojo->startup($tx);

=cut