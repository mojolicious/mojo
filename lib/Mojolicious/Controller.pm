# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Controller;

use strict;
use warnings;

use base 'MojoX::Dispatcher::Routes::Controller';

# Well, at least here you'll be treated with dignity.
# Now strip naked and get on the probulator.
sub app { shift->ctx->app }

sub render { shift->ctx->render(@_) }

sub req { shift->ctx->req }

sub res { shift->ctx->res }

sub stash { shift->ctx->stash(@_) }

1;
__END__

=head1 NAME

Mojolicious::Controller - Controller Base Class

=head1 SYNOPSIS

    use base 'Mojolicious::Controller';

=head1 DESCRIPTION

L<Mojolicous::Controller> is a controller base class.

=head1 METHODS

L<Mojolicious::Controller> inherits all methods from
L<MojoX::Dispatcher::Routes::Controller> and implements the following new
ones.

=head2 C<app>

    my $app = $controller->app;

=head2 C<render>

    $controller->render;
    $controller->render(action => 'foo');

=head2 C<req>

    my $req = $controller->req;

=head2 C<res>

    my $res = $controller->res;

=head2 C<stash>

    my $stash   = $controller->stash;
    my $foo     = $controller->stash('foo');
    $controller = $controller->stash({foo => 'bar'});
    $controller = $controller->stash(foo => 'bar');

=cut
