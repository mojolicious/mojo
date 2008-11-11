# Copyright (C) 2008, Sebastian Riedel.

package Mojolicious;

use strict;
use warnings;

use base 'Mojo';

use Mojo::Loader;
use Mojolicious::Dispatcher;
use Mojolicious::Renderer;
use MojoX::Dispatcher::Static;
use MojoX::Types;

__PACKAGE__->attr('ctx_class',
    chained => 1,
    default => 'Mojolicious::Context'
);
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
__PACKAGE__->attr('environment',
    chained => 1,
    default => sub { ($ENV{MOJO_ENV} || 'development') }
);

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
    $self->renderer->root($self->home->rel_dir('templates'));
    $self->static->root($self->home->rel_dir('public'));

    # Startup
    $self->startup(@_);

    # Environment
    my $env = $self->environment . "_env";
    $self->$env if $self->can($env);

    # Load context class
    Mojo::Loader->new->load($self->ctx_class);

    return $self;
}

sub build_ctx {
    my $self = shift;
    return $self->ctx_class->new(app => $self, tx => shift);
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

See L<Mojo::Manual::Mojolicious> for user friendly documentation.

=head1 ATTRIBUTES

L<Mojolicious> inherits all attributes from L<Mojo> and implements the
following new ones.

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

=head2 C<environment>

Defaults to ENV{MOJO_ENV} or 'development'.

    my $env = $mojo->environment;
    if ($env =~ m/^dev/) {
        do_debug_output();
     }

=head1 METHODS

L<Mojolicious> inherits all methods from L<Mojo> and implements the following
new ones.

=head2 C<new>

    my $mojo = Mojolicious->new;

This method will call the method called C<${environment}_env>, if it
exists.  (C<$environment> being the value of that attribute).  For
example in production mode, C<production_env> will be called.

=head2 C<build_ctx>

    my $c = $mojo->build_ctx($tx);

=head2 C<dispatch>

    $mojo->dispatch($c);

=head2 C<handler>

    $tx = $mojo->handler($tx);

=head2 C<startup>

    $mojo->startup($tx);

=cut
