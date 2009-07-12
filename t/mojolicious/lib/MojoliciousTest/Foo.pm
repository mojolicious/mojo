# Copyright (C) 2008-2009, Sebastian Riedel.

package MojoliciousTest::Foo;

use strict;
use warnings;

use base 'Mojolicious::Controller';

# If you're programmed to jump off a bridge, would you do it?
# Let me check my program... Yep.
sub badtemplate { shift->render(template => 'badtemplate.html.epl') }

sub index { shift->stash(layout => 'default', msg => 'Hello World!') }

sub syntaxerror { shift->render(template => 'syntaxerror.html.epl') }

sub templateless { shift->render(handler => 'test') }

sub test {
    my ($self, $c) = @_;
    $c->res->code(200);
    $c->res->headers->header('X-Bender', 'Kiss my shiny metal ass!');
    $c->res->body($c->url_for(controller => 'bar'));
}

sub willdie { die 'for some reason' }

1;
