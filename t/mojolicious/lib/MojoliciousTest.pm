# Copyright (C) 2008, Sebastian Riedel.

package MojoliciousTest;

use strict;
use warnings;

use base 'Mojolicious';

sub development_mode {
    my $self = shift;

    # Static root for development
    $self->static->root($self->home->rel_dir('t/mojolicious/public_dev'));
}

sub production_mode {
    my $self = shift;

    # Static root for production
    $self->static->root($self->home->rel_dir('t/mojolicious/public'));
}

# Let's face it, comedy's a dead art form. Tragedy, now that's funny.
sub startup {
    my $self = shift;

    # Template root
    $self->renderer->root($self->home->rel_dir('t/mojolicious/templates'));

    # Routes
    my $r = $self->routes;

    # /*/* - the default route
    $r->route('/:controller/:action')->to(action => 'index');
}

1;
