# Copyright (C) 2008-2009, Sebastian Riedel.

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

    # Only log errors
    $self->log->level('error');

    # Template root
    $self->renderer->root($self->home->rel_dir('t/mojolicious/templates'));

    # Templateless renderer
    $self->renderer->add_handler(
        test => sub {
            my ($self, $c, $output) = @_;
            $$output = 'Hello Mojo from a templateless renderer!';
        }
    );

    # Renderer for a different file extension
    $self->renderer->add_handler(xpl => $self->renderer->handler->{epl});

    # Default handler
    $self->renderer->default_handler('epl');

    # Routes
    my $r = $self->routes;

    # /test3 - no class, just a namespace
    $r->route('/test3')
      ->to(namespace => 'MojoliciousTestController', method => 'index');

    # /test2 - different namespace test
    $r->route('/test2')->to(
        namespace => 'MojoliciousTest2',
        class     => 'Foo',
        method    => 'test'
    );

    # /*/* - the default route
    $r->route('/:controller/:action')->to(action => 'index');
}

1;
