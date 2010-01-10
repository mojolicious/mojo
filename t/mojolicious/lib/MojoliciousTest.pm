# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoliciousTest;

use strict;
use warnings;

use base 'Mojolicious';

sub development_mode {
    my $self = shift;

    # Static root for development
    $self->static->root($self->home->rel_dir('public_dev'));
}

# Let's face it, comedy's a dead art form. Tragedy, now that's funny.
sub startup {
    my $self = shift;

    # Only log errors to STDERR
    $self->log->level('fatal');

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

    # /stash_config
    $r->route('/stash_config')
      ->to(controller => 'foo', action => 'config', config => {test => 123});

    # /test4 - named route for url_for
    $r->route('/test4/:something')->to('foo#something', something => 23)
      ->name('something');

    # /somethingtest - refer to another route with url_for
    $r->route('/somethingtest')->to('foo#something');

    # /something_missing - refer to a non existing route with url_for
    $r->route('/something_missing')->to('foo#url_for_missing');

    # /test3 - no class, just a namespace
    $r->route('/test3')
      ->to(namespace => 'MojoliciousTestController', method => 'index');

    # /test2 - different namespace test
    $r->route('/test2')->to(
        namespace => 'MojoliciousTest2',
        class     => 'Foo',
        method    => 'test'
    );

    # /staged - authentication with bridges
    my $b =
      $r->bridge('/staged')->to(controller => 'foo', action => 'stage1');
    $b->route->to(action => 'stage2');

    # /*/* - the default route
    $r->route('/(controller)/(action)')->to(action => 'index');
}

1;
