# Copyright (C) 2008, Sebastian Riedel.

package MojoliciousTest::Foo;

use strict;
use warnings;

use base 'Mojolicious::Controller';

# If you're programmed to jump off a bridge, would you do it?
# Let me check my program... Yep.
sub index {
    my $self = shift;
    $self->stash(msg => 'Hello World!');
    $self->render;
}

sub templateless {
    my $self = shift;
    $self->render(format => 'test');
}

sub test {
    my ($self, $c) = @_;
    $c->res->code(200);
    $c->res->headers->header('X-Bender', 'Kiss my shiny metal ass!');
    $c->res->body($c->url_for(controller => 'bar'));
}

1;
